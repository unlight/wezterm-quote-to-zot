local wezterm = require 'wezterm'

local module = dofile('./init.lua')
local internal = module._internal

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format('%s: expected %q, got %q', label, tostring(expected), tostring(actual)))
  end
end

local function fake_pane()
  local sent = {}
  return {
    sent = sent,
    send_text = function(_, chunk)
      sent[#sent + 1] = chunk
    end,
  }
end

local function typed_text(sent)
  return (table.concat(sent):gsub('\27\r', '\n'))
end

-- Разметка цитат.
assert_equal(internal.to_quote('one\ntwo', '> '), '> one\n> two', 'two lines')
assert_equal(internal.to_quote('one\n\ntwo', '> '), '> one\n>\n> two', 'blank line')
assert_equal(internal.to_quote('one\r\ntwo', '> '), '> one\n> two', 'crlf')
assert_equal(internal.to_quote('trailing\n\n\n', '> '), '> trailing', 'trailing newlines')
assert_equal(internal.to_quote('  indented  ', '> '), '>   indented  ', 'leading spaces')

-- Переводы строк отправляются как Alt+Enter, а не как Enter.
local pane = fake_pane()
internal.send_typed(pane, '> a\n\n')
assert_equal(table.concat(pane.sent), '> a\27\r\27\r', 'typed line breaks')
pane = fake_pane()
internal.send_typed(pane, '> a\n> b')
assert_equal(table.concat(pane.sent), '> a\27\r> b', 'typed two lines')

local function fake_screen(text)
  return {
    get_lines_as_text = function()
      return text
    end,
  }
end

assert_equal(internal.field_is_empty(fake_screen('▌\n')), true, 'empty input')
assert_equal(internal.field_is_empty(fake_screen('▌ > a\n')), false, 'input with text')
assert_equal(internal.field_is_empty(fake_screen('▌\n  > a\n')), false, 'text below prompt')
assert_equal(internal.field_is_empty(fake_screen('▌\n  \n  \n')), true, 'blank continuation')
assert_equal(internal.field_is_empty(fake_screen('no prompt\n')), false, 'no prompt')

local settings = {
  lead = '\n\n',
  trail = '\n',
  cursor_after_first = true,
}

-- Одна цитата в пустом поле.
pane = fake_pane()
internal.insert_quotes(pane, { '> a' }, settings, true)
assert_equal(typed_text(pane.sent), '> a\n', 'single quote')

-- Одна цитата после предыдущей вставки.
pane = fake_pane()
internal.insert_quotes(pane, { '> a' }, settings, false)
assert_equal(typed_text(pane.sent), '\n\n> a\n', 'single quote with lead')

-- Несколько цитат, поле не пустое: курсор в конце.
pane = fake_pane()
internal.insert_quotes(pane, { '> a', '> b', '> c' }, settings, false)
assert_equal(typed_text(pane.sent), '\n\n> a\n\n> b\n\n> c\n', 'multiple quotes at end')

-- Несколько цитат, поле пустое: хвост, переход в начало, первая цитата.
pane = fake_pane()
internal.insert_quotes(pane, { '> a', '> b', '> c' }, settings, true)
assert_equal(typed_text(pane.sent), '> a\n\n\n> b\n\n> c', 'multiple quotes')
assert_equal(pane.sent[#pane.sent], '\27\r', 'cursor line under first quote')
assert_equal(pane.sent[#pane.sent - 1], '> a', 'first quote inserted last')
assert_equal(pane.sent[#pane.sent - 2], '\1', 'cursor to line start')
assert_equal(
  #pane.sent,
  6 + internal.start_ups + internal.start_page_downs + 1 + 2,
  'typed chunk count'
)
for i = 7, 6 + internal.start_ups do
  assert_equal(pane.sent[i], '\27[A', 'cursor up')
end
for i = 7 + internal.start_ups, 6 + internal.start_ups + internal.start_page_downs do
  assert_equal(pane.sent[i], '\27[6~', 'chat page down')
end

-- Регистрация привязок.
local config = wezterm.config_builder()
local keys_before = #(config.keys or {})
local mouse_before = #(config.mouse_bindings or {})
module.apply(config, { key = { key = 'x', mods = 'CTRL|ALT' } })
assert_equal(#config.keys, keys_before + 1, 'binding added')
assert_equal(#config.mouse_bindings, mouse_before + 3, 'mouse bindings added')

local binding = config.keys[#config.keys]
assert_equal(binding.key, 'x', 'binding key')
assert_equal(binding.mods, 'CTRL|ALT', 'binding modifiers')

wezterm.log_info('wezterm-quote-to-zot: tests passed')
return config
