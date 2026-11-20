-- Цитаты из выделенного текста в поле ввода zot, без отправки.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

local DEFAULT_SETTINGS = {
  key = { key = 'q', mods = 'CTRL|SHIFT' },
  prefix = '> ',
  lead = '\n\n',            -- разделитель перед цитатой, когда поле не пустое
  trail = '\n\n',           -- пустая строка под цитатой
  require_zot = true,       -- вставлять только в панель, где работает zot
  clear_selection = true,
  multi_selection = true,   -- Ctrl+протяжка собирает несколько цитат
  flush_delay = 2.0,        -- пауза после последнего Ctrl+отпускания мыши
  cursor_after_first = true,
  notify = 'status',        -- 'status' | 'toast' | 'none'
  notify_timeout = 1.0,     -- секунды
}

local START_UPS = 500 -- столько Up перед Ctrl+A, чтобы попасть в начало поля

local pasted_once = {} -- pane_id -> true после первой вставки
local pending = {}     -- pane_id -> { quotes = {}, generation = 0 }
local notify_generation = {}

-- Секундное беззвучное сообщение в правой части таб-бара.
local function notify(window, text, settings)
  if settings.notify == 'none' then
    return
  end

  if settings.notify == 'toast' then
    window:toast_notification('quote-to-zot', text, nil, math.floor(settings.notify_timeout * 1000))
    return
  end

  local window_id = tostring(window:window_id())
  notify_generation[window_id] = (notify_generation[window_id] or 0) + 1
  local generation = notify_generation[window_id]
  window:set_right_status(text)
  wezterm.time.call_after(settings.notify_timeout, function()
    if notify_generation[window_id] ~= generation then
      return
    end
    pcall(function()
      window:set_right_status('')
    end)
  end)
end

local function split_lines(text)
  local normalized = text:gsub('\r\n', '\n'):gsub('\n+$', '')
  local lines = {}
  for line in (normalized .. '\n'):gmatch('([^\n]*)\n') do
    lines[#lines + 1] = line
  end
  return lines
end

local function to_quote(text, prefix)
  local out = {}
  for _, line in ipairs(split_lines(text)) do
    if line == '' then
      out[#out + 1] = prefix:gsub('%s+$', '')
    else
      out[#out + 1] = prefix .. line
    end
  end
  return table.concat(out, '\n')
end

-- \x1b\r это Alt+Enter: zot добавляет строку в редакторе и не отправляет промпт.
local function send_typed(pane, text)
  local first = true
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    if not first then
      pane:send_text('\x1b\r')
    end
    first = false
    if line ~= '' then
      pane:send_text(line)
    end
  end
end

-- Эмуляция перехода в начало поля: Up до упора и Ctrl+A в начало строки.
local function move_to_start(pane)
  for _ = 1, START_UPS do
    pane:send_text('\x1b[A')
  end
  pane:send_text('\x01')
end

local function process_name(pane)
  local ok, name = pcall(function()
    return pane:get_foreground_process_name()
  end)
  if not ok or not name then
    return nil
  end
  return (name:match('([^/\\]+)$') or name):lower()
end

local function is_zot(pane)
  return process_name(pane) == 'zot'
end

local function find_zot_pane(window, pane)
  if is_zot(pane) then
    return pane
  end
  local ok, tab = pcall(function()
    return window:active_tab()
  end)
  if not ok or not tab then
    return nil
  end
  for _, candidate in ipairs(tab:panes()) do
    if is_zot(candidate) then
      return candidate
    end
  end
  return nil
end

local function selection_of(window, pane)
  local ok, text = pcall(function()
    return window:get_selection_text_for_pane(pane)
  end)
  if not ok or not text or text:match('^%s*$') then
    return nil
  end
  return text
end

-- Несколько цитат: хвост вставляется первым, затем первая цитата пишется
-- в начало поля. Курсор остаётся под первой цитатой.
local function insert_quotes(target, quotes, settings, first_in_pane)
  local lead = first_in_pane and '' or settings.lead

  if #quotes == 1 then
    send_typed(target, lead .. quotes[1] .. settings.trail)
    return
  end

  if settings.cursor_after_first and first_in_pane then
    local tail = {}
    for i = 2, #quotes do
      tail[#tail + 1] = quotes[i]
    end
    send_typed(target, '\n\n' .. table.concat(tail, '\n\n'))
    move_to_start(target)
    send_typed(target, quotes[1] .. '\n')
    return
  end

  send_typed(target, lead .. table.concat(quotes, '\n\n') .. settings.trail)
end

local flush

flush = function(window, pane, settings)
  local pane_id = tostring(pane:pane_id())
  local state = pending[pane_id]
  if not state or #state.quotes == 0 then
    return
  end

  local target = pane
  if settings.require_zot then
    target = find_zot_pane(window, pane)
    if not target then
      notify(window, 'No zot pane in this tab', settings)
      return
    end
  end

  local quotes = state.quotes
  pending[pane_id] = nil

  local target_id = tostring(target:pane_id())
  local first_in_pane = not pasted_once[target_id]
  insert_quotes(target, quotes, settings, first_in_pane)
  pasted_once[target_id] = true

  if settings.clear_selection then
    window:perform_action(act.ClearSelection, pane)
  end

  local placed = (#quotes > 1 and settings.cursor_after_first and first_in_pane) and 'first' or 'end'
  notify(window, string.format('Quoted %d, cursor %s', #quotes, placed), settings)
end

local function add_quote(pane, selection, settings)
  local pane_id = tostring(pane:pane_id())
  local state = pending[pane_id]
  if not state then
    state = { quotes = {}, generation = 0 }
    pending[pane_id] = state
  end
  state.quotes[#state.quotes + 1] = to_quote(selection, settings.prefix)
  return state
end

local function cancel_timer(pane)
  local state = pending[tostring(pane:pane_id())]
  if state then
    state.generation = state.generation + 1
  end
end

local function schedule_flush(window, pane, settings)
  local pane_id = tostring(pane:pane_id())
  local state = pending[pane_id]
  if not state then
    return
  end

  state.generation = state.generation + 1
  local generation = state.generation
  wezterm.time.call_after(settings.flush_delay, function()
    local current = pending[pane_id]
    if not current or current.generation ~= generation then
      return
    end
    pcall(flush, window, pane, settings)
  end)
end

local function on_hotkey(window, pane, settings)
  local selection = selection_of(window, pane)
  local state = pending[tostring(pane:pane_id())]
  local queued = state and #state.quotes or 0

  if not selection and queued == 0 then
    notify(window, 'Nothing selected', settings)
    return
  end

  if selection then
    add_quote(pane, selection, settings)
  end
  flush(window, pane, settings)
end

local function on_ctrl_down(window, pane, settings)
  cancel_timer(pane)
  window:perform_action(act.SelectTextAtMouseCursor 'Cell', pane)
end

local function on_ctrl_drag(window, pane, settings)
  cancel_timer(pane)
  window:perform_action(act.ExtendSelectionToMouseCursor 'Cell', pane)
end

local function on_ctrl_up(window, pane, settings)
  local selection = selection_of(window, pane)
  if not selection then
    return
  end
  local state = add_quote(pane, selection, settings)
  notify(window, string.format('Queued %d', #state.quotes), settings)
  schedule_flush(window, pane, settings)
end

local function merge_settings(options)
  local settings = {}
  for key, value in pairs(DEFAULT_SETTINGS) do
    settings[key] = value
  end
  for key, value in pairs(options or {}) do
    settings[key] = value
  end
  return settings
end

local function add_mouse_bindings(config, settings)
  config.mouse_bindings = config.mouse_bindings or {}
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      on_ctrl_down(window, pane, settings)
    end),
  })
  table.insert(config.mouse_bindings, {
    event = { Drag = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      on_ctrl_drag(window, pane, settings)
    end),
  })
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      on_ctrl_up(window, pane, settings)
    end),
  })
end

-- Добавляет горячую клавишу и мышиные привязки в конфигурацию WezTerm.
function M.apply(config, options)
  local settings = merge_settings(options)

  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = settings.key.key,
    mods = settings.key.mods,
    action = wezterm.action_callback(function(window, pane)
      on_hotkey(window, pane, settings)
    end),
  })

  if settings.multi_selection then
    add_mouse_bindings(config, settings)
  end
end

-- Точка входа для wezterm.plugin.require.
M.apply_to_config = M.apply

M._internal = {
  split_lines = split_lines,
  to_quote = to_quote,
  send_typed = send_typed,
  move_to_start = move_to_start,
  insert_quotes = insert_quotes,
  start_ups = START_UPS,
}

return M
