# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line


# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# Store human readable time in a variable as specified by the caller
	typeset -g "${var}"="${human}"
}

# Stores (into prompt_pure_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_pure_cmd_exec_time=
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
		prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
	}
}

prompt_pure_preexec() {
	typeset -g prompt_pure_cmd_timestamp=$EPOCHSECONDS
}

# Change the colors if their value are different from the current ones.
prompt_pure_set_colors() {
	local color_temp key value
	for key value in ${(kv)prompt_pure_colors}; do
		zstyle -t ":prompt:pure:$key" color "$value"
		case $? in
			1) # The current style is different from the one from zstyle.
				zstyle -s ":prompt:pure:$key" color color_temp
				prompt_pure_colors[$key]=$color_temp ;;
			2) # No style is defined.
				prompt_pure_colors[$key]=$prompt_pure_colors_default[$key] ;;
		esac
	done
}

prompt_pure_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_pure_async_render_requested

	# Initialize the preprompt array.
	local -a preprompt_parts

	# Username and machine, if applicable.
	[[ -n $prompt_pure_state[username] ]] && preprompt_parts+=($prompt_pure_state[username])

	# Git branch and dirty status info.
	typeset -gA prompt_pure_vcs_info
  local gitinfo
  if [[ -n $prompt_pure_vcs_info[root] ]]; then
    gitinfo=("%F{$prompt_pure_colors[git:root]}"'$prompt_pure_vcs_info[root]%f')
  fi
  if ([[ -n $prompt_pure_vcs_info[root] ]] && [[ -n $prompt_pure_vcs_info[branch] ]]); then
    gitinfo=("${gitinfo}@")
  fi
	if [[ -n $prompt_pure_vcs_info[branch] ]]; then
		gitinfo=("${gitinfo}""%F{$prompt_pure_colors[git:branch]}"'${prompt_pure_vcs_info[branch]}${prompt_pure_git_status}')
	fi
  if ([[ -n $prompt_pure_vcs_info[root] ]] || [[ -n $prompt_pure_vcs_info[branch] ]]); then
    preprompt_parts+=$gitinfo
  fi

	# Git action (for example, merge).
	if [[ -n $prompt_pure_vcs_info[action] ]]; then
		preprompt_parts+=("%F{$prompt_pure_colors[git:action]}"'$prompt_pure_vcs_info[action]%f')
	fi

  # AWS profile
	if [[ -n $AWS_PROFILE ]]; then
		preprompt_parts+=("%F{yellow}${AWS_PROFILE}%f")
	fi

  # Kubernetes context
  local kubectx
	if [[ -n $prompt_pure_kubernetes_context ]]; then
    kubectx=("%F{$prompt_pure_colors[kube:context]}${prompt_pure_kubernetes_context}%f")
  fi
  if ([[ -n $prompt_pure_kubernetes_context ]] && [[ -n $prompt_pure_kubernetes_namespace ]]); then
		kubectx=("${kubectx}:")
	fi
	[[ -n $prompt_pure_kubernetes_namespace ]] && kubectx=("${kubectx}%F{$prompt_pure_colors[kube:namespace]}${prompt_pure_kubernetes_namespace}%f")
  if ([[ -n $prompt_pure_kubernetes_context ]] || [[ -n $prompt_pure_kubernetes_namespace ]]); then
  preprompt_parts+=$kubectx
  fi

	# Execution time.
	[[ -n $prompt_pure_cmd_exec_time ]] && preprompt_parts+=('%F{$prompt_pure_colors[execution_time]}${prompt_pure_cmd_exec_time}%f')

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		# Remove everything from the prompt until the newline. This
		# removes the preprompt and only the original PROMPT remains.
		cleaned_ps1=${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	# Construct the new prompt with a clean preprompt.
	local -ah ps1
	ps1=(
		${(j. .)preprompt_parts}  # Join parts, space separated.
		$prompt_newline           # Separate preprompt and prompt.
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"
  RPROMPT='%F{${prompt_pure_colors[path]}}%(5~|%-1~/.../%3~|%~)%f %*'

	# Expand the prompt for future comparision.
	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"

	if [[ $1 == precmd ]]; then
		# Initial newline, for spaciousness.
		[[ -n $PURE_NEWLINE ]] && print
	elif [[ $prompt_pure_last_prompt != $expanded_prompt ]]; then
		# Redraw the prompt.
		prompt_pure_reset_prompt
	fi

	typeset -g prompt_pure_last_prompt=$expanded_prompt
}

prompt_pure_precmd() {
	setopt localoptions noshwordsplit

	# Check execution time and store it in a variable.
	prompt_pure_check_cmd_exec_time
	unset prompt_pure_cmd_timestamp

	# Modify the colors if some have changed..
	prompt_pure_set_colors

	# Perform async Git dirty check and fetch.
	prompt_pure_async_tasks

	# Make sure VIM prompt is reset.
	prompt_pure_reset_prompt_symbol

	# Print the preprompt.
	prompt_pure_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Pure might not be working correctly."
		print "For more information, see: https://github.com/sindresorhus/pure#oh-my-zsh"
		unset ZSH_THEME  # Only show this warning once.
	fi
}

prompt_pure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	# List all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # Split line on spaces.
		aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
		shift parts                   # Remove `aliasname`

		# Check alias for pull or fetch. Must be exact match.
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_pure_async_vcs_info() {
	setopt localoptions noshwordsplit

	# Configure `vcs_info` inside an async task. This frees up `vcs_info`
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# Only export four message variables from `vcs_info`.
	zstyle ':vcs_info:*' max-exports 4
  # Export branch (%b), root (%r) Git toplevel (%R), action (rebase/cherry-pick) (%a)
	zstyle ':vcs_info:git*' formats '%b' '%r' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[branch]=$vcs_info_msg_0_
  info[root]=$vcs_info_msg_1_
	info[top]=$vcs_info_msg_2_
	info[action]=$vcs_info_msg_3_

	print -r - ${(@kvq)info}
}

# Fastest possible way to check if a Git repo is dirty.
prompt_pure_async_git_status() {
	local file_status status_summary untracked unstaged staged

	git --no-optional-locks status --porcelain --ignore-submodules -unormal | while IFS='' read -r file_status; do
    if [[ "${file_status:0:2}" == '??' ]]; then
      untracked='%F{red}●'
    else
      [[ "${file_status:0:1}" != ' ' ]] && staged='%F{green}●'
      [[ "${file_status:1:1}" != ' ' ]] && unstaged='%F{yellow}●'
    fi
	done
	status_summary="${untracked}${unstaged}${staged}"
  [[ -n $status_summary ]] && echo "${status_summary}%f"
}

# Try to lower the priority of the worker so that disk heavy operations
# like `git status` has less impact on the system responsivity.
prompt_pure_async_renice() {
	setopt localoptions noshwordsplit

	if command -v renice >/dev/null; then
		command renice +15 -p $$
	fi

	if command -v ionice >/dev/null; then
		command ionice -c 3 -p $$
	fi
}

prompt_pure_async_init() {
	typeset -g prompt_pure_async_inited
	if ((${prompt_pure_async_inited:-0})); then
		return
	fi
	prompt_pure_async_inited=1
	async_start_worker "prompt_pure" -u -n
	async_register_callback "prompt_pure" prompt_pure_async_callback
	async_worker_eval "prompt_pure" prompt_pure_async_renice
}

prompt_pure_async_kubernetes_context() {
	setopt localoptions noshwordsplit
  local kube_ctx=$(command kubectl config current-context 2>/dev/null)
  echo "${kube_ctx:-N/A}"
}

prompt_pure_async_kubernetes_namespace() {
	setopt localoptions noshwordsplit
  local kube_ns=$(command kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
  echo "${kube_ctx:-default}"
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# Initialize the async worker.
	prompt_pure_async_init

	# Update the current working directory of the async worker.
	async_worker_eval "prompt_pure" builtin cd -q $PWD

	typeset -gA prompt_pure_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_pure_vcs_info[pwd]}* ]]; then
		# Stop any running async jobs.
		async_flush_jobs "prompt_pure"

		# Reset Git preprompt variables, switching working tree.
		unset prompt_pure_git_status
		unset prompt_pure_git_last_dirty_check_timestamp
		prompt_pure_vcs_info[branch]=
    prompt_pure_vcs_info[root]=
		prompt_pure_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_pure" prompt_pure_async_vcs_info

	# Only perform tasks inside a Git working tree.
	[[ -n $prompt_pure_vcs_info[top] ]] || return

	prompt_pure_async_refresh
}

prompt_pure_async_refresh() {
	setopt localoptions noshwordsplit

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_pure" prompt_pure_async_git_status
	fi
	async_job "prompt_pure" prompt_pure_async_kubernetes_context
	async_job "prompt_pure" prompt_pure_async_kubernetes_namespace
}

prompt_pure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		\[async])
			# Handle all the errors that could indicate a crashed
			# async worker. See zsh-async documentation for the
			# definition of the exit codes.
			if (( code == 2 )) || (( code == 3 )) || (( code == 130 )); then
				# Our worker died unexpectedly, try to recover immediately.
				# TODO(mafredri): Do we need to handle next_pending
				#                 and defer the restart?
				typeset -g prompt_pure_async_inited=0
				async_stop_worker prompt_pure
				prompt_pure_async_init   # Reinit the worker.
				prompt_pure_async_tasks  # Restart all tasks.

				# Reset render state due to restart.
				unset prompt_pure_async_render_requested
			fi
			;;
		\[async/eval])
			if (( code )); then
				# Looks like async_worker_eval failed,
				# rerun async tasks just in case.
				prompt_pure_async_tasks
			fi
			;;
		prompt_pure_async_vcs_info)
			local -A info
			typeset -gA prompt_pure_vcs_info

			# Parse output (z) and unquote as array (Q@).
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi
			# Check if Git top-level has changed.
			if [[ $info[top] = $prompt_pure_vcs_info[top] ]]; then
				# If the stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be top-level, so we update pwd.
				if [[ $prompt_pure_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_pure_vcs_info[pwd]=$PWD
				fi
			else
				# Store $PWD to detect if we (maybe) left the Git path.
				prompt_pure_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# The update has a Git top-level set, which means we just entered a new
			# Git directory. Run the async refresh tasks.
			[[ -n $info[top] ]] && [[ -z $prompt_pure_vcs_info[top] ]] && prompt_pure_async_refresh

			# Always update branch, top-level and stash.
			prompt_pure_vcs_info[branch]=$info[branch]
      prompt_pure_vcs_info[root]=$info[root]
			prompt_pure_vcs_info[top]=$info[top]
			prompt_pure_vcs_info[action]=$info[action]

			do_render=1
			;;
		prompt_pure_async_git_aliases)
			if [[ -n $output ]]; then
				# Append custom Git aliases to the predefined ones.
				prompt_pure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pure_async_git_status)
			local prev_status=$prompt_pure_git_status
			if [[ -z "$output" ]]; then
				unset prompt_pure_git_status
			else
				typeset -g prompt_pure_git_status=" $output"
			fi

			[[ $prev_status != $prompt_pure_git_status ]] && do_render=1

			# When `prompt_pure_git_last_dirty_check_timestamp` is set, the Git info is displayed
			# in a different color. To distinguish between a "fresh" and a "cached" result, the
			# preprompt is rendered before setting this variable. Thus, only upon the next
			# rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_kubernetes_context)
			local prev_context=$prompt_pure_kubernetes_context
			if (( code == 0 )); then
				typeset -g prompt_pure_kubernetes_context="$output"
			else
				unset prompt_pure_kubernetes_context
			fi

			[[ $prev_context != $prompt_pure_kubernetes_context ]] && do_render=1
			;;
    prompt_pure_async_kubernetes_namespace)
      local prev_namespace=$prompt_pure_kubernetes_namespace
      if (( code == 0 )); then
				typeset -g prompt_pure_kubernetes_namespace="$output"
      else
				unset prompt_pure_kubernetes_namespace
      fi
			[[ $prev_namespace != $prompt_pure_kubernetes_namespace ]] && do_render=1
      ;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_pure_async_render_requested=1
		return
	fi

	[[ ${prompt_pure_async_render_requested:-$do_render} = 1 ]] && prompt_pure_preprompt_render
	unset prompt_pure_async_render_requested
}

prompt_pure_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# When the context is "cont", PS2 is active and calling
		# reset-prompt will have no effect on PS1, but it will
		# reset the execution context (%_) of PS2 which we don't
		# want. Unfortunately, we can't save the output of "%_"
		# either because it is only ever rendered as part of the
		# prompt, expanding in-place won't work.
		return
	fi

	zle && zle .reset-prompt
}

prompt_pure_reset_prompt_symbol() {
	prompt_pure_state[prompt]=${PURE_PROMPT_SYMBOL:-❯}
}

prompt_pure_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_state[prompt]=${${KEYMAP/vicmd/${PURE_PROMPT_VICMD_SYMBOL:-❮}}/(main|viins)/${PURE_PROMPT_SYMBOL:-❯}}

	prompt_pure_reset_prompt
}

prompt_pure_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_reset_prompt_symbol

	# We can't perform a prompt reset at this point because it
	# removes the prompt marks inserted by macOS Terminal.
}

prompt_pure_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_PURE_SSH_CONNECTION}
	local username hostname
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost. Attempt detection via `who`.
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			# Who am I not supported, fallback to plain who.
			local -a who_in
			who_in=( ${(f)"$(who 2>/dev/null)"} )
			who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
		# Here we assume two non-consecutive periods represents a
		# hostname. This matches `foo.bar.baz`, but not `foo.bar`.
		local reHostname='([.][^. ]+){2}'

		# Usually the remote address is surrounded by parenthesis, but
		# not on all systems (e.g. busybox).
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			# Export variable to allow detection propagation inside
			# shells spawned by this one (e.g. tmux does not always
			# inherit the same tty, which breaks detection).
			export PROMPT_PURE_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	hostname='%F{$prompt_pure_colors[host]}@%m%f'
	# Show `username@host` if logged in through SSH.
	[[ -n $ssh_connection ]] && username='%F{$prompt_pure_colors[user]}%n%f'"$hostname"

	# Show `username@host` if inside a container.
	prompt_pure_is_inside_container && username='%F{$prompt_pure_colors[user]}%n%f'"$hostname"

	# Show `username@host` if root, with username in default color.
	[[ $UID -eq 0 ]] && username='%F{$prompt_pure_colors[user:root]}%n%f'"$hostname"

	typeset -gA prompt_pure_state
	prompt_pure_state[version]="1.13.0"
	prompt_pure_state+=(
		username "$username"
		prompt	 "${PURE_PROMPT_SYMBOL:-❯}"
	)
}

# Return true if executing inside a Docker or LXC container.
prompt_pure_is_inside_container() {
	local -r cgroup_file='/proc/1/cgroup'
	[[ -r "$cgroup_file" && "$(< $cgroup_file)" = *(lxc|docker)* ]] \
		|| [[ "$container" == "lxc" ]]
}

prompt_pure_system_report() {
	setopt localoptions noshwordsplit

	local shell=$SHELL
	if [[ -z $shell ]]; then
		shell=$commands[zsh]
	fi
	print - "- Zsh: $($shell --version) ($shell)"
	print -n - "- Operating system: "
	case "$(uname -s)" in
		Darwin)	print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*)	print "$(uname -s) ($(uname -r) $(uname -v) $(uname -m) $(uname -o))";;
	esac
	print - "- Terminal program: ${TERM_PROGRAM:-unknown} (${TERM_PROGRAM_VERSION:-unknown})"
	print -n - "- Tmux: "
	[[ -n $TMUX ]] && print "yes" || print "no"

	local git_version
	git_version=($(git --version))  # Remove newlines, if hub is present.
	print - "- Git: $git_version"

	print - "- Pure state:"
	for k v in "${(@kv)prompt_pure_state}"; do
		print - "    - $k: \`${(q-)v}\`"
	done
	print - "- zsh-async version: \`${ASYNC_VERSION}\`"
	print - "- PROMPT: \`$(typeset -p PROMPT)\`"
	print - "- Colors: \`$(typeset -p prompt_pure_colors)\`"
	print - "- TERM: \`$(typeset -p TERM)\`"
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"

	local ohmyzsh=0
	typeset -la frameworks
	(( $+ANTIBODY_HOME )) && frameworks+=("Antibody")
	(( $+ADOTDIR )) && frameworks+=("Antigen")
	(( $+ANTIGEN_HS_HOME )) && frameworks+=("Antigen-hs")
	(( $+functions[upgrade_oh_my_zsh] )) && {
		ohmyzsh=1
		frameworks+=("Oh My Zsh")
	}
	(( $+ZPREZTODIR )) && frameworks+=("Prezto")
	(( $+ZPLUG_ROOT )) && frameworks+=("Zplug")
	(( $+ZPLGM )) && frameworks+=("Zplugin")

	(( $#frameworks == 0 )) && frameworks+=("None")
	print - "- Detected frameworks: ${(j:, :)frameworks}"

	if (( ohmyzsh )); then
		print - "    - Oh My Zsh:"
		print - "        - Plugins: ${(j:, :)plugins}"
	fi
}

prompt_pure_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# Borrowed from `promptinit`. Sets the prompt options in case Pure was not
	# initialized via `promptinit`.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	# The `add-zle-hook-widget` function is not guaranteed to be available.
	# It was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	# Set the colors.
	typeset -gA prompt_pure_colors_default prompt_pure_colors
	prompt_pure_colors_default=(
		execution_time       yellow
		git:branch           blue
    git:root             blue
		git:branch:cached    red
		git:action           yellow
		host                 242
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:continuation  242
		user                 242
		user:root            default
		virtualenv           242
    kube:context          magenta
    kube:namespace        magenta
	)
	prompt_pure_colors=("${(@kv)prompt_pure_colors_default}")

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	prompt_pure_state_setup

	zle -N prompt_pure_reset_prompt
	zle -N prompt_pure_update_vim_prompt_widget
	zle -N prompt_pure_reset_vim_prompt_widget
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_pure_reset_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select prompt_pure_update_vim_prompt_widget
	fi

	# If a virtualenv is activated, display it in grey.
	PROMPT='%(12V.%F{$prompt_pure_colors[virtualenv]}%12v%f .)'

	# Prompt turns red if the previous command didn't exit with 0.
	PROMPT_INDICATOR='%(?.%F{$prompt_pure_colors[prompt:success]}.%F{$prompt_pure_colors[prompt:error]})${prompt_pure_state[prompt]}%f '
	PROMPT+=$PROMPT_INDICATOR

	# Indicate continuation prompt by … and use a darker color for it.
	PROMPT2='%F{$prompt_pure_colors[prompt:continuation]}… %(1_.%_ .%_)%f'$PROMPT_INDICATOR

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_pure_debug_depth
	prompt_pure_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both filename and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_pure_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_pure_debug_depth[2]}:#${(%)prompt_pure_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_pure_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an ampty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Guard against Oh My Zsh themes overriding Pure.
	unset ZSH_THEME
}

prompt_pure_setup "$@"

short_prompt() {
  echo '%(?.%F{$prompt_pure_colors[prompt:success]}.%F{$prompt_pure_colors[prompt:error]})${prompt_pure_state[prompt]}%f '
}

truncate-prompt() {
  # short="%(?.%F{$prompt_pure_colors[prompt:success]}.%F{$prompt_pure_colors[prompt:error]})${prompt_pure_state[prompt]}%f "
  if [[ $PROMPT != $PROMPT_INDICATOR ]]; then
    PROMPT=$PROMPT_INDICATOR
    zle .reset-prompt
  fi
}

zle-line-finish() { truncate-prompt }
zle -N zle-line-finish

trap 'set-short-prompt; return 130' INT
