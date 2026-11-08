# ~/.bashrc -- Maria Padilha default interactive shell setup.
#
# Keep this file free of secrets.  Machine-local environment belongs in the
# user's own files (for example ~/.config/hypr/hyprland/env.local.lua for
# Hyprland); it is never part of /etc/skel.

# Load the system-wide interactive configuration first, then keep only the
# settings below as user defaults.
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# Non-interactive shells (scripts, SSH commands) have nothing to configure.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend checkwinsize

# The desktop and the dotfiles both install user commands here.
case ":${PATH}:" in
    *:"${HOME}/.local/bin":*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}" ;;
esac
export PATH

export EDITOR="${EDITOR:-micro}"
export VISUAL="${VISUAL:-${EDITOR}}"

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# A readable prompt that does not depend on a theme or a network connection.
if [ -n "${PS1:-}" ] && [ -z "${MARIA_PADILHA_PS1:-}" ]; then
    PS1='\[\e[38;5;166m\]\u@\h\[\e[0m\] \[\e[38;5;179m\]\w\[\e[0m\] \$ '
fi
