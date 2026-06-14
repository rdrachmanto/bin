#!/usr/bin/env sh

if [ -n "$ZSH_VERSION" ]; then
    historian() {
        cmd="$(history 1 | sed 's/^ *[0-9]\+ *//' | fzf --tac --no-sort)" || return

        BUFFER="$cmd"
        CURSOR=${#BUFFER}
    }

    zle -N historian 
    bindkey '^R' historian 
elif [ -n "$BASH_VERSION" ]; then
    historian() {
        cmd="$(history 1 | sed 's/^ *[0-9]\+ *//' | fzf --tac --no-sort)" || return

        READLINE_LINE="$cmd"
        READLINE_POINT=${#READLINE_LINE}
    }

    bind -x '"\C-r": historian'
fi
