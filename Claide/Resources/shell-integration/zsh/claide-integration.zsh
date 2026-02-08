# Claide zsh shell integration.
# Provides OSC 7 directory tracking and other terminal hooks.

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

# Register as a precmd hook (runs before each prompt)
precmd_functions=(${precmd_functions:#__claide_osc7} __claide_osc7)
