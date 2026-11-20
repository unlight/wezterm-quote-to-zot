# wezterm-quote-to-zot

Quote a selection from the terminal into the [zot](https://github.com/patriceckhart/zot)
prompt without submitting it. Select part of an agent reply, press one chord, and
the text lands in zot's editor as a `>` quote with a blank line below it for your
comment.

```
> selected text from response

My comment here...

> selected text 2 from response

my comment 2 here
```

## Install

Add the plugin to `~/.wezterm.lua` (or `~/.config/wezterm/wezterm.lua`):

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local quote = wezterm.plugin.require 'https://github.com/USER/wezterm-quote-to-zot'
quote.apply_to_config(config)

return config
```

From a local checkout, `wezterm.plugin.require 'file:///home/user/Dev/wezterm-quote-to-zot'`
also works; run `wezterm.plugin.update_all()` after editing the plugin.

During development, loading the file directly avoids the sync step:

```lua
dofile('/home/user/Dev/wezterm-quote-to-zot/plugin/init.lua').apply_to_config(config)
```

Reload the config with `Ctrl+Shift+R`, select some text, press `Ctrl+Shift+Q`.

## Options

```lua
quote.apply_to_config(config, {
  key = { key = 'q', mods = 'CTRL|SHIFT' },
  prefix = '> ',
  lead = '\n\n',          -- separator before a quote, from the second paste on
  trail = '\n\n',         -- blank line below a quote, where the comment goes
  require_zot = true,     -- only paste into a pane running zot
  clear_selection = true, -- drop the selection after pasting
})
```

If the selection lives in another pane of the same tab, the quote still goes to
the zot pane. When no zot pane is found, a toast appears and nothing is pasted.

## How it works

- `window:get_selection_text_for_pane(pane)` reads the native WezTerm selection.
- `pane:send_text()` types the quote into zot. Every newline is sent as
  `\x1b\r` (Alt+Enter), which inserts a line break in zot's editor instead of
  submitting the prompt.

Newlines are typed one by one on purpose: zot collapses multi-line bracketed
paste into `[pasted text #1 +N lines]` once the paste gets long, so the quote
would stop being visible. Line-by-line typing keeps the whole quote on screen.
Long quotes are slower, but each line is a single `send_text` call.

## Limitations

- Do not rebind `alt+enter` in zot's `keymap`; the newline injection depends on it.
- If zot's `tui_click_to_position` is enabled, zot owns the mouse and WezTerm
  cannot see the selection. Hold `Shift` while dragging to get a native selection.
- With a zot dialog open (tool confirmation, login, extension panel), typed text
  goes to the dialog, not the prompt.
- Selected code loses its fences: every line gets a `> ` prefix and becomes a
  quote block.
- Terminals with very large selections will paste noticeably slower.
- Wrapped lines may be quoted with the terminal's visual line breaks.

## Tested with

- WezTerm `20261120-054626-8066067d`
- zot `0.4.86`

## License

MIT
