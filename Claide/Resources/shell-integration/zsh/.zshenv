# Claide shell integration entry point.
# Restores the original ZDOTDIR then sources Claide's hooks.

# Restore original ZDOTDIR so the rest of zsh startup (.zprofile, .zshrc,
# .zlogin) proceeds normally from the user's home or custom ZDOTDIR.
if [[ -n "$CLAIDE_ORIG_ZDOTDIR" ]]; then
    ZDOTDIR="$CLAIDE_ORIG_ZDOTDIR"
else
    unset ZDOTDIR
fi
unset CLAIDE_ORIG_ZDOTDIR

# Source the user's original .zshenv (if any)
if [[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
    source "${ZDOTDIR:-$HOME}/.zshenv"
fi

# Install Claide shell hooks
builtin source "${${(%):-%x}:A:h}/claide-integration.zsh"
