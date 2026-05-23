#!/usr/bin/env bash

edit() {
  file="$(fd --type f | fzf)" || return
  "${VISUAL:-${EDITOR:-vim}}" "$file"
}

cdf() {
  dir="$(fd --type d | fzf)" || return 
  cd "${dir}" || return
}

if [[ -n "$ZSH_VERSION" ]]; then
  historian() {
    cmd="$(history 1 | sed 's/^ *[0-9]\+ *//' | fzf --tac --no-sort)" || return

    BUFFER="$cmd"
    CURSOR=${#BUFFER}
  }

  zle -N historian 
  bindkey '^R' historian 
elif [[ -n "$BASH_VERSION" ]]; then
  historian() {
    cmd="$(history 1 | sed 's/^ *[0-9]\+ *//' | fzf --tac --no-sort)" || return

    READLINE_LINE="$cmd"
    READLINE_POINT=${#READLINE_LINE}
  }

  bind -x '"\C-r": historian'
fi
