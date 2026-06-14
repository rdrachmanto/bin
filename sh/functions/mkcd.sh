#!/usr/bin/env sh

mkcd() {
    __print_usage() {
        cat <<EOF
Usage: mkcd [-t] <dirname>
       
Options:
-t    Append a timestamp to the directory name
-h    Show this help message
EOF
    }

    WITH_TS=0
    while getopts ":th" opt; do
        case ${opt} in
            t) WITH_TS=1 ;;
            h)
                __print_usage
                return 0
                ;;
            \?) echo "Invalid option"
                exit 1
                ;;
        esac
    done

    shift $((OPTIND - 1))

    dirname="${1}"

    if [ $WITH_TS -eq 1 ]; then
        dirname="${dirname}-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "${dirname}"
    cd "${dirname}" || exit
}
