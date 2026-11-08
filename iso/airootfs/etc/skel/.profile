# ~/.profile -- Maria Padilha login shell setup.
#
# This file is read by login shells that are not Bash.  Bash login shells read
# ~/.bash_profile or ~/.profile; this keeps the same PATH for both.

# Prefer the per-user command directory.  Do not add a source checkout path:
# an installed system only needs the commands from /usr/bin.
case ":${PATH}:" in
    *:"${HOME}/.local/bin":*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}" ;;
esac
export PATH

# Bash users get the interactive settings from ~/.bashrc.  Other shells only
# need the environment above.
if [ -n "${BASH_VERSION:-}" ] && [ -f "${HOME}/.bashrc" ]; then
    . "${HOME}/.bashrc"
fi
