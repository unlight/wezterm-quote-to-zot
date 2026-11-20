local wezterm = require 'wezterm'

local module = dofile('./init.lua')
local internal = module._internal

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format('%s: expected %q, got %q', label, tostring(expected), tostring(actual)))
  end
end

local function collect_typed(text)
  local sent = {}
  local pane = {
    send_text = function(_, chunk)
      sent[#sent + 1] = chunk
    end,
  }
  internal.send_typed(pane, text)
  return table.concat(sent)
end

assert_equal(internal.to_quote('one\ntwo', '> '), '> one\n> two', 'two lines')
assert_equal(internal.to_quote('one\n\ntwo', '> '), '> one\n>\n> two', 'blank line')
assert_equal(internal.to_quote('one\r\ntwo', '> '), '> one\n> two', 'crlf')
assert_equal(internal.to_quote('trailing\n\n\n', '> '), '> trailing', 'trailing newlines')
assert_equal(internal.to_quote('  indented  ', '> '), '>   indented  ', 'leading spaces')

-- Переводы строк отправляются как Alt+Enter, а не как Enter.
assert_equal(collect_typed('> a\n\n'), '> a\x1b\r\x1b\r', 'typed line breaks')
assert_equal(collect_typed('> a\n> b'), '> a\x1b\r> b', 'typed two lines')

local config = wezterm.config_builder()
local keys_before = #(config.keys or {})
module.apply(config, { key = { key = 'x', mods = 'CTRL|ALT' } })
assert_equal(#config.keys, keys_before + 1, 'binding added')

local binding = config.keys[#config.keys]
assert_equal(binding.key, 'x', 'binding key')
assert_equal(binding.mods, 'CTRL|ALT', 'binding modifiers')

wezterm.log_info('wezterm-quote-to-zot: tests passed')
return config
