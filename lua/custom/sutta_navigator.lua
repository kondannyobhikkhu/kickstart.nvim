-- Path to the JSON file
local json_file_path = '/home/kondannyo/PGP/Nikayas/sutta_metadata_ALL.json'

-- Cache for parsed JSON
local json_cache = nil

-- Read and parse JSON file
local function read_json_file()
  if json_cache then
    return json_cache
  end
  local file = io.open(json_file_path, 'r')
  if not file then
    error('Could not open JSON file: ' .. json_file_path)
  end
  local content = file:read('*all')
  file:close()
  json_cache = vim.fn.json_decode(content)
  return json_cache
end

-- Helper to format display string as English / Pali
local function format_display(english, pali)
  english = english or 'Unknown'
  pali = pali or 'Unknown'
  return string.format('%s / %s', english, pali)
end

-- Main module
local M = {}

-- Define all picker functions in a local table to ensure scope
local pickers = {}

-- Fuzzy search across suttas
local function fuzzy_search(nikaya_filter)
  local json_data = read_json_file()
  local entries = {}

  -- Flatten suttas
  for _, nikaya_data in ipairs(json_data) do
    local nikaya = nikaya_data.nikaya
    if not nikaya_filter or nikaya == nikaya_filter then
      for _, division in ipairs(nikaya_data.divisions or {}) do
        for _, subdivision in ipairs(division.subdivisions or {}) do
          for _, sutta in ipairs(subdivision.suttas or {}) do
            if sutta.sutta_title_english ~= 'error' and sutta.sutta_path then
              local display = string.format(
                '%s: %s / %s (%s)',
                sutta.sutta_number or 'Unknown',
                sutta.sutta_title_english or 'Unknown',
                sutta.sutta_title_pali or 'Unknown',
                nikaya
              )
              table.insert(entries, {
                path = sutta.sutta_path,
                display = display,
                search_text = string.lower(
                  (sutta.sutta_number or '') .. ' ' ..
                  (sutta.sutta_title_english or '') .. ' ' ..
                  (sutta.sutta_title_pali or '') .. ' ' ..
                  nikaya
                ),
              })
            end
          end
        end
      end
    end
  end

  -- Prompt for search query
  vim.ui.input({ prompt = 'Search Suttas (e.g., King): ' }, function(query)
    if not query or query == '' then
      return
    end
    query = string.lower(query)

    -- Filter entries
    local filtered = {}
    for _, entry in ipairs(entries) do
      if entry.search_text:find(query, 1, true) then
        table.insert(filtered, entry)
      end
    end

    -- Show results
    vim.ui.select(filtered, {
      prompt = 'Select Sutta (<C-n>:Next, <C-p>:Prev, <CR>:Select)',
      format_item = function(entry)
        return entry.display
      end,
    }, function(choice)
      if choice then
        vim.api.nvim_command('edit ' .. vim.fn.fnameescape(choice.path))
      end
    end)
  end)
end

-- Nikaya picker
function pickers.nikaya_picker()
  local json_data = read_json_file()
  local nikayas = { 'AN', 'DN', 'MN', 'SN' }
  local entries = {
    { is_search = true, display = 'Search All Suttas', action = function()
      fuzzy_search(nil)
    end },
  }

  for _, nikaya in ipairs(nikayas) do
    for _, item in ipairs(json_data) do
      if item.nikaya == nikaya then
        table.insert(entries, { nikaya = nikaya, data = item })
        break
      end
    end
  end

  vim.ui.select(entries, {
    prompt = 'Select Nikaya or Search (<C-n>:Next, <C-p>:Prev, <CR>:Select)',
    format_item = function(entry)
      return entry.display or entry.nikaya
    end,
  }, function(choice)
    if choice then
      if choice.is_search then
        choice.action()
      else
        pickers.division_picker(choice.data)
      end
    end
  end)
end

-- Division picker
function pickers.division_picker(nikaya_data)
  local entries = {
    { is_back = true, display = '.. [Back to Nikaya]', action = pickers.nikaya_picker },
    { is_search = true, display = 'Search ' .. nikaya_data.nikaya .. ' Suttas', action = function()
      fuzzy_search(nikaya_data.nikaya)
    end },
  }
  for _, division in ipairs(nikaya_data.divisions or {}) do
    local english = division.english_name or 'Unknown'
    local pali = division.pali_name or 'Unknown'
    table.insert(entries, {
      division = division,
      display = format_display(english, pali),
      nikaya = nikaya_data.nikaya,
    })
  end

  -- Map <C-b> for this picker
  local bufnr = vim.api.nvim_get_current_buf()
  vim.keymap.set('n', '<C-b>', function()
    vim.api.nvim_buf_call(bufnr, function()
      pickers.nikaya_picker()
    end)
  end, { buffer = bufnr, silent = true })

  vim.ui.select(entries, {
    prompt = 'Select Division (' .. nikaya_data.nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <C-b>:Back, <CR>:Select)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Clean up keymap
    pcall(vim.keymap.del, 'n', '<C-b>', { buffer = bufnr })
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        pickers.subdivision_picker({ division_data = choice.division, nikaya = choice.nikaya })
      end
    end
  end)
end

-- Subdivision picker
function pickers.subdivision_picker(opts)
  local division_data = opts.division_data
  local nikaya = opts.nikaya
  local entries = {
    { is_back = true, display = '.. [Back to Division]', action = function()
      pickers.division_picker({ nikaya = nikaya, divisions = division_data.parent_divisions or {} })
    end },
    { is_search = true, display = 'Search ' .. nikaya .. ' Suttas', action = function()
      fuzzy_search(nikaya)
    end },
  }

  for _, subdivision in ipairs(division_data.subdivisions or {}) do
    local english = subdivision.english_name or 'Unknown'
    local pali = subdivision.pali_name or 'Unknown'
    table.insert(entries, {
      subdivision = subdivision,
      display = format_display(english, pali),
      nikaya = nikaya,
    })
  end

  -- Map <C-b> for this picker
  local bufnr = vim.api.nvim_get_current_buf()
  vim.keymap.set('n', '<C-b>', function()
    vim.api.nvim_buf_call(bufnr, function()
      pickers.division_picker({ nikaya = nikaya, divisions = division_data.parent_divisions or {} })
    end)
  end, { buffer = bufnr, silent = true })

  vim.ui.select(entries, {
    prompt = 'Select Subdivision (' .. nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <C-b>:Back, <CR>:Select)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Clean up keymap
    pcall(vim.keymap.del, 'n', '<C-b>', { buffer = bufnr })
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        pickers.sutta_picker({ subdivision_data = choice.subdivision, nikaya = choice.nikaya })
      end
    end
  end)
end

-- Sutta picker
function pickers.sutta_picker(opts)
  local subdivision_data = opts.subdivision_data
  local nikaya = opts.nikaya
  local entries = {
    { is_back = true, display = '.. [Back to Subdivision]', action = function()
      pickers.subdivision_picker({ division_data = subdivision_data.parent_division or {}, nikaya = nikaya })
    end },
    { is_search = true, display = 'Search ' .. nikaya .. ' Suttas', action = function()
      fuzzy_search(nikaya)
    end },
  }

  for _, sutta in ipairs(subdivision_data.suttas or {}) do
    if sutta.sutta_title_english ~= 'error' and sutta.sutta_path then
      local display = string.format(
        '%s: %s / %s (%s)',
        sutta.sutta_number,
        sutta.sutta_title_english or 'Unknown',
        sutta.sutta_title_pali or 'Unknown',
        nikaya
      )
      table.insert(entries, {
        path = sutta.sutta_path,
        display = display,
      })
    end
  end

  -- Map <C-b> for this picker
  local bufnr = vim.api.nvim_get_current_buf()
  vim.keymap.set('n', '<C-b>', function()
    vim.api.nvim_buf_call(bufnr, function()
      pickers.subdivision_picker({ division_data = subdivision_data.parent_division or {}, nikaya = nikaya })
    end)
  end, { buffer = bufnr, silent = true })

  vim.ui.select(entries, {
    prompt = 'Select Sutta (' .. nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <C-b>:Back, <CR>:Select)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Clean up keymap
    pcall(vim.keymap.del, 'n', '<C-b>', { buffer = bufnr })
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        vim.api.nvim_command('edit ' .. vim.fn.fnameescape(choice.path))
      end
    end
  end)
end

-- Main entry point
function M.sutta_navigator()
  pickers.nikaya_picker()
end

-- Setup function
function M.setup()
  -- Keymap handled in init.lua
end

return M