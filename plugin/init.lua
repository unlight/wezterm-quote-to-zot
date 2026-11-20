-- wezterm-quote-to-zot: quote terminal selections into the zot prompt
-- without submitting them.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

M.defaults = {
  key = { key = 'q', mods = 'CTRL|SHIFT' },
  prefix = '> ',
  lead = '\n\n',          -- separator before a quote, from the second paste on
  trail = '\n\n',         -- blank line below a quote, where the comment goes
  require_zot = true,     -- only paste into a pane running zot
  clear_selection = true, -- drop the selection after pasting
}

local pasted_once = {} -- pane_id -> true after the first paste

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

-- \x1b\r is Alt+Enter: zot opens a new editor line instead of submitting.
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

local function insert_quote(window, pane, opts)
  local ok, selection = pcall(function()
    return window:get_selection_text_for_pane(pane)
  end)
  if not ok or not selection or selection:match('^%s*$') then
    window:toast_notification('quote-to-zot', 'Nothing selected', nil, 1500)
    return
  end

  local target = pane
  if opts.require_zot then
    target = find_zot_pane(window, pane)
    if not target then
      window:toast_notification('quote-to-zot', 'No zot pane in this tab', nil, 1500)
      return
    end
  end

  local pane_id = tostring(target:pane_id())
  local lead = pasted_once[pane_id] and opts.lead or ''
  send_typed(target, lead .. to_quote(selection, opts.prefix) .. opts.trail)
  pasted_once[pane_id] = true

  if opts.clear_selection then
    window:perform_action(act.ClearSelection, pane)
  end
end

function M.apply_to_config(config, user)
  local opts = {}
  for key, value in pairs(M.defaults) do
    opts[key] = value
  end
  for key, value in pairs(user or {}) do
    opts[key] = value
  end

  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = opts.key.key,
    mods = opts.key.mods,
    action = wezterm.action_callback(function(window, pane)
      insert_quote(window, pane, opts)
    end),
  })
end

return M
