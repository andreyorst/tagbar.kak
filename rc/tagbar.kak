# ╭─────────────╥────────────────────╮
# │ Author:     ║ File:              │
# │ Andrey Orst ║ tagbar.kak         │
# ╞═════════════╩════════════════════╡
# │ Class outline viewer for Kakoune │
# ╞══════════════════════════════════╡
# │ GitHub.com/andreyorst/tagbar.kak │
# ╰──────────────────────────────────╯

declare-option -hidden -docstring "name of the client in which all source code jumps will be executed" \
str tagbarjumpclient
declare-option -docstring "name of the client that tagbar will use to display itself" \
str tagbarclient 'tagbarclient'
declare-option -hidden -docstring "helps to keep track of focus events" \
str tagbar_last_client ''

declare-option -docstring "Sort tags in tagbar buffer.
  Possible values:
    true:     Sort tags.
    false:    Do not sort tags.
    foldcase: The foldcase value specifies case insensitive (or case-folded) sorting.
  Default value: true" \
str tagbar_sort 'true'

declare-option -docstring "display anonymous tags.
  Possible values: true, false
  Default value: true" \
str tagbar_display_anon 'true'

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

declare-option -hidden -docstring "state of tagbar" \
str tagbar_onscreen 'false'

add-highlighter shared/tagbar group
add-highlighter shared/tagbar/category regex ^[^\s][^\n]+$ 0:keyword
add-highlighter shared/tagbar/info     regex (?<=:\h)(.*?)$   1:comment

hook -group tagbar-syntax global WinSetOption filetype=tagbar %{
    add-highlighter window/tagbar ref tagbar
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter window/tagbar
    }
}

define-command tagbar-enable %{ evaluate-commands %sh{
    [ "$kak_opt_tagbar_active" = "true" ] && exit
    if [ -z "$kak_opt_tagbar_kinds" ]; then
        printf "%s\n" "echo -markup %{{Information}Filetype '$kak_opt_filetype' is not supported by Tagbar}"
        exit
    fi

    printf "%s\n" "set-option global tagbarjumpclient '${kak_client:-client0}'
                   set-option global tagbar_active true
                   tagbar-display
                   set-option global tagbar_onscreen true"
}}

define-command -hidden tagbar-display %{ nop %sh{
    [ "${kak_opt_tagbar_onscreen}" = "true" ] && exit

    tagbar_cmd="edit! -debug -scratch *tagbar*
                rename-client %opt{tagbarclient}
                evaluate-commands -client %opt{tagbarjumpclient} %{ tagbar-update }
                hook -group tagbar-watchers global FocusIn (?!$kak_opt_tagbarclient).* %{ try %{ tagbar-update 'focus' } }
                hook -group tagbar-watchers global WinDisplay (?!\*tagbar\*).* %{ try %{ tagbar-update } }
                hook -group tagbar-watchers global BufWritePost (?!\*tagbar\*).* %{ try %{ tagbar-update } }
                hook -group tagbar-watchers global WinSetOption tagbar_(sort|display_anon)=.* %{ try %{ tagbar-update } }"

    if [ -n "$TMUX" ]; then
        [ "$kak_opt_tagbar_split" = "vertical" ] && split="-v" || split="-h"
        [ "$kak_opt_tagbar_side" = "left" ] && side="-b" || side=
        [ -n "${kak_opt_tagbar_size%%*%}" ] && measure="-l" || measure="-p"
        tmux split-window $split $side $measure ${kak_opt_tagbar_size%%%*} kak -c $kak_session -e "$tagbar_cmd"
    elif [ -n "$kak_opt_termcmd" ]; then
        ( $kak_opt_termcmd "sh -c 'kak -c $kak_session -e \"$tagbar_cmd\"'" ) > /dev/null 2>&1 < /dev/null &
    fi
}}

define-command tagbar-disable %{
    set-option global tagbar_active 'false'
    set-option global tagbar_onscreen 'false'
    remove-hooks global tagbar-watchers
    try %{ delete-buffer *tagbar* } catch %{ echo -debug "Can't close tagbar buffer. Perhaps it was closed by something else" }
    try %{
        evaluate-commands -client %opt{tagbarclient} quit
    } catch %{
        echo -debug "Can't close tagbar client. Perhaps it was closed by something else"
    }
}

define-command tagbar-toggle %{ evaluate-commands %sh{
    if [ "${kak_opt_tagbar_active}" = "true" ]; then
        if [ "${kak_opt_tagbar_onscreen}" = "true" ]; then
            printf "%s\n" "evaluate-commands -client %opt{tagbarclient} quit
                           set-option global tagbar_onscreen false"
        else
            printf "%s\n" "evaluate-commands tagbar-display
                           set-option global tagbar_onscreen true"
        fi
    fi
}}

define-command -hidden tagbar-update -params ..1 %{ evaluate-commands %sh{
    [ "${kak_opt_tagbar_active}" != "true" ] && exit
    if [ "$1" = "focus" ] && [ "$kak_client" = "$kak_opt_tagbar_last_client" ]; then
        exit
    else
        printf "%s\n" "set-option global tagbar_last_client %{$kak_client}"
    fi

    printf "%s\n" "set-option global tagbarjumpclient '${kak_client:-client0}'"

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/tagbar.XXXXXXXX")
    tags="$tmp/tags"
    tagbar_buffer="$tmp/buffer"
    fifo="${tmp}/fifo"
    mkfifo ${fifo}

    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{ rm -rf $tmp }}"

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
                    out = out "  " tag ": \t" info "\n"
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
                       edit! -debug -fifo ${fifo} *tagbar*
                       set-option buffer filetype tagbar
                       map buffer normal '<ret>' '<a-h>;/: <c-v><c-i><ret><a-h>2<s-l><a-l><a-;>:<space>tagbar-jump $kak_bufname<ret>'
                       try %{
                           set-option window tabstop 1
                           remove-highlighter window/wrap
                           remove-highlighter window/numbers
                           remove-highlighter window/whitespace
                           remove-highlighter window/wrap
                       }
                       try %{ focus $kak_client }
                   }"

    ( cat $tagbar_buffer > $fifo; rm -rf $tmp ) > /dev/null 2>&1 < /dev/null &
}}

define-command -hidden tagbar-jump -params 1 %{
    evaluate-commands -client %opt{tagbarjumpclient} %sh{
        printf "%s: \t%s\n" "$kak_selection" "$1" | awk -F ': \t' '{
                keys = $2; gsub(/</, "<lt>", keys); gsub(/\t/, "<c-v><c-i>", keys);
                gsub("&", "&&", keys); gsub("#", "##", keys);
                select = $1; gsub(/</, "<lt>", select); gsub(/\t/, "<c-v><c-i>", select);
                gsub("&", "&&", select); gsub("#", "##", select);
                bufname = $3; gsub("&", "&&", bufname); gsub("#", "##", bufname);
                print "try %# buffer %&" bufname "&; execute-keys %&<esc>/\\Q" keys "<ret>vc& # catch %# echo -markup %&{Error}unable to find tag& #; try %# execute-keys %&s\\Q" select "<ret>& #"
            }'
    }
    try %{ focus %opt{tagbarjumpclient} }
}

# This section defines different kinds for ctags supported languages and their kinds
# Full list of supported languages can be obtained by evaluating `ctags --list-kinds' command
declare-option -hidden str-list tagbar_kinds
try %{
    hook global WinSetOption filetype=ada %{
        set-option window tagbar_kinds 'P' 'Package Specifications' 'p' 'Packages' 't' 'Types' 'u' 'Subtypes' 'c' 'Record Type Components' 'l' 'Enum Type Literals' 'v' 'Variables' 'f' 'Generic Formal Parameters' 'n' 'Constants' 'x' 'User Defined Exceptions' 'R' 'Subprogram Specifications' 'r' 'Subprograms' 'K' 'Task Specifications' 'k' 'Tasks' 'O' 'Protected Data Specifications' 'o' 'Protected Data' 'e' 'Task/Protected Data Entries' 'b' 'Labels' 'i' 'Loop/Declare Identifiers' 'S' 'Ctags Internal Use'
    }
    hook global WinSetOption filetype=ant %{
        set-option window tagbar_kinds 'p' 'Projects' 't' 'Targets' 'P' 'Properties' 'i' 'Antfiles'
    }
    hook global WinSetOption filetype=asciidoc %{
        set-option window tagbar_kinds 'c' 'Chapters' 's' 'Sections' 'S' 'Level 2 Sections' 't' 'Level 3 Sections' 'T' 'Level 4 Sections' 'u' 'Level 5 Sections' 'a' 'Anchors'
    }
    hook global WinSetOption filetype=(asm|gas) %{
        set-option window tagbar_kinds 'd' 'Defines' 'l' 'Labels' 'm' 'Macros' 't' 'Types' 's' 'Sections'
    }
    hook global WinSetOption filetype=asp %{
        set-option window tagbar_kinds 'd' 'Constants' 'c' 'Classes' 'f' 'Functions' 's' 'Subroutines' 'v' 'Variables'
    }
    hook global WinSetOption filetype=autoconf %{
        set-option window tagbar_kinds 'p' 'Packages' 't' 'Templates' 'm' 'Autoconf Macros' 'w' 'Options Specified With --With-...' 'e' 'Options Specified With --Enable-...' 's' 'Substitution Keys' 'c' 'Automake Conditions' 'd' 'Definitions'
    }
    hook global WinSetOption filetype=autoit %{
        set-option window tagbar_kinds 'f' 'Functions' 'r' 'Regions' 'g' 'Global Variables' 'l' 'Local Variables' 'S' 'Included Scripts'
    }
    hook global WinSetOption filetype=automake %{
        set-option window tagbar_kinds 'd' 'Directories' 'P' 'Programs' 'M' 'Manuals' 'T' 'Ltlibraries' 'L' 'Libraries' 'S' 'Scripts' 'D' 'Datum' 'c' 'Conditions'
    }
    hook global WinSetOption filetype=awk %{
        set-option window tagbar_kinds 'f' 'Functions'
    }
    hook global WinSetOption filetype=basic %{
        set-option window tagbar_kinds 'c' 'Constants' 'f' 'Functions' 'l' 'Labels' 't' 'Types' 'v' 'Variables' 'g' 'Enumerations'
    }
    hook global WinSetOption filetype=beta %{
        set-option window tagbar_kinds 'f' 'Fragment Definitions' 's' 'Slots' 'v' 'Patterns'
    }
    hook global WinSetOption filetype=clojure %{
        set-option window tagbar_kinds 'f' 'Functions' 'n' 'Namespaces'
    }
    hook global WinSetOption filetype=cmake %{
        set-option window tagbar_kinds 'f' 'Functions' 'm' 'Macros' 't' 'Targets' 'v' 'Variable Definitions' 'D' 'Options Specified With -D' 'p' 'Projects' 'r' 'Regex'
    }
    hook global WinSetOption filetype=c %{
        set-option window tagbar_kinds 'd' 'Macro Definitions' 'e' 'Enumerators' 'f' 'Function Definitions' 'g' 'Enumeration Names' 'h' 'Included Header Files' 'm' 'Struct, And Union Members' 's' 'Structure Names' 't' 'Typedefs' 'u' 'Union Names' 'v' 'Variable Definitions'
    }
    hook global WinSetOption filetype=cpp %{
        set-option window tagbar_kinds 'd' 'Macro Definitions' 'e' 'Enumerators' 'f' 'Function Definitions' 'g' 'Enumeration Names' 'h' 'Included Header Files' 'm' 'Class, Struct, And Union Members' 's' 'Structure Names' 't' 'Typedefs' 'u' 'Union Names' 'v' 'Variable Definitions' 'c' 'Classes' 'n' 'Namespaces'
    }
    hook global WinSetOption filetype=cpreprocessor %{
        set-option window tagbar_kinds 'd' 'Macro Definitions' 'h' 'Included Header Files'
    }
    hook global WinSetOption filetype=css %{
        set-option window tagbar_kinds 'c' 'Classes' 's' 'Selectors' 'i' 'Identities'
    }
    hook global WinSetOption filetype=csharp %{
        set-option window tagbar_kinds 'c' 'Classes' 'd' 'Macro Definitions' 'e' 'Enumerators' 'E' 'Events' 'f' 'Fields' 'g' 'Enumeration Names' 'i' 'Interfaces' 'm' 'Methods' 'n' 'Namespaces' 'p' 'Properties' 's' 'Structure Names' 't' 'Typedefs'
    }
    hook global WinSetOption filetype=ctags %{
        set-option window tagbar_kinds 'l' 'Language Definitions' 'k' 'Kind Definitions'
    }
    hook global WinSetOption filetype=cobol %{
        set-option window tagbar_kinds 'p' 'Paragraphs' 'd' 'Data Items' 'S' 'Source Code File' 'f' 'File Descriptions' 'g' 'Group Items' 'P' 'Program Ids' 's' 'Sections' 'D' 'Divisions'
    }
    hook global WinSetOption filetype=cuda %{
        set-option window tagbar_kinds 'd' 'Macro Definitions' 'e' 'Enumerators' 'f' 'Function Definitions' 'g' 'Enumeration Names' 'h' 'Included Header Files' 'm' 'Struct, And Union Members' 's' 'Structure Names' 't' 'Typedefs' 'u' 'Union Names' 'v' 'Variable Definitions'
    }
    hook global WinSetOption filetype=d %{
        set-option window tagbar_kinds 'a' 'Aliases' 'c' 'Classes' 'g' 'Enumeration Names' 'e' 'Enumerators' 'f' 'Function Definitions' 'i' 'Interfaces' 'm' 'Class, Struct, And Union Members' 'X' 'Mixins' 'M' 'Modules' 'n' 'Namespaces' 's' 'Structure Names' 'T' 'Templates' 'u' 'Union Names' 'v' 'Variable Definitions' 'V' 'Version Statements'
    }
    hook global WinSetOption filetype=diff %{
        set-option window tagbar_kinds 'm' 'Modified Files' 'n' 'Newly Created Files' 'd' 'Deleted Files' 'h' 'Hunks'
    }
    hook global WinSetOption filetype=dtd %{
        set-option window tagbar_kinds 'E' 'Entities' 'p' 'Parameter Entities' 'e' 'Elements' 'a' 'Attributes' 'n' 'Notations'
    }
    hook global WinSetOption filetype=dts %{
        set-option window tagbar_kinds 'p' 'Phandlers' 'l' 'Labels' 'r' 'Regex'
    }
    hook global WinSetOption filetype=dosbatch %{
        set-option window tagbar_kinds 'l' 'Labels' 'v' 'Variables'
    }
    hook global WinSetOption filetype=eiffel %{
        set-option window tagbar_kinds 'c' 'Classes' 'f' 'Features'
    }
    hook global WinSetOption filetype=elm %{
        set-option window tagbar_kinds 'm' 'Module' 'n' 'Renamed Imported Module' 'p' 'Port' 't' 'Type Definition' 'c' 'Type Constructor' 'a' 'Type Alias' 'f' 'Functions'
    }
    hook global WinSetOption filetype=erlang %{
        set-option window tagbar_kinds 'd' 'Macro Definitions' 'f' 'Functions' 'm' 'Modules' 'r' 'Record Definitions' 't' 'Type Definitions'
    }
    hook global WinSetOption filetype=falcon %{
        set-option window tagbar_kinds 'c' 'Classes' 'f' 'Functions' 'm' 'Class Members' 'v' 'Variables' 'i' 'Imports'
    }
    hook global WinSetOption filetype=flex %{
        set-option window tagbar_kinds 'f' 'Functions' 'c' 'Classes' 'm' 'Methods' 'p' 'Properties' 'v' 'Global Variables' 'x' 'Mxtags'
    }
    hook global WinSetOption filetype=fortran %{
        set-option window tagbar_kinds 'b' 'Block Data' 'c' 'Common Blocks' 'e' 'Entry Points' 'E' 'Enumerations' 'f' 'Functions' 'i' 'Interface Contents, Generic Names, And Operators' 'k' 'Type And Structure Components' 'l' 'Labels' 'm' 'Modules' 'M' 'Type Bound Procedures' 'n' 'Namelists' 'N' 'Enumeration Values' 'p' 'Programs' 's' 'Subroutines' 't' 'Derived Types And Structures' 'v' 'Program And Module Variables' 'S' 'Submodules'
    }
    hook global WinSetOption filetype=fypp %{
        set-option window tagbar_kinds 'm' 'Macros'
    }
    hook global WinSetOption filetype=gdbinit %{
        set-option window tagbar_kinds 'd' 'Definitions' 't' 'Toplevel Variables'
    }
    hook global WinSetOption filetype=go %{
        set-option window tagbar_kinds 'p' 'Packages' 'f' 'Functions' 'c' 'Constants' 't' 'Types' 'v' 'Variables' 's' 'Structs' 'i' 'Interfaces' 'm' 'Struct Members' 'M' 'Struct Anonymous Members' 'n' 'Interface Method Specification' 'u' 'Unknown' 'P' 'Name For Specifying Imported Package'
    }
    hook global WinSetOption filetype=html %{
        set-option window tagbar_kinds 'a' 'Named Anchors' 'h' 'H1 Headings' 'i' 'H2 Headings' 'j' 'H3 Headings'
    }
    hook global WinSetOption filetype=iniconf %{
        set-option window tagbar_kinds 's' 'Sections' 'k' 'Keys'
    }
    hook global WinSetOption filetype=itcl %{
        set-option window tagbar_kinds 'c' 'Classes' 'm' 'Methods' 'v' 'Object-Specific Variables' 'C' 'Common Variables' 'p' 'Procedures Within The  Class  Namespace'
    }
    hook global WinSetOption filetype=java %{
        set-option window tagbar_kinds 'a' 'Annotation Declarations' 'c' 'Classes' 'e' 'Enum Constants' 'f' 'Fields' 'g' 'Enum Types' 'i' 'Interfaces' 'm' 'Methods' 'p' 'Packages'
    }
    hook global WinSetOption filetype=javaproperties %{
        set-option window tagbar_kinds 'k' 'Keys'
    }
    hook global WinSetOption filetype=javascript %{
        set-option window tagbar_kinds 'f' 'Functions' 'c' 'Classes' 'm' 'Methods' 'p' 'Properties' 'C' 'Constants' 'v' 'Global Variables' 'g' 'Generators' 'G' 'Getters' 'S' 'Setters'
    }
    hook global WinSetOption filetype=json %{
        set-option window tagbar_kinds 'o' 'Objects' 'a' 'Arrays' 'n' 'Numbers' 's' 'Strings' 'b' 'Booleans' 'z' 'Nulls'
    }
    hook global WinSetOption filetype=ldscript %{
        set-option window tagbar_kinds 'S' 'Sections' 's' 'Symbols' 'v' 'Versions' 'i' 'Input Sections'
    }
    hook global WinSetOption filetype=lisp %{
        set-option window tagbar_kinds 'f' 'Functions'
    }
    hook global WinSetOption filetype=lua %{
        set-option window tagbar_kinds 'f' 'Functions'
    }
    hook global WinSetOption filetype=m4 %{
        set-option window tagbar_kinds 'd' 'Macros' 'I' 'Macro Files'
    }
    hook global WinSetOption filetype=man %{
        set-option window tagbar_kinds 't' 'Titles' 's' 'Sections'
    }
    hook global WinSetOption filetype=makefile %{
        set-option window tagbar_kinds 'm' 'Macros' 't' 'Targets' 'I' 'Makefiles'
    }
    hook global WinSetOption filetype=markdown %{
        set-option window tagbar_kinds 'c' 'Chapsters' 's' 'Sections' 'S' 'Subsections' 't' 'Subsubsections' 'T' 'Level 4 Subsections' 'u' 'Level 5 Subsections' 'r' 'Regex'
    }
    hook global WinSetOption filetype=matlab %{
        set-option window tagbar_kinds 'f' 'Function' 'v' 'Variable' 'c' 'Class'
    }
    hook global WinSetOption filetype=myrddin %{
        set-option window tagbar_kinds 'f' 'Functions' 'c' 'Constants' 'v' 'Variables' 't' 'Types' 'r' 'Traits' 'p' 'Packages'
    }
    hook global WinSetOption filetype=objectivec %{
        set-option window tagbar_kinds 'i' 'Class Interface' 'I' 'Class Implementation' 'P' 'Protocol' 'm' 'Object''s method' 'c' 'Class'' method' 'v' 'Global Variable' 'E' 'Object Field' 'f' 'A Function' 'p' 'A Property' 't' 'A Type Alias' 's' 'A Type Structure' 'e' 'An Enumeration' 'M' 'A Preprocessor Macro' 'C' 'Categories'
    }
    hook global WinSetOption filetype=ocaml %{
        set-option window tagbar_kinds 'c' 'Classes' 'm' 'Object''s method' 'M' 'Module Or Functor' 'v' 'Global Variable' 'p' 'Signature Item' 't' 'Type Name' 'f' 'A Function' 'C' 'A Constructor' 'r' 'A Structure Field' 'e' 'An Exception'
    }
    hook global WinSetOption filetype=passwd %{
        set-option window tagbar_kinds 'u' 'User Names'
    }
    hook global WinSetOption filetype=pascal %{
        set-option window tagbar_kinds 'f' 'Functions' 'p' 'Procedures'
    }
    hook global WinSetOption filetype=perl %{
        set-option window tagbar_kinds 'c' 'Constants' 'f' 'Formats' 'l' 'Labels' 'p' 'Packages' 's' 'Subroutines'
    }
    hook global WinSetOption filetype=perl6 %{
        set-option window tagbar_kinds 'c' 'Classes' 'g' 'Grammars' 'm' 'Methods' 'o' 'Modules' 'p' 'Packages' 'r' 'Roles' 'u' 'Rules' 'b' 'Submethods' 's' 'Subroutines' 't' 'Tokens'
    }
    hook global WinSetOption filetype=php %{
        set-option window tagbar_kinds 'c' 'Classes' 'd' 'Constant Definitions' 'f' 'Functions' 'i' 'Interfaces' 'n' 'Namespaces' 't' 'Traits' 'v' 'Variables' 'a' 'Aliases'
    }
    hook global WinSetOption filetype=pod %{
        set-option window tagbar_kinds 'c' 'Chapters' 's' 'Sections' 'S' 'Subsections' 't' 'Subsubsections'
    }
    hook global WinSetOption filetype=protobuf %{
        set-option window tagbar_kinds 'p' 'Packages' 'm' 'Messages' 'f' 'Fields' 'e' 'Enum Constants' 'g' 'Enum Types' 's' 'Services'
    }
    hook global WinSetOption filetype=puppetmanifest %{
        set-option window tagbar_kinds 'c' 'Classes' 'd' 'Definitions' 'n' 'Nodes' 'r' 'Resources' 'v' 'Variables'
    }
    hook global WinSetOption filetype=python %{
        set-option window tagbar_kinds 'c' 'Classes' 'f' 'Functions' 'm' 'Class Members' 'v' 'Variables' 'I' 'Name Referring A Module Defined In Other File' 'i' 'Modules' 'x' 'Name Referring A Class/Variable/Function/Module Defined In Other Module'
    }
    hook global WinSetOption filetype=pythonloggingconfig %{
        set-option window tagbar_kinds 'L' 'Logger Sections' 'q' 'Logger Qualnames'
    }
    hook global WinSetOption filetype=qemuhx %{
        set-option window tagbar_kinds 'q' 'QEMU Management Protocol Dispatch Table Entries' 'i' 'Item In Texinfo Doc'
    }
    hook global WinSetOption filetype=qtmoc %{
        set-option window tagbar_kinds 's' 'Slots' 'S' 'Signals' 'p' 'Properties'
    }
    hook global WinSetOption filetype=r %{
        set-option window tagbar_kinds 'f' 'Functions' 'l' 'Libraries' 's' 'Sources' 'g' 'Global Variables' 'v' 'Function Variables'
    }
    hook global WinSetOption filetype=rspec %{
        set-option window tagbar_kinds 'd' 'Describes' 'c' 'Contexts'
    }
    hook global WinSetOption filetype=rexx %{
        set-option window tagbar_kinds 's' 'Subroutines'
    }
    hook global WinSetOption filetype=robot %{
        set-option window tagbar_kinds 't' 'Testcases' 'k' 'Keywords' 'v' 'Variables'
    }
    hook global WinSetOption filetype=rpmspec %{
        set-option window tagbar_kinds 't' 'Tags' 'm' 'Macros' 'p' 'Packages' 'g' 'Global Macros'
    }
    hook global WinSetOption filetype=restructuredtext %{
        set-option window tagbar_kinds 'c' 'Chapters' 's' 'Sections' 'S' 'Subsections' 't' 'Subsubsections' 'T' 'Targets'
    }
    hook global WinSetOption filetype=ruby %{
        set-option window tagbar_kinds 'c' 'Classes' 'f' 'Methods' 'm' 'Modules' 'S' 'Singleton Methods'
    }
    hook global WinSetOption filetype=rust %{
        set-option window tagbar_kinds 'n' 'Module' 's' 'Structural Type' 'i' 'Trait Interface' 'c' 'Implementation' 'f' 'Function' 'g' 'Enum' 't' 'Type Alias' 'v' 'Global Variable' 'M' 'Macro Definitions' 'm' 'Struct Fields' 'e' 'An Enum Variant' 'P' 'Methods'
    }
    hook global WinSetOption filetype=scheme %{
        set-option window tagbar_kinds 'f' 'Functions' 's' 'Sets'
    }
    hook global WinSetOption filetype=sh %{
        set-option window tagbar_kinds 'a' 'Aliases' 'f' 'Functions' 's' 'Script Files' 'h' 'Label For Here Document'
    }
    hook global WinSetOption filetype=slang %{
        set-option window tagbar_kinds 'f' 'Functions' 'n' 'Namespaces'
    }
    hook global WinSetOption filetype=sml %{
        set-option window tagbar_kinds 'e' 'Exception Declarations' 'f' 'Function Definitions' 'c' 'Functor Definitions' 's' 'Signature Declarations' 'r' 'Structure Declarations' 't' 'Type Definitions' 'v' 'Value Bindings'
    }
    hook global WinSetOption filetype=sql %{
        set-option window tagbar_kinds 'c' 'Cursors' 'f' 'Functions' 'E' 'Record Fields' 'L' 'Block Label' 'P' 'Packages' 'p' 'Procedures' 's' 'Subtypes' 't' 'Tables' 'T' 'Triggers' 'v' 'Variables' 'i' 'Indexes' 'e' 'Events' 'U' 'Publications' 'R' 'Services' 'D' 'Domains' 'V' 'Views' 'n' 'Synonyms' 'x' 'MobiLink Table Scripts' 'y' 'MobiLink Conn Scripts' 'z' 'MobiLink Properties '
    }
    hook global WinSetOption filetype=systemdunit %{
        set-option window tagbar_kinds 'u' 'Units'
    }
    hook global WinSetOption filetype=systemtap %{
        set-option window tagbar_kinds 'p' 'Probe Aliases' 'f' 'Functions' 'v' 'Variables' 'm' 'Macros' 'r' 'Regex'
    }
    hook global WinSetOption filetype=tcl %{
        set-option window tagbar_kinds 'p' 'Procedures' 'n' 'Namespaces'
    }
    hook global WinSetOption filetype=tcloo %{
        set-option window tagbar_kinds 'c' 'Classes' 'm' 'Methods'
    }
    hook global WinSetOption filetype=tex %{
        set-option window tagbar_kinds 'p' 'Parts' 'c' 'Chapters' 's' 'Sections' 'u' 'Subsections' 'b' 'Subsubsections' 'P' 'Paragraphs' 'G' 'Subparagraphs' 'l' 'Labels' 'i' 'Includes'
    }
    hook global WinSetOption filetype=ttcn %{
        set-option window tagbar_kinds 'M' 'Module Definition' 't' 'Type Definition' 'c' 'Constant Definition' 'd' 'Template Definition' 'f' 'Function Definition' 's' 'Signature Definition' 'C' 'Testcase Definition' 'a' 'Altstep Definition' 'G' 'Group Definition' 'P' 'Module Parameter Definition' 'v' 'Variable Instance' 'T' 'Timer Instance' 'p' 'Port Instance' 'm' 'Record/Set/Union Member' 'e' 'Enumeration Value'
    }
    hook global WinSetOption filetype=vera %{
        set-option window tagbar_kinds 'c' 'Classes' 'd' 'Macro Definitions' 'e' 'Enumerators' 'f' 'Function Definitions' 'g' 'Enumeration Names' 'i' 'Interfaces' 'm' 'Class, Struct, And Union Members' 'p' 'Programs' 's' 'Signals' 't' 'Tasks' 'T' 'Typedefs' 'v' 'Variable Definitions' 'h' 'Included Header Files'
    }
    hook global WinSetOption filetype=verilog %{
        set-option window tagbar_kinds 'c' 'Constants' 'e' 'Events' 'f' 'Functions' 'm' 'Modules' 'n' 'Net Data Types' 'p' 'Ports' 'r' 'Register Data Types' 't' 'Tasks' 'b' 'Blocks'
    }
    hook global WinSetOption filetype=systemverilog %{
        set-option window tagbar_kinds 'c' 'Constants' 'e' 'Events' 'f' 'Functions' 'm' 'Modules' 'n' 'Net Data Types' 'p' 'Ports' 'r' 'Register Data Types' 't' 'Tasks' 'b' 'Blocks' 'A' 'Assertions' 'C' 'Classes' 'V' 'Covergroups' 'E' 'Enumerators' 'I' 'Interfaces' 'M' 'Modports' 'K' 'Packages' 'P' 'Programs' 'R' 'Properties' 'S' 'Structs And Unions' 'T' 'Type Declarations'
    }
    hook global WinSetOption filetype=vhdl %{
        set-option window tagbar_kinds 'c' 'Constant Declarations' 't' 'Type Definitions' 'T' 'Subtype Definitions' 'r' 'Record Names' 'e' 'Entity Declarations' 'f' 'Function Prototypes And Declarations' 'p' 'Procedure Prototypes And Declarations' 'P' 'Package Definitions'
    }
    hook global WinSetOption filetype=vim %{
        set-option window tagbar_kinds 'a' 'Autocommand Groups' 'c' 'User-Defined Commands' 'f' 'Function Definitions' 'm' 'Maps' 'v' 'Variable Definitions' 'n' 'Vimball Filename'
    }
    hook global WinSetOption filetype=windres %{
        set-option window tagbar_kinds 'd' 'Dialogs' 'm' 'Menus' 'i' 'Icons' 'b' 'Bitmaps' 'c' 'Cursors' 'f' 'Fonts' 'v' 'Versions' 'a' 'Accelerators'
    }
    hook global WinSetOption filetype=yacc %{
        set-option window tagbar_kinds 'l' 'Labels'
    }
    hook global WinSetOption filetype=yumrepo %{
        set-option window tagbar_kinds 'r' 'Repository Id'
    }
    hook global WinSetOption filetype=zephir %{
        set-option window tagbar_kinds 'c' 'Classes' 'd' 'Constant Definitions' 'f' 'Functions' 'i' 'Interfaces' 'n' 'Namespaces' 't' 'Traits' 'v' 'Variables' 'a' 'Aliases'
    }
    hook global WinSetOption filetype=dbusintrospect %{
        set-option window tagbar_kinds 'i' 'Interfaces' 'm' 'Methods' 's' 'Signals' 'p' 'Properties'
    }
    hook global WinSetOption filetype=glade %{
        set-option window tagbar_kinds 'i' 'Identifiers' 'c' 'Classes' 'h' 'Handlers'
    }
    hook global WinSetOption filetype=maven2 %{
        set-option window tagbar_kinds 'g' 'Group Identifiers' 'a' 'Artifact Identifiers' 'p' 'Properties' 'r' 'Repository Identifiers'
    }
    hook global WinSetOption filetype=plistxml %{
        set-option window tagbar_kinds 'k' 'Keys'
    }
    hook global WinSetOption filetype=relaxng %{
        set-option window tagbar_kinds 'e' 'Elements' 'a' 'Attributes' 'n' 'Named Patterns'
    }
    hook global WinSetOption filetype=svg %{
        set-option window tagbar_kinds 'i' 'Id Attributes'
    }
    hook global WinSetOption filetype=xslt %{
        set-option window tagbar_kinds 's' 'Stylesheets' 'p' 'Parameters' 'm' 'Matched Template' 'n' 'Matched Template' 'v' 'Variables'
    }
    hook global WinSetOption filetype=yaml %{
        set-option window tagbar_kinds 'a' 'Anchors'
    }
    hook global WinSetOption filetype=ansibleplaybook %{
        set-option window tagbar_kinds 'p' 'Plays'
    }
}
