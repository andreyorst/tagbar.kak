
# tagbar.kak

![tagbar.kak](https://user-images.githubusercontent.com/19470159/52857326-e109f800-3137-11e9-8341-8993cfd42d6a.png)

This plugin displays the outline overview  of your code, somewhat similar to Vim
plugin [tagbar][1]. It uses [ctags][2] to  generate tags for current buffer, and
[readtags][3] to display them.

**tagbar.kak** doesn't display  your project structure, but  current file structure,
providing ability to jump to the definition of the tags in current file.

## Installation

### With [plug.kak][4]
Add this snippet to your `kakrc`:

```kak
plug "andreyorst/tagbar.kak" config %{
    # if you have wrap highlighter enamled in you configuration
    # files it's better to turn it off for tagbar, using this hook:
    hook global WinSetOption filetype=tagbar %{
        remove-highlighter window/wrap
        # you can also disable rendering whitespaces here, and
    }
}
```

### Without Plugin Manager
Clone this repo, and place `tagbar.kak` script to your autoload directory, or
source it manually. Note: **tagbar.kak** uses huge amount of horizontal space
for its items, so it is better to turn off `wrap` highlighter for `tagbar`
filetype, as shown above.

## Dependencies
For this plugin to work, you need working [ctags][2] and [readtags][3] programs.
Note that [readtags][3] isn't shipped with [exuberant-ctags][2] by default (you
can use [universal-ctags][5]).


## Configuration
**tagbar.kak** supports configuration via these options:
- `tagbar_sort` - affects tags sorting method in sections of the tagbar buffer;
- `tagbar_display_anon` - affects displaying of anonymous tags;
- `tagbar_side` - defines what side of the tmux pane should be used to open tagbar;
- `tagbar_size` - defines width or height in cells or percents;
- `tagbar_split` - defines how to split tmux pane, horizontally or vertically;
- `tagbarclient` - defines name of the client that tagbar will create and use to
  display itself.
- `tagbar_ctags_cmd` - defines what command will be used to generate tag
  file. This option was added to allow setting custom ctags-compatible
  executable for languages that are not supported by ctags package, but have a
  compatible parser. If you want to set up **tagbar.kak** for unsupported
  language, you also need to populate `tagbar_kinds` option with pairs of kinds
  for the language. For example, for C, kinds are defined as follows `'f'
  'Function Definitions'`, `'g' 'Enumeration Names'`, `'h' 'Included Header
  files'`, and so on.

### Automatic startup
To start **tagbar.kak** automatically on certain filetypes, you can use this hook:

```kak
# To see what filetypes are supported use `ctags --list-kinds | awk '/^\w+/'
hook global WinSetOption filetype=(c|cpp|rust) %{
    tagbar-enable
}
```

Note that **tagbar.kak** currently allows only one client per session.

## Usage
**tagbar.kak** provides these commands:
- `tagbar-enable` - spawn new client with `*tagbar*` buffer in it, and define
  watching hooks;
- `tagbar-toggle` - toggles `tagbar` client on and off;
- `tagbar-disable` - destroys `tagbar` client and support hooks. That's a proper
  way to exit `tagbar`.

When `$TMUX` option is available **tagbar.kak** will create split accordingly to the
settings.  If Kakoune launched in X, new window will be spawned, letting window
manager to handle it.

In `tagbar` window you can use <kbd>Ret</kbd> key to jump to the definition of
the tag. `tagbarclient` will keep track of file opened in the last active
client.

[1]: https://github.com/majutsushi/tagbar
[2]: http://ctags.sourceforge.net/
[3]: http://ctags.sourceforge.net/tool_support.html
[4]: https://github.com/andreyorst/plug.kak
[5]: https://github.com/universal-ctags
