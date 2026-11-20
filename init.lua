-- Цитаты из выделенного текста в поле ввода zot, без отправки.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

local DEFAULT_SETTINGS = {
  key = { key = 'q', mods = 'CTRL|SHIFT' },
  prefix = '> ',
  lead = '\n\n',          -- разделитель перед цитатой, начиная со второй вставки
  trail = '\n\n',         -- пустая строка под цитатой, где печатается комментарий
  require_zot = true,     -- вставлять только в панель, где работает zot
  clear_selection = true,
}

-- pane_id -> true после первой вставки
local pasted_once = {}

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

local function insert_quote(window, pane, settings)
  local ok, selection = pcall(function()
    return window:get_selection_text_for_pane(pane)
  end)
  if not ok or not selection or selection:match('^%s*$') then
    window:toast_notification('quote-to-zot', 'Nothing selected', nil, 1500)
    return
  end

  local target = pane
  if settings.require_zot then
    target = find_zot_pane(window, pane)
    if not target then
      window:toast_notification('quote-to-zot', 'No zot pane in this tab', nil, 1500)
      return
    end
  end

  local pane_id = tostring(target:pane_id())
  local lead = pasted_once[pane_id] and settings.lead or ''
  send_typed(target, lead .. to_quote(selection, settings.prefix) .. settings.trail)
  pasted_once[pane_id] = true

  if settings.clear_selection then
    window:perform_action(act.ClearSelection, pane)
  end
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

-- Добавляет горячую клавишу в конфигурацию WezTerm.
function M.apply(config, options)
  local settings = merge_settings(options)

  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = settings.key.key,
    mods = settings.key.mods,
    action = wezterm.action_callback(function(window, pane)
      insert_quote(window, pane, settings)
    end),
  })
end

-- Точка входа для wezterm.plugin.require.
M.apply_to_config = M.apply

M._internal = {
  split_lines = split_lines,
  to_quote = to_quote,
  send_typed = send_typed,
}

return M
