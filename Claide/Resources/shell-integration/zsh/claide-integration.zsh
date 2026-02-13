# ABOUTME: Zsh shell integration for Claide terminal.
# ABOUTME: Provides OSC 7 (directory tracking) and OSC 133 (prompt markers).

# OSC 7: Report working directory to the terminal on every prompt.
# Encodes the path as a file:// URL with percent-encoded special characters.
__claide_osc7() {
    local url_path=""
    local i ch
    local LC_CTYPE=C
    for (( i = 1; i <= ${#PWD}; i++ )); do
        ch="${PWD[i]}"
        if [[ "$ch" =~ '[/._~A-Za-z0-9-]' ]]; then
            url_path+="$ch"
        else
            printf -v ch '%%%02X' "'$ch"
            url_path+="$ch"
        fi
    done
    printf '\e]7;file://%s%s\a' "${HOST}" "$url_path"
}

# OSC 133 (FinalTerm protocol): Mark prompt boundaries.
# Ghostty uses these markers to clear old prompt content on resize
# before the shell redraws, preventing garbled reflow artifacts.
typeset -gi __claide_cmd_state=0

__claide_mark_prompt() {
    builtin emulate -L zsh -o no_warn_create_global -o no_aliases

    # Close previous command output region.
    if (( __claide_cmd_state == 1 )); then
        # Command was running — close with exit status.
        builtin print -nu 2 '\e]133;D;'$?'\a'
    elif (( __claide_cmd_state == 2 )); then
        builtin print -nu 2 '\e]133;D\a'
    fi

    # Embed prompt-start marker in PS1 so it's re-emitted on SIGWINCH.
    # %{...%} tells zsh the enclosed text is zero-width (no cursor movement).
    builtin local mark=$'%{\e]133;A\a%}'
    [[ $PS1 == *$mark* ]] || PS1=${mark}${PS1}

    __claide_cmd_state=2
}

__claide_mark_output() {
    builtin emulate -L zsh -o no_warn_create_global -o no_aliases

    # Strip prompt-start marker from PS1 before command runs.
    PS1=${PS1//$'%{\e]133;A\a%}'}

    # Mark command output start.
    builtin print -nu 2 '\e]133;C\a'
    __claide_cmd_state=1
}

# Register hooks. Append to end so we run after prompt theme plugins
# (e.g., oh-my-posh) that overwrite PS1 in their own precmd hooks.
precmd_functions=(${precmd_functions:#__claide_osc7} __claide_osc7)
precmd_functions=(${precmd_functions:#__claide_mark_prompt} __claide_mark_prompt)
preexec_functions=(${preexec_functions:#__claide_mark_output} __claide_mark_output)
