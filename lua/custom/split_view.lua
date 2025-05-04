-- ~/.config/nvim/lua/custom/split_view.lua
-- Module for opening split views of sutta files and synchronizing cursors across windows.
local M = {}

-- File suffix mappings for different sutta file types.
-- Maps short codes (e.g., 'p1') to file suffixes (e.g., '_sc_pali').
local file_types = {
  p1 = '_sc_pali',  -- Pali text from SuttaCentral
  e1 = '_sc_engl',  -- English translation from SuttaCentral
  p2 = '_vri_pali', -- Pali text from Vipassana Research Institute
  e2 = '_bb_engl',  -- English translation from Bhikkhu Bodhi
}

-- Function to get the base filename and current file type.
-- Extracts the base path (without suffix) and identifies the file type from the current file.
-- @return base_name (string or nil): Path without suffix (e.g., '/path/to/dn18/dn18').
-- @return file_type (string or nil): File type code (e.g., 'p1') or nil if not recognized.
local function get_file_info()
  -- Full path of the current file (e.g., '/path/to/dn18/dn18_sc_pali').
  local current_file = vim.fn.expand '%:p'
  -- Base path without suffix, to be determined.
  local base_name = nil
  -- File type code (e.g., 'p1'), to be determined.
  local file_type = nil

  -- Iterate through file_types to find a matching suffix.
  for type, suffix in pairs(file_types) do
    -- Pattern to match suffix at the end of the file path.
    local pattern = suffix .. '$'
    if current_file:match(pattern) then
      -- Remove suffix to get base path.
      base_name = current_file:gsub(pattern, '')
      file_type = type
      break
    end
  end

  return base_name, file_type
end

-- Function to check if a file exists.
-- @param path (string): File path to check.
-- @return (boolean): True if the file exists, false otherwise.
local function file_exists(path)
  -- Attempt to open the file in read mode.
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

-- Function to synchronize cursor line across all windows.
-- Updates the cursor position in passive windows to match the active window's cursor line,
-- ensuring the cursor stays within the buffer's line count and is highlighted.
local function sync_cursor_line()
  -- ID of the currently active window.
  local current_win = vim.api.nvim_get_current_win()
  -- Line number of the cursor in the active window.
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  -- List of all window IDs in the current tab.
  local windows = vim.api.nvim_tabpage_list_wins(0)

  -- Update cursor in each passive window.
  for _, win in ipairs(windows) do
    if win ~= current_win then
      -- Buffer ID for the window.
      local buf = vim.api.nvim_win_get_buf(win)
      -- Total number of lines in the buffer.
      local max_lines = vim.api.nvim_buf_line_count(buf)
      -- Limit target line to the buffer's maximum to prevent errors.
      local target_line = math.min(current_line, max_lines)
      -- Set cursor position safely.
      local ok, err = pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
      if not ok then
        vim.notify('Failed to set cursor in window ' .. win .. ': ' .. err, vim.log.levels.WARN)
      end
      -- Enable cursorline to highlight the cursor in the passive window.
      vim.api.nvim_win_set_option(win, 'cursorline', true)
    end
  end
end

-- Function to open a split view with two files and synchronize scroll and cursors.
-- Opens two files in a vertical split, enables scrollbind, and sets up cursor synchronization.
-- @param left_type (string): File type code for the left window (e.g., 'e1').
-- @param right_type (string): File type code for the right window (e.g., 'p1').
local function open_split(left_type, right_type)
  -- Get base path and file type of the current file.
  local base_name, current_type = get_file_info()

  -- Check if the current file is recognized.
  if not base_name or not current_type then
    vim.notify('Not a recognized file type (_sc_pali, _sc_engl, _vri_pali, _bb_engl)', vim.log.levels.ERROR)
    return
  end

  -- Suffixes for the left and right files.
  local left_suffix = file_types[left_type]
  local right_suffix = file_types[right_type]
  -- Full paths for the left and right files.
  local left_file = base_name .. left_suffix
  local right_file = base_name .. right_suffix

  -- Check if the files exist.
  local left_exists = file_exists(left_file)
  local right_exists = file_exists(right_file)

  -- Abort if neither file exists.
  if not left_exists and not right_exists then
    vim.notify('Neither file exists: ' .. left_file .. ' nor ' .. right_file, vim.log.levels.ERROR)
    return
  end

  -- Close all other windows to start fresh.
  vim.cmd 'only'

  -- Open the left file if it exists.
  if left_exists then
    vim.cmd('edit ' .. vim.fn.fnameescape(left_file))
  else
    vim.notify('Left file does not exist: ' .. left_file, vim.log.levels.WARN)
    return
  end

  -- Current cursor line in the left window.
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Open the right file in a vertical split if it exists.
  if right_exists then
    vim.cmd('vsplit ' .. vim.fn.fnameescape(right_file))
    -- Buffer ID for the right window.
    local right_buf = vim.api.nvim_win_get_buf(0)
    -- Total number of lines in the right buffer.
    local max_lines = vim.api.nvim_buf_line_count(right_buf)
    -- Limit cursor line to the buffer's maximum.
    local target_line = math.min(current_line, max_lines)
    -- Set cursor to align with the left window.
    vim.api.nvim_win_set_cursor(0, { target_line, 0 })
    -- Center both windows for visibility.
    vim.cmd 'windo normal! zz'
    -- Enable scrollbind for synchronized scrolling.
    vim.cmd 'windo set scrollbind'
    -- Enable cursorline in both windows for highlighting.
    vim.cmd 'windo set cursorline'
  else
    vim.notify('Right file does not exist: ' .. right_file, vim.log.levels.WARN)
    return
  end

  -- Create autocommand group for persistent cursor synchronization.
  vim.api.nvim_create_augroup('SplitViewCursorSync', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'WinEnter' }, {
    group = 'SplitViewCursorSync',
    callback = sync_cursor_line,
    desc = 'Synchronize cursor line across split windows',
  })
end

-- Function to open split view with SC English (left) and SC Pali (right).
M.view_e1_p1 = function()
  open_split('e1', 'p1')
end

-- Function to open split view with SC English (left) and BB English (right).
M.view_e1_e2 = function()
  open_split('e1', 'e2')
end

-- Function to open split view with SC Pali (left) and VRI Pali (right).
M.view_p1_p2 = function()
  open_split('p1', 'p2')
end

-- Function to open split view with BB English (left) and VRI Pali (right).
M.view_e2_p2 = function()
  open_split('e2', 'p2')
end

-- Function to open split view with SC Pali (left) and BB English (right).
M.view_p1_e2 = function()
  open_split('p1', 'e2')
end

-- Function to set up keybindings for split view commands.
-- Configures key mappings under <Space> for opening different split view combinations.
M.setup = function()
  -- Shortcut for setting keymaps.
  local map = vim.keymap.set
  -- Default options for keymappings: non-recursive and silent.
  local opts = { noremap = true, silent = true }

  -- Set keybindings with descriptions.
  map('n', '<Space>vo', M.view_e1_p1, vim.tbl_extend('force', opts, { desc = 'View SC English (left) and SC Pali (right)' }))
  map('n', '<Space>ve', M.view_e1_e2, vim.tbl_extend('force', opts, { desc = 'View SC English (left) and BB English (right)' }))
  map('n', '<Space>vp', M.view_p1_p2, vim.tbl_extend('force', opts, { desc = 'View SC Pali (left) and VRI Pali (right)' }))
  map('n', '<Space>vb', M.view_e2_p2, vim.tbl_extend('force', opts, { desc = 'View BB English (left) and VRI Pali (right)' }))
  map('n', '<Space>vr', M.view_p1_e2, vim.tbl_extend('force', opts, { desc = 'View SC Pali (left) and BB English (right)' }))
end

return M