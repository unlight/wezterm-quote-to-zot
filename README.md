# wezterm-quote-to-zot

Paste a terminal selection into the [zot](https://github.com/patriceckhart/zot)
prompt as a quote without submitting it. Select part of an agent reply, press one
chord, and the text lands in zot's editor with the cursor on the next line for
your comment.

```
> selected text from response
My comment here...

> selected text 2 from response
my comment 2 here
```

Several quotes at once: hold `Ctrl` and drag over multiple blocks. Each mouse
release queues a quote; after a pause the queue is pasted. The cursor stays under
the first quote:

```
> selected text 1
[cursor here]

> selected text 2

> selected text 3
```

## Install

Copy the repository or symlink it into the WezTerm config directory. Run this
from the repository directory:

```sh
ln -sfn "$PWD/init.lua" ~/.config/wezterm/wezterm-quote-to-zot.lua
```

Load the module in `~/.config/wezterm/wezterm.lua`:

```lua
local quote_to_zot = require 'wezterm-quote-to-zot'
quote_to_zot.apply(config)
```

Restart WezTerm or reload the config (`Ctrl+Shift+R`). Select text and press
`Ctrl+Shift+Q`.

## Options

`apply(config, options)` accepts an optional table:

```lua
quote_to_zot.apply(config, {
  key = { key = 'q', mods = 'CTRL|SHIFT' },
  prefix = '> ',
  lead = '\n\n',
  trail = '\n',
  require_zot = true,
  clear_selection = true,
  multi_selection = true,
  flush_delay = 2.0,
  cursor_after_first = true,
  notify = 'status',
  notify_timeout = 1.0,
})
```

| Option | Default | Purpose |
| ------ | ------- | ------- |
| `key` | `{ key = 'q', mods = 'CTRL|SHIFT' }` | Hotkey |
| `prefix` | `> ` | Prefix for every quoted line |
| `lead` | `\n\n` | Separator before a quote when the input already has text |
| `trail` | `\n` | Newline under the quote; the cursor lands right below it |
| `require_zot` | `true` | Only paste into a pane running zot |
| `clear_selection` | `true` | Clear the selection after pasting |
| `multi_selection` | `true` | `Ctrl` + drag queues several quotes |
| `flush_delay` | `2.0` | Pause after the last selection before pasting, in seconds |
| `cursor_after_first` | `true` | Put the cursor under the first quote in a block |
| `notify` | `status` | Notifications: `status`, `toast` or `none` |
| `notify_timeout` | `1.0` | How long a notification stays visible, in seconds |

The plugin checks the input by reading the pane. When the last `▌` prompt line
has no text below it, the quote is pasted without a leading separator, so no
blank line appears at the top. When the input already has text, `lead` is added.

If the selection is made in another pane of the same tab, the quote still goes
to the zot pane. When no zot pane is found, a notification appears and nothing
is pasted.

## Notifications

By default messages (`Queued 2`, `Quoted 2, cursor first`) appear on the right
side of the tab bar and disappear after one second. They are silent and do not
depend on desktop settings.

| `notify` | Behavior |
| -------- | -------- |
| `status` | Text on the right side of the tab bar for `notify_timeout` seconds |
| `toast` | System notification. The notification daemon controls sound and lifetime, and some desktops ignore the requested timeout |
| `none` | No notifications |

`status` is visible only when the tab bar is enabled. If it is hidden, use
`toast`.

## How it works

- `window:get_selection_text_for_pane(pane)` reads the native WezTerm selection.
- `pane:send_text()` types the quote into zot. Every newline is sent as
  `\x1b\r` (Alt+Enter), which inserts an editor line in zot without submitting
  the prompt.

Newlines are typed one by one on purpose: zot collapses a long bracketed paste
into `[pasted text #1 +N lines]`, so the quote would stop being visible.
Line-by-line typing keeps the whole quote on screen. Long quotes are slower, but
each line is a single `send_text` call.

## Multiple selection

The plugin adds three mouse bindings with the `Ctrl` modifier:

| Event | Action |
| ----- | ------ |
| `Ctrl` + left button down | start a new selection, the queue is kept |
| `Ctrl` + drag | extend the selection |
| `Ctrl` + left button up | turn the selection into a quote and queue it |

After the last release a `flush_delay` timer starts. Starting a new selection
cancels it. When the pause ends, all quotes are pasted into zot.

With several quotes the tail of the block is pasted first, then the cursor moves
to the top of the input and the first quote is pasted. The cursor stays under
the first quote and the rest follow below. Moving to the top is emulated with
500 `Up` presses, 100 `PageDown` presses and `Ctrl+A`: extra `Up` presses scroll
the chat up, so `PageDown` brings it back down without moving the editor cursor.

The `Ctrl+Shift+Q` hotkey pastes the queue immediately, without waiting for the
timer. With an empty queue it works as usual and pastes the current selection.

## Verification

From the repository directory:

```sh
wezterm --config-file test/run.lua show-keys --lua >/dev/null
```

The test covers quote markup, blank lines, CRLF, trailing newlines, newline
injection via Alt+Enter, empty-input detection, the order of several quotes, and
keyboard and mouse binding registration.

## Limitations

- Do not rebind `alt+enter` in zot's `keymap`; newline injection depends on it.
- If zot's `tui_click_to_position` is enabled, zot owns the mouse and WezTerm
  cannot see the selection. Hold `Shift` while dragging to get a native
  selection.
- With a zot dialog open (tool confirmation, login, extension panel), typed text
  goes to the dialog, not the prompt.
- Selected code loses its fences: every line gets a `> ` prefix and becomes a
  quote block.
- Very large selections paste noticeably slower.
- Wrapped lines may be quoted with the terminal's visual line breaks.
- Releasing `Ctrl` is not observable in WezTerm: pasting starts on a timer after
  the mouse button is released, not when `Ctrl` is released.
- `cursor_after_first` puts the cursor under the first quote only when the input
  is empty (checked by reading the pane). With text already in the input, the
  block is appended at the end and the cursor stays after the last quote.
- Moving to the top of the input is emulated with 500 `Up`, 100 `PageDown` and
  `Ctrl+A`. If the input has more than 500 lines, the chat has more than 100
  pages, or zot changes how these keys work, the trick breaks. A manually
  scrolled chat position is reset to the bottom.
- The `status` notification is invisible when the tab bar is hidden, and `toast`
  does not control sound: the notification daemon does.

## Compatibility

- WezTerm `20261120-054626-8066067d`
- zot `0.4.86`

## License

[MIT](https://opensource.org/licenses/MIT), Copyright (c) 2026
