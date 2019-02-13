# tagbar.kak

This  plugin displays  the  outline overview  of  your code,  somewhat
similar to Vim plugin [tagbar][1]. It uses [ctags][2] to generate tags
for current buffer, and [readtags][3] to display them.

## Installation

### With [plug.kak][4]
Add this snippet to your `kakrc`:

```kak
plug "andreyorst/tagbar.kak
```

### Without Plugin Manager
Clone this repo, and place `tagbar.kak` to your autoload directory, or
source it manually.

## Dependencies
For this plugin to work, you need working [ctags][2] and [readtags][3]
programs.    Note    that    [readtags][3]    isn't    shipped    with
[excuberant-ctags][2] by default (you can use [[universal-ctags][5]).

[1]: https://github.com/majutsushi/tagbar
[2]: http://ctags.sourceforge.net/
[3]: http://ctags.sourceforge.net/tool_support.html
[4]: https://github.com/andreyorst/plug.kak
[5]: https://github.com/universal-ctags
