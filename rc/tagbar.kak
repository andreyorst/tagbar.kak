declare-option str-list tagbar_kinds ''

try %{
    hook global WinSetOption filetype=c %{
        set-option global tagbar_kinds 'd' 'Macros' 'e' 'Enumerators' 'f' 'Functions' 'g' 'Enumerations' 'h' 'Headers' 'm' 'Structs, and Union members' 's' 'Structs' 't' 'Typedefs' 'u' 'Unions' 'v' 'Variables'
    }
    hook global WinSetOption filetype=cpp %{
        set-option global tagbar_kinds 'd' 'Macros' 'e' 'Enumerators' 'f' 'Functions' 'g' 'Enumerations' 'h' 'Headers' 'm' 'Class, Struct, and Union members' 's' 'Structs' 't' 'Typedefs' 'u' 'Unions' 'v' 'Variables' 'c' 'Classes' 'n' 'Namespaces'
    }
}

define-command tagbar %{ evaluate-commands %sh{
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/tagbar.XXXXXXXX")
    tagbar=$(mktemp "$tmp/buffer.XXXXXXXX")
    contents=$(mktemp "$tmp/contents.XXXXXXXX")
    tags=$(mktemp "$tmp/tags.XXXXXXXX")

    fifo="${tmp}/fifo"
    mkfifo ${fifo}

    ctags -f "$tags" "$kak_buffile"

    printf "%s\n" "try %{ delete-buffer *tagbar* }
                   edit! -fifo ${fifo} *tagbar*
                   hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r ${fifo%/*} } }
                   try %{ hook -always global KakEnd .* %{ nop %sh{ rm -r ${tmp} } } }
                   map buffer normal '<ret>' '<a-l><a-i><a-w>:<space>tagbar-jump $tags<ret>'"
                   # set-option window filetype tagbar

    eval "set -- $kak_opt_tagbar_kinds"
    while [ $# -gt 0 ]; do
        kind=$1
        description=$2
        readtags -t "$tags" -Q '(eq? $kind "'$kind'")' -l | cut -f1 > $contents
        if [ -s $contents ]; then
            printf "%s\n" "$description" >> $tagbar
            while read line; do
                printf "  %s\n" $line >> $tagbar
            done < $contents
            printf "\n" >> $tagbar
        fi
        shift 2
    done
    ( cat $tagbar > $fifo ) > /dev/null 2>&1 < /dev/null &
}}

define-command -docstring "tagbar-jump <tags-file>: jump to definition of selected tag" \
tagbar-jump -params 1 %{ evaluate-commands %sh{
    tags="$1"
    export tagname="${kak_selection}"
    readtags -t "$tags" "$tagname" | awk -F '\t|\n' '
        /[^\t]+\t[^\t]+\t\/\^.*\$?\// {
            opener = "{"; closer = "}"
            line = $0; sub(".*\t/\\^", "", line); sub("\\$?/$", "", line);
            menu_info = line; gsub("!", "!!", menu_info); gsub(/^[\t+ ]+/, "", menu_info); gsub(opener, "\\"opener, menu_info); gsub(/\t/, " ", menu_info);
            keys = line; gsub(/</, "<lt>", keys); gsub(/\t/, "<c-v><c-i>", keys); gsub("!", "!!", keys); gsub("&", "&&", keys); gsub("?", "??", keys); gsub("\\|", "||", keys);
            menu_item = $2; gsub("!", "!!", menu_item);
            edit_path = $2; gsub("&", "&&", edit_path); gsub("?", "??", edit_path); gsub("\\|", "||", edit_path);
            select = $1; gsub(/</, "<lt>", select); gsub(/\t/, "<c-v><c-i>", select); gsub("!", "!!", select); gsub("&", "&&", select); gsub("?", "??", select); gsub("\\|", "||", select);
            out = out "%!" menu_item ": {MenuInfo}" menu_info "! %!evaluate-commands %? try %& edit -existing %|" edit_path "|; execute-keys %|/\\Q" keys "<ret>vc| & catch %& echo -markup %|{Error}unable to find tag| &; try %& execute-keys %|s\\Q" select "<ret>| & ? !"
        }
        /[^\t]+\t[^\t]+\t[0-9]+/ {
            opener = "{"; closer = "}"
            menu_item = $2; gsub("!", "!!", menu_item);
            select = $1; gsub(/</, "<lt>", select); gsub(/\t/, "<c-v><c-i>", select); gsub("!", "!!", select); gsub("&", "&&", select); gsub("?", "??", select); gsub("\\|", "||", select);
            menu_info = $3; gsub("!", "!!", menu_info); gsub(opener, "\\"opener, menu_info);
            edit_path = $2; gsub("!", "!!", edit_path); gsub("?", "??", edit_path); gsub("&", "&&", edit_path); gsub("\\|", "||", keys);
            line_number = $3;
            out = out "%!" menu_item ": {MenuInfo}" menu_info "! %!evaluate-commands %? try %& edit -existing %|" edit_path "|; execute-keys %|" line_number "gx| & catch %& echo -markup %|{Error}unable to find tag| &; try %& execute-keys %|s\\Q" select "<ret>| & ? !"
        }
        END { print ( length(out) == 0 ? "echo -markup %{{Error}no such tag " ENVIRON["tagname"] "}" : "menu -markup -auto-single " out ) }'
}}

