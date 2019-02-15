# ╭─────────────╥────────────────────╮
# │ Author:     ║ File:              │
# │ Andrey Orst ║ tagbar.kak         │
# ╞═════════════╩════════════════════╡
# │ Class outline viewer for Kakoune │
# ╞══════════════════════════════════╡
# │ GitHub.com/andreyorst/tagbar.kak │
# ╰──────────────────────────────────╯

declare-option -docstring "name of the client in which all source code jumps will be executed" \
str jumpclient
declare-option -docstring "name of the client in which utilities display information" \
str tagbarclient 'tagbarclient'

declare-option -docstring "Sort tags in tagbar buffer.
  Possible values:
    true:     Sort tags.
    false:    Do not sort tags.
    foldcase: The foldcase value specifies case insensitive (or case-folded) sorting.
  Default value: true" \
str tagbar_sort "true"

declare-option -docstring "display anonymous tags.
  Possible values: true, false
  Default value: true" \
str tagbar_display_anon "true"

declare-option -docstring "Choose how to split current pane to display tagbar panel.
  Possible values: vertical, horizontal
  Default value: horizontal" \
str tagbar_split "horizontal"

declare-option -docstring "Choose where to display tagbar panel.
  Possible values: left, right
  Default value: right
When tagbar_split is set to 'horizontal', 'left' and 'right' will make split above or below current pane respectively." \
str tagbar_side "right"

declare-option -docstring "The size of tagbar pane. Can be either a number of columns or size in percentage" \
str tagbar_size '28'

declare-option -hidden -docstring "state of tagbar" \
str tagbar_active 'false'

add-highlighter shared/tagbar group
add-highlighter shared/tagbar/category regex ^[^\s]{2}[^\n]+$ 0:keyword
add-highlighter shared/tagbar/info     regex (?<=:\h)(.*?)$   1:comment

hook -group tagbar-syntax global WinSetOption filetype=tagbar %{
    add-highlighter window/tagbar ref tagbar
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter window/tagbar
    }
}

define-command tagbar-enable %{
    evaluate-commands %sh{
        [ "$kak_opt_tagbar_active" = "true" ] && exit
        if [ -z "$kak_opt_tagbar_kinds" ]; then
            printf "%s\n" "echo -markup %{{Information}Filetype '$kak_opt_filetype' is not supported by Tagbar}"
            exit
        fi

        [ -z "$kak_opt_jumpclient" ] && printf "%s\n" "set-option global jumpclient $kak_client"

        tagbar_cmd="rename-client %opt{tagbarclient}
                    set-option global tagbar_active true
                    evaluate-commands -client %opt{jumpclient} tagbar-update
                    hook -group tagbar-watchers global WinDisplay .* %{ tagbar-update }
                    hook -group tagbar-watchers global BufWritePost .* %{ tagbar-update }
                    hook -group tagbar-watchers global WinSetOption tagbar_sort=.* %{ tagbar-update }
                    hook -group tagbar-watchers global WinSetOption tagbar_display_anon=.* %{ tagbar-update }"

        if [ -n "$TMUX" ]; then
            [ "$kak_opt_tagbar_split" = "vertical" ] && split="-v" || split="-h"
            [ "$kak_opt_tagbar_side" = "left" ] && side="-b" || side=
            [ -n "${kak_opt_tagbar_size%%*%}" ] && measure="-p" || measure="-l"
            tmux split-window $split $side $measure ${kak_opt_tagbar_size%%%*} kak -c $kak_session -e "$tagbar_cmd"
        elif [ -n "$kak_opt_termcmd" ]; then
            ( $kak_opt_termcmd "sh -c 'kak -c $kak_session -e \"$tagbar_cmd\"'" ) > /dev/null 2>&1 < /dev/null &
        fi
    }
}

define-command tagbar-disable %{
    set-option global tagbar_active 'false'
    remove-hooks global tagbar-watchers
    try %{ delete-buffer *tagbar* } catch %{ echo -debug "Can't close tagbar buffer. Perhaps it was closed by something else" }
    try %{
        evaluate-commands -client %opt{tagbarclient} quit
        set-option global tagbarclient ''
    } catch %{
        echo -debug "Can't close tagbar client. Perhaps it was closed by something else"
    }
}

define-command tagbar-toggle %{ evaluate-commands %sh{
    if [ "${kak_opt_tagbar_active}" = "true" ]; then
        printf "tagbar-disable\n"
    else
        printf "tagbar-enable\n"
    fi
}}

define-command -hidden tagbar-update %{ evaluate-commands %sh{
    if [ "${kak_opt_tagbar_active}" != "true" ]; then
        exit
    fi
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/tagbar.XXXXXXXX")
    tags="$tmp/tags"
    tagbar_buffer="$tmp/buffer"
    fifo="${tmp}/fifo"
    mkfifo ${fifo}

    ctags --sort="${kak_opt_tagbar_sort:-yes}" -f "$tags" "$kak_buffile" > /dev/null 2>&1

    eval "set -- $kak_opt_tagbar_kinds"
    while [ $# -gt 0 ]; do
        export description="$2"
        readtags -t "$tags" -Q '(eq? $kind "'$1'")' -l | awk -F '\t|\n' '
            /^__anon[a-zA-Z0-9]+/ {
                if ( ENVIRON["kak_opt_tagbar_display_anon"] != "true" ) {
                    $0=""
                }
            }
            /[^\t]+\t[^\t]+\t\/\^.*\$?\// {
                tag = $1;
                info = $0; sub(".*\t/\\^", "", info); sub("\\$?/$", "", info); gsub(/^[\t ]+/, "", info); gsub("\\\\/", "/", info);
                if (length(info) != 0)
                    out = out "  " tag ":\t" info "\n"
            }
            END {
                if (length(out) != 0) {
                    print ENVIRON["description"]
                    print out
                }
            }
        ' >> $tagbar_buffer
        shift 2
    done

    printf "%s\n" "evaluate-commands -client %opt{tagbarclient} %{
                       edit! -fifo ${fifo} *tagbar*
                       set-option buffer filetype tagbar
                       map buffer normal '<ret>' '<a-h>;/:<c-v><c-i><ret><a-h>2<s-l><a-l><a-;>:<space>tagbar-jump $kak_bufname<ret>'
                       try %{
                           remove-highlighter window/wrap
                           remove-highlighter window/numbers
                           remove-highlighter window/whitespace
                           remove-highlighter window/wrap
                           set-option window tabstop 1
                       }
                   }"

    ( cat $tagbar_buffer > $fifo; rm -rf $tmp ) > /dev/null 2>&1 < /dev/null &

}}

define-command tagbar-jump -params 1 %{
    evaluate-commands -client %opt{jumpclient} %sh{
        printf "%s:\t%s\n" "$kak_selection" "$1" | awk -F ':\t' '{
                keys = $2; gsub(/</, "<lt>", keys); gsub(/\t/, "<c-v><c-i>", keys);
                gsub("&", "&&", keys); gsub("?", "??", keys);
                select = $1; gsub(/</, "<lt>", select); gsub(/\t/, "<c-v><c-i>", select);
                gsub("&", "&&", select); gsub("?", "??", select);
                bufname = $3; gsub("&", "&&", bufname); gsub("?", "??", bufname);
                print "try %? buffer %&" bufname "&; execute-keys %&/\\Q" keys "<ret>vc& ? catch %? echo -markup %&{Error}unable to find tag& ?; try %? execute-keys %&s\\Q" select "<ret>& ?"
            }'
    }
    try %{ focus %opt{jumpclient} }
}


# This section defines different kinds for ctags supported languages and their kinds
# Full list of supported languages can be obtained by evaluating `ctags --list-kinds' command
declare-option -hidden str-list tagbar_kinds

try %{
    hook global WinSetOption filetype=c %{
        set-option window tagbar_kinds 'd' 'macro definitions' 'e' 'enumerators' 'f' 'function definitions' 'g' 'enumeration names' 'h' 'included header files' 'm' 'struct, and union members' 's' 'structure names' 't' 'typedefs' 'u' 'union names' 'v' 'variable definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=cpp %{
        set-option window tagbar_kinds 'd' 'macro definitions' 'e' 'enumerators' 'f' 'function definitions' 'g' 'enumeration names' 'h' 'included header files' 'm' 'class, struct, and union members' 's' 'structure names' 't' 'typedefs' 'u' 'union names' 'v' 'variable definitions' 'c' 'classes' 'n' 'namespaces'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ada %{
        set-option window tagbar_kinds 'P' 'package specifications' 'p' 'packages' 't' 'types' 'u' 'subtypes' 'c' 'record type components' 'l' 'enum type literals' 'v' 'variables' 'f' 'generic formal parameters' 'n' 'constants' 'x' 'user defined exceptions' 'R' 'subprogram specifications' 'r' 'subprograms' 'K' 'task specifications' 'k' 'tasks' 'O' 'protected data specifications' 'o' 'protected data' 'e' 'task/protected data entries' 'b' 'labels' 'i' 'loop/declare identifiers' 'S' '(ctags internal use)'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ant %{
        set-option window tagbar_kinds 'p' 'projects' 't' 'targets' 'P' 'properties(global)' 'i' 'antfiles'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=asciidoc %{
        set-option window tagbar_kinds 'c' 'chapters' 's' 'sections' 'S' 'level 2 sections' 't' 'level 3 sections' 'T' 'level 4 sections' 'u' 'level 5 sections' 'a' 'anchors'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=asm %{
        set-option window tagbar_kinds 'd' 'defines' 'l' 'labels' 'm' 'macros' 't' 'types' 's' 'sections'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=asp %{
        set-option window tagbar_kinds 'd' 'constants' 'c' 'classes' 'f' 'functions' 's' 'subroutines' 'v' 'variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=autoconf %{
        set-option window tagbar_kinds 'p' 'packages' 't' 'templates' 'm' 'autoconf macros' 'w' 'options specified with --with-...' 'e' 'options specified with --enable-...' 's' 'substitution keys' 'c' 'automake conditions' 'd' 'definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=autoit %{
        set-option window tagbar_kinds 'f' 'functions' 'r' 'regions' 'g' 'global variables' 'l' 'local variables' 'S' 'included scripts'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=automake %{
        set-option window tagbar_kinds 'd' 'directories' 'P' 'programs' 'M' 'manuals' 'T' 'ltlibraries' 'L' 'libraries' 'S' 'scripts' 'D' 'datum' 'c' 'conditions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=awk %{
        set-option window tagbar_kinds 'f' 'functions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=basic %{
        set-option window tagbar_kinds 'c' 'constants' 'f' 'functions' 'l' 'labels' 't' 'types' 'v' 'variables' 'g' 'enumerations'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=beta %{
        set-option window tagbar_kinds 'f' 'fragment definitions' 's' 'slots' 'v' 'patterns'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=clojure %{
        set-option window tagbar_kinds 'f' 'functions' 'n' 'namespaces'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=cmake %{
        set-option window tagbar_kinds 'f' 'functions' 'm' 'macros' 't' 'targets' 'v' 'variable definitions' 'D' 'options specified with -<a-d>' 'P' 'projects' 'r' 'regex'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=cpreprocessor %{
        set-option window tagbar_kinds 'd' 'macro definitions' 'h' 'included header files'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=css %{
        set-option window tagbar_kinds 'c' 'classes' 's' 'selectors' 'i' 'identities'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=csharp %{
        set-option window tagbar_kinds 'c' 'classes' 'd' 'macro definitions' 'e' 'enumerators' 'E' 'events' 'f' 'fields' 'g' 'enumeration names' 'i' 'interfaces' 'm' 'methods' 'n' 'namespaces' 'p' 'properties' 's' 'structure names' 't' 'typedefs'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ctags %{
        set-option window tagbar_kinds 'l' 'language definitions' 'k' 'kind definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=cobol %{
        set-option window tagbar_kinds 'p' 'paragraphs' 'd' 'data items' 'S' 'source code file' 'f' 'file descriptions' 'G' 'group items' 'P' 'program ids' 's' 'sections' 'D' 'divisions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=cuda %{
        set-option window tagbar_kinds 'd' 'macro definitions' 'e' 'enumerators' 'f' 'function definitions' 'g' 'enumeration names' 'h' 'included header files' 'm' 'struct, and union members' 's' 'structure names' 't' 'typedefs' 'u' 'union names' 'v' 'variable definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=d %{
        set-option window tagbar_kinds 'a' 'aliases' 'c' 'classes' 'g' 'enumeration names' 'e' 'enumerators' 'f' 'function definitions' 'i' 'interfaces' 'm' 'class, struct, and union members' 'X' 'mixins' 'M' 'modules' 'n' 'namespaces' 's' 'structure names' 'T' 'templates' 'u' 'union names' 'v' 'variable definitions' 'V' 'version statements'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=diff %{
        set-option window tagbar_kinds 'm' 'modified files' 'n' 'newly created files' 'd' 'deleted files' 'h' 'hunks'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=dtd %{
        set-option window tagbar_kinds 'E' 'entities' 'p' 'parameter entities' 'e' 'elements' 'a' 'attributes' 'n' 'notations'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=dts %{
        set-option window tagbar_kinds 'p' 'phandlers' 'l' 'labels' 'r' 'regex'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=dosbatch %{
        set-option window tagbar_kinds 'l' 'labels' 'v' 'variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=eiffel %{
        set-option window tagbar_kinds 'c' 'classes' 'f' 'features'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=elm %{
        set-option window tagbar_kinds 'm' 'module' 'n' 'renamed <a-i>mported <a-m>odule' 'P' 'port' 't' 'type <a-d>efinition' 'C' 'type <a-c>onstructor' 'A' 'type <a-a>lias' 'F' 'functions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=erlang %{
        set-option window tagbar_kinds 'd' 'macro definitions' 'f' 'functions' 'm' 'modules' 'r' 'record definitions' 't' 'type definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=falcon %{
        set-option window tagbar_kinds 'c' 'classes' 'f' 'functions' 'm' 'class members' 'v' 'variables' 'i' 'imports'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=flex %{
        set-option window tagbar_kinds 'f' 'functions' 'c' 'classes' 'm' 'methods' 'p' 'properties' 'v' 'global variables' 'x' 'mxtags'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=fortran %{
        set-option window tagbar_kinds 'b' 'block data' 'c' 'common blocks' 'e' 'entry points' 'E' 'enumerations' 'f' 'functions' 'i' 'interface contents, generic names, and operators' 'k' 'type and structure components' 'l' 'labels' 'm' 'modules' 'M' 'type bound procedures' 'n' 'namelists' 'N' 'enumeration values' 'p' 'programs' 's' 'subroutines' 't' 'derived types and structures' 'v' 'program and module variables' 'S' 'submodules'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=fypp %{
        set-option window tagbar_kinds 'm' 'macros'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=gdbinit %{
        set-option window tagbar_kinds 'd' 'definitions' 't' 'toplevel variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=go %{
        set-option window tagbar_kinds 'p' 'packages' 'f' 'functions' 'c' 'constants' 't' 'types' 'v' 'variables' 's' 'structs' 'i' 'interfaces' 'm' 'struct members' 'M' 'struct anonymous members' 'u' 'unknown' 'P' 'name for specifying imported package'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=html %{
        set-option window tagbar_kinds 'a' 'named anchors' 'h' 'h1 headings' 'i' 'h2 headings' 'j' 'h3 headings'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=iniconf %{
        set-option window tagbar_kinds 's' 'sections' 'k' 'keys'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=itcl %{
        set-option window tagbar_kinds 'c' 'classes' 'm' 'methods' 'v' 'object-specific variables' 'C' 'common variables' 'p' 'procedures within the  class  namespace'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=java %{
        set-option window tagbar_kinds 'a' 'annotation declarations' 'c' 'classes' 'e' 'enum constants' 'f' 'fields' 'g' 'enum types' 'i' 'interfaces' 'm' 'methods' 'p' 'packages'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=javaproperties %{
        set-option window tagbar_kinds 'k' 'keys'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=javascript %{
        set-option window tagbar_kinds 'f' 'functions' 'c' 'classes' 'm' 'methods' 'p' 'properties' 'C' 'constants' 'v' 'global variables' 'g' 'generators'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=json %{
        set-option window tagbar_kinds 'o' 'objects' 'a' 'arrays' 'n' 'numbers' 's' 'strings' 'b' 'booleans' 'z' 'nulls'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ldscript %{
        set-option window tagbar_kinds 'S' 'sections' 's' 'symbols' 'v' 'versions' 'i' 'input sections'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=lisp %{
        set-option window tagbar_kinds 'f' 'functions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=lua %{
        set-option window tagbar_kinds 'f' 'functions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=m4 %{
        set-option window tagbar_kinds 'd' 'macros' 'I' 'macro files'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=man %{
        set-option window tagbar_kinds 't' 'titles' 's' 'sections'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=make %{
        set-option window tagbar_kinds 'm' 'macros' 't' 'targets' 'I' 'makefiles'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=markdown %{
        set-option window tagbar_kinds 'c' 'chapsters' 's' 'sections' 'S' 'subsections' 't' 'subsubsections' 'T' 'level 4 subsections' 'u' 'level 5 subsections' 'r' 'regex'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=matlab %{
        set-option window tagbar_kinds 'f' 'function' 'v' 'variable' 'c' 'class'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=myrddin %{
        set-option window tagbar_kinds 'f' 'functions' 'c' 'constants' 'v' 'variables' 't' 'types' 'r' 'traits' 'p' 'packages'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=objectivec %{
        set-option window tagbar_kinds 'i' 'class interface' 'I' 'class implementation' 'P' '<a-p>rotocol' 'M' 'object's method' 'c' 'class' method' 'v' 'global variable' 'E' '<a-o>bject field' 'F' 'a function' 'p' 'a property' 't' 'a type alias' 's' 'a type structure' 'e' 'an enumeration' 'M' '<a-a> preprocessor macro'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ocaml %{
        set-option window tagbar_kinds 'c' 'classes' 'm' 'object's method' 'M' '<a-m>odule or functor' 'V' 'global variable' 'p' 'signature item' 't' 'type name' 'f' 'a function' 'C' '<a-a> constructor' 'R' 'a 'structure' field' 'e' 'an exception'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=passwd %{
        set-option window tagbar_kinds 'u' 'user names'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=pascal %{
        set-option window tagbar_kinds 'f' 'functions' 'p' 'procedures'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=perl %{
        set-option window tagbar_kinds 'c' 'constants' 'f' 'formats' 'l' 'labels' 'p' 'packages' 's' 'subroutines'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=perl6 %{
        set-option window tagbar_kinds 'c' 'classes' 'g' 'grammars' 'm' 'methods' 'o' 'modules' 'p' 'packages' 'r' 'roles' 'u' 'rules' 'b' 'submethods' 's' 'subroutines' 't' 'tokens'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=php %{
        set-option window tagbar_kinds 'c' 'classes' 'd' 'constant definitions' 'f' 'functions' 'i' 'interfaces' 'n' 'namespaces' 't' 'traits' 'v' 'variables' 'a' 'aliases'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=pod %{
        set-option window tagbar_kinds 'c' 'chapters' 's' 'sections' 'S' 'subsections' 't' 'subsubsections'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=protobuf %{
        set-option window tagbar_kinds 'p' 'packages' 'm' 'messages' 'f' 'fields' 'e' 'enum constants' 'g' 'enum types' 's' 'services'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=puppetmanifest %{
        set-option window tagbar_kinds 'c' 'classes' 'd' 'definitions' 'n' 'nodes' 'r' 'resources' 'v' 'variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=python %{
        set-option window tagbar_kinds 'c' 'classes' 'f' 'functions' 'm' 'class members' 'v' 'variables' 'I' 'name referring a module defined in other file' 'i' 'modules' 'x' 'name referring a class/variable/function/module defined in other module'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=pythonloggingconfig %{
        set-option window tagbar_kinds 'L' 'logger sections' 'q' 'logger qualnames'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=qtmoc %{
        set-option window tagbar_kinds 's' 'slots' 'S' 'signals' 'p' 'properties'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=r %{
        set-option window tagbar_kinds 'f' 'functions' 'l' 'libraries' 's' 'sources' 'g' 'global variables' 'v' 'function variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=rspec %{
        set-option window tagbar_kinds 'd' 'describes' 'c' 'contexts'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=rexx %{
        set-option window tagbar_kinds 's' 'subroutines'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=robot %{
        set-option window tagbar_kinds 't' 'testcases' 'k' 'keywords' 'v' 'variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=rpmspec %{
        set-option window tagbar_kinds 't' 'tags' 'm' 'macros' 'p' 'packages' 'g' 'global macros'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=restructuredtext %{
        set-option window tagbar_kinds 'c' 'chapters' 's' 'sections' 'S' 'subsections' 't' 'subsubsections' 'T' 'targets'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ruby %{
        set-option window tagbar_kinds 'c' 'classes' 'f' 'methods' 'm' 'modules' 'S' 'singleton methods'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=rust %{
        set-option window tagbar_kinds 'n' 'module' 's' 'structural type' 'i' 'trait interface' 'c' 'implementation' 'f' 'function' 'g' 'enum' 't' 'type <a-a>lias' 'V' 'global variable' 'M' '<a-m>acro <a-d>efinition' 'M' 'a struct field' 'e' 'an enum variant' 'P' '<a-a> method'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=scheme %{
        set-option window tagbar_kinds 'F' 'functions' 's' 'sets'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=sh %{
        set-option window tagbar_kinds 'a' 'aliases' 'f' 'functions' 's' 'script files' 'h' 'label for here document'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=slang %{
        set-option window tagbar_kinds 'f' 'functions' 'n' 'namespaces'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=sml %{
        set-option window tagbar_kinds 'e' 'exception declarations' 'f' 'function definitions' 'c' 'functor definitions' 's' 'signature declarations' 'r' 'structure declarations' 't' 'type definitions' 'v' 'value bindings'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=sql %{
        set-option window tagbar_kinds 'c' 'cursors' 'f' 'functions' 'E' 'record fields' 'L' 'block label' 'P' 'packages' 'p' 'procedures' 's' 'subtypes' 't' 'tables' 'T' 'triggers' 'v' 'variables' 'i' 'indexes' 'e' 'events' 'U' 'publications' 'R' 'services' 'D' 'domains' 'V' 'views' 'n' 'synonyms' 'x' 'mobi<a-l>ink <a-t>able <a-s>cripts' 'Y' 'mobi<a-l>ink <a-c>onn <a-s>cripts' 'Z' 'mobi<a-l>ink <a-p>roperties '
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=systemdunit %{
        set-option window tagbar_kinds 'U' 'units'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=tcl %{
        set-option window tagbar_kinds 'p' 'procedures' 'n' 'namespaces'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=tcloo %{
        set-option window tagbar_kinds 'c' 'classes' 'm' 'methods'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=tex %{
        set-option window tagbar_kinds 'p' 'parts' 'c' 'chapters' 's' 'sections' 'u' 'subsections' 'b' 'subsubsections' 'P' 'paragraphs' 'G' 'subparagraphs' 'l' 'labels' 'i' 'includes'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ttcn %{
        set-option window tagbar_kinds 'M' 'module definition' 't' 'type definition' 'c' 'constant definition' 'd' 'template definition' 'f' 'function definition' 's' 'signature definition' 'C' 'testcase definition' 'a' 'altstep definition' 'G' 'group definition' 'P' 'module parameter definition' 'v' 'variable instance' 'T' 'timer instance' 'p' 'port instance' 'm' 'record/set/union member' 'e' 'enumeration value'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=vera %{
        set-option window tagbar_kinds 'c' 'classes' 'd' 'macro definitions' 'e' 'enumerators' 'f' 'function definitions' 'g' 'enumeration names' 'i' 'interfaces' 'm' 'class, struct, and union members' 'p' 'programs' 's' 'signals' 't' 'tasks' 'T' 'typedefs' 'v' 'variable definitions' 'h' 'included header files'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=verilog %{
        set-option window tagbar_kinds 'c' 'constants' 'e' 'events' 'f' 'functions' 'm' 'modules' 'n' 'net data types' 'p' 'ports' 'r' 'register data types' 't' 'tasks' 'b' 'blocks'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=systemverilog %{
        set-option window tagbar_kinds 'c' 'constants' 'e' 'events' 'f' 'functions' 'm' 'modules' 'n' 'net data types' 'p' 'ports' 'r' 'register data types' 't' 'tasks' 'b' 'blocks' 'A' 'assertions' 'C' 'classes' 'V' 'covergroups' 'E' 'enumerators' 'I' 'interfaces' 'M' 'modports' 'K' 'packages' 'P' 'programs' 'R' 'properties' 'S' 'structs and unions' 'T' 'type declarations'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=vhdl %{
        set-option window tagbar_kinds 'c' 'constant declarations' 't' 'type definitions' 'T' 'subtype definitions' 'r' 'record names' 'e' 'entity declarations' 'f' 'function prototypes and declarations' 'p' 'procedure prototypes and declarations' 'P' 'package definitions'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=vim %{
        set-option window tagbar_kinds 'a' 'autocommand groups' 'c' 'user-defined commands' 'f' 'function definitions' 'm' 'maps' 'v' 'variable definitions' 'n' 'vimball filename'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=windres %{
        set-option window tagbar_kinds 'd' 'dialogs' 'm' 'menus' 'i' 'icons' 'b' 'bitmaps' 'c' 'cursors' 'f' 'fonts' 'v' 'versions' 'a' 'accelerators'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=yacc %{
        set-option window tagbar_kinds 'l' 'labels'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=yumrepo %{
        set-option window tagbar_kinds 'r' 'repository id'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=zephir %{
        set-option window tagbar_kinds 'c' 'classes' 'd' 'constant definitions' 'f' 'functions' 'i' 'interfaces' 'n' 'namespaces' 't' 'traits' 'v' 'variables' 'a' 'aliases'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=dbusintrospect %{
        set-option window tagbar_kinds 'i' 'interfaces' 'm' 'methods' 's' 'signals' 'p' 'properties'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=glade %{
        set-option window tagbar_kinds 'i' 'identifiers' 'c' 'classes' 'h' 'handlers'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=maven2 %{
        set-option window tagbar_kinds 'g' 'group identifiers' 'a' 'artifact identifiers' 'p' 'properties' 'r' 'repository identifiers'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=plistxml %{
        set-option window tagbar_kinds 'k' 'keys'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=relaxng %{
        set-option window tagbar_kinds 'e' 'elements' 'a' 'attributes' 'n' 'named patterns'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=svg %{
        set-option window tagbar_kinds 'i' 'id attributes'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=xslt %{
        set-option window tagbar_kinds 's' 'stylesheets' 'p' 'parameters' 'm' 'matched template' 'n' 'matched template' 'v' 'variables'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=yaml %{
        set-option window tagbar_kinds 'a' 'anchors'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
    hook global WinSetOption filetype=ansibleplaybook %{
        set-option window tagbar_kinds 'p' 'plays'
        hook -once global WinSetOption filetype=.* %{ unset-option window tagbar_kinds }
    }
}

