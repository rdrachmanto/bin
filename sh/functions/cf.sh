#!/usr/bin/env sh 

cf() {
    dir="$(fd --type d | fzf)" || exit
    cd "${dir}" || exit
}

