
# tagbar.kak

![tagbar.kak](https://user-images.githubusercontent.com/19470159/52857326-e109f800-3137-11e9-8341-8993cfd42d6a.png)

This plugin displays the outline overview  of your code, somewhat similar to Vim
plugin [tagbar][1]. It uses [ctags][2] to  generate tags for current buffer, and
[readtags][3] to display them.

Tagbar.kak doesn't display  your project structure, but  current file structure,
providing ability to jump to the definition of the tags in current file.

## Installation

### With [plug.kak][4]
Add this snippet to your `kakrc`:

```kak
plug "andreyorst/tagbar.kak"
```

### Without Plugin Manager
Clone this repo, and place `tagbar.kak` to your autoload directory, or source it
manually.

## Dependencies
For this plugin to work, you need working [ctags][2] and [readtags][3] programs.
Note that [readtags][3] isn't shipped with [excuberant-ctags][2] by default (you
can use [universal-ctags][5]).


## Configuration
Tagbar.kak supports configuration via these options:
- `tagbar_sort` - affects tags sorting method in sections of the tagbar buffer;
- `tagbar_display_anon` - affects displaying of anonymous tags;
- `tagbar_side` - defines what side of the tmux pane should be used to open tagbar;
- `tagbar_size` - defines width or height in cells or percents;
- `tagbar_split` - defines how to split tmux pane, horizontally or vertically;
- `tagbarclient` - defines name of the client that tagbar will create and use to display itself.

## Usage
Tagbar.kak provides these commands:
- `tagbar-enable`  - spawn new client  with `*tagbar*` buffer in  it, and define
  watching hooks;
- `tagbar-toggle` - toggles `tagbar` client on and off;
- `tagbar-disable` - destroys `tagbar` client and support hooks. That's a proper
  way to exit `tagbar`.

When `$TMUX`  option is available  Tagbar.kak will  create split accordingly  to the
settings.  If Kakoune launched in X,  new window will be spawned, letting window
manager to handle it.

In `tagbar` window you  can use <kbd>Ret</kbd> key to jump  to the definition of
the tag. `tagbar` window will keep track of file opened in the last active client.

[1]: https://github.com/majutsushi/tagbar
[2]: http://ctags.sourceforge.net/
[3]: http://ctags.sourceforge.net/tool_support.html
[4]: https://github.com/andreyorst/plug.kak
[5]: https://github.com/universal-ctags
