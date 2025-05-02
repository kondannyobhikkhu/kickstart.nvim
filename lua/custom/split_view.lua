local M = {}

-- File suffix mappings
local file_types = {
  p1 = '_sc_pali',
  e1 = '_sc_engl',
  p2 = '_vri_pali',
  e2 = '_bb_engl',
}

-- Function to get base filename and current file type
local function get_file_info()
  local current_file = vim.fn.expand '%:p'
  local base_name, file_type = nil, nil

  for type, suffix in pairs(file_types) do
    local pattern = suffix .. '$'
    if current_file:match(pattern) then
      base_name = current_file:gsub(pattern, '')
      file_type = type
      break
    end
  end

  return base_name, file_type
end

-- Function to check if a file exists
local function file_exists(path)
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

-- Function to sync cursor line across all windows
local function sync_cursor_line()
  local current_win = vim.api.nvim_get_current_win()
  local current_line = vim.api.nvim_win_get_cursor(current_win)[1]

  -- Get all windows in the current tab
  local windows = vim.api.nvim_tabpage_list_wins(0)

  for _, win in ipairs(windows) do
    if win ~= current_win then
      -- Get the buffer for the window
      local buf = vim.api.nvim_win_get_buf(win)
      -- Get the total number of lines in the buffer
      local max_lines = vim.api.nvim_buf_line_count(buf)
      -- Cap the target line at the buffer's maximum
      local target_line = math.min(current_line, max_lines)
      -- Set cursor with error handling
      local ok, err = pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
      if not ok then
        vim.notify('Failed to set cursor in window ' .. win .. ': ' .. err, vim.log.levels.WARN)
      end
    end
  end
end

-- Function to open a split with two files and sync scroll
local function open_split(left_type, right_type)
  local base_name, current_type = get_file_info()

  if not base_name or not current_type then
    vim.notify('Not a recognized file type (_sc_pali, _sc_engl, _vri_pali, _bb_engl)', vim.log.levels.ERROR)
    return
  end

  -- Construct file paths without extensions
  local left_suffix = file_types[left_type]
  local right_suffix = file_types[right_type]
  local left_file = base_name .. left_suffix
  local right_file = base_name .. right_suffix

  -- Check if files exist
  local left_exists = file_exists(left_file)
  local right_exists = file_exists(right_file)

  if not left_exists and not right_exists then
    vim.notify('Neither file exists: ' .. left_file .. ' nor ' .. right_file, vim.log.levels.ERROR)
    return
  end

  -- Close all other windows to start fresh
  vim.cmd 'only'

  -- Open left file
  if left_exists then
    vim.cmd('edit ' .. left_file)
  else
    vim.notify('Left file does not exist: ' .. left_file, vim.log.levels.WARN)
    return
  end

  -- Get current line to align both windows
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Open right file in a vertical split
  if right_exists then
    vim.cmd('vsplit ' .. right_file)
    -- Get the buffer for the right window
    local right_buf = vim.api.nvim_win_get_buf(0)
    -- Get the total number of lines in the right buffer
    local max_lines = vim.api.nvim_buf_line_count(right_buf)
    -- Set cursor to the current line or the last line if current_line exceeds max_lines
    local target_line = math.min(current_line, max_lines)
    vim.api.nvim_win_set_cursor(0, { target_line, 0 })
    -- Center both windows for better visibility
    vim.cmd 'windo normal! zz'
    -- Synchronize scroll positions
    vim.cmd 'windo set scrollbind'
  else
    vim.notify('Right file does not exist: ' .. right_file, vim.log.levels.WARN)
    return
  end

  -- Set up autocommand group for initial cursor synchronization
  vim.api.nvim_create_augroup('SyncCursorLine', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'WinEnter' }, {
    group = 'SyncCursorLine',
    callback = sync_cursor_line,
    desc = 'Sync cursor line across split windows',
  })

  -- Clear the autocommand after initial setup to rely on scrollbind
  vim.defer_fn(function()
    vim.api.nvim_del_augroup_by_name 'SyncCursorLine'
  end, 100)
end

-- Specific functions for each combination
M.view_e1_p1 = function()
  open_split('e1', 'p1') -- e1 (English) on left, p1 (Pali) on right
end

M.view_e1_e2 = function()
  open_split('e1', 'e2') -- e1 (English 1) on left, e2 (English 2) on right
end

M.view_p1_p2 = function()
  open_split('p1', 'p2') -- p1 (Pali 1) on left, p2 (Pali 2) on right
end

M.view_e2_p2 = function()
  open_split('e2', 'p2') -- e2 (English 2) on left, p2 (Pali 2) on right
end

M.view_p1_e2 = function()
  open_split('p1', 'e2') -- p1 (Pali) on left, e2 (English 2) on right
end

-- Setup key bindings
M.setup = function()
  local map = vim.keymap.set
  local opts = { noremap = true, silent = true }

  -- Leader key is space
  map('n', '<Space>vo', M.view_e1_p1, vim.tbl_extend('force', opts, { desc = 'View e1 (left) and p1 (right)' }))
  map('n', '<Space>ve', M.view_e1_e2, vim.tbl_extend('force', opts, { desc = 'View e1 (left) and e2 (right)' }))
  map('n', '<Space>vp', M.view_p1_p2, vim.tbl_extend('force', opts, { desc = 'View p1 (left) and p2 (right)' }))
  map('n', '<Space>vb', M.view_e2_p2, vim.tbl_extend('force', opts, { desc = 'View e2 (left) and p2 (right)' }))
  map('n', '<Space>vr', M.view_p1_e2, vim.tbl_extend('force', opts, { desc = 'View p1 (left) and e2 (right)' }))
end

return M
