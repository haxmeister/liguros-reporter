# Complete option names, or complete filenames/dirs as normal
# bashdefault requires Bash >=3.0
[ -n "$BASH_VERSINFO" ] || return
(( BASH_VERSINFO[0] >= 3 )) || return
complete -W '
    --config
    --update-config
    --list-config
    --show-json
    --send
    --verbose
    --debug
    --help
    --version
' -o bashdefault -o default funtoo-report
