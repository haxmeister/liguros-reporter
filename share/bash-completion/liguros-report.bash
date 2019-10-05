# Complete option names, or complete filenames/dirs as normal
# bashdefault requires Bash >=3.0
[ -n "$BASH_VERSINFO" ] || return
(( BASH_VERSINFO[0] >= 3 )) || return
_liguros-report() {
    COMPREPLY=( $(compgen -W '
        --config
        --update-config
        --list-config
        --show-json
        --send
        --verbose
        --debug
        --help
        --version
    ' -- "$2" ) )
}
complete -F _liguros-report -o bashdefault -o default liguros-report
