-- ~/.config/nvim/lua/custom/sutta_navigator.lua
-- Module for navigating sutta files using a hierarchical picker interface.
-- Allows selection of Nikayas, divisions, subdivisions, and suttas from a JSON metadata file.

-- Main module table to export functions.
local M = {}

-- Path to the JSON metadata file containing sutta information.
local json_file_path = '/home/kondannyo/PGP/Nikayas/sutta_metadata_ALL.json'

-- Cache for parsed JSON data to avoid re-reading the file multiple times.
local json_cache = nil

-- Function to read and parse the JSON metadata file.
-- Caches the result to improve performance on subsequent calls.
-- @return json_data (table): Parsed JSON data as a Lua table.
local function read_json_file()
  -- Check if cached JSON data exists.
  if json_cache then
    return json_cache
  end
  -- File handle for opening the JSON file in read mode.
  local file = io.open(json_file_path, 'r')
  -- Check if the file opened successfully.
  if not file then
    error('Could not open JSON file: ' .. json_file_path)
  end
  -- Entire content of the JSON file as a string.
  local content = file:read('*all')
  file:close()
  -- Parsed JSON data converted to a Lua table.
  json_cache = vim.fn.json_decode(content)
  return json_cache
end

-- Helper function to format a display string combining English and Pali titles.
-- Used to create readable entries for the picker interface.
-- @param english (string or nil): English title or name.
-- @param pali (string or nil): Pali title or name.
-- @return (string): Formatted string in the form "English / Pali".
local function format_display(english, pali)
  -- English title, defaulting to 'Unknown' if nil.
  english = english or 'Unknown'
  -- Pali title, defaulting to 'Unknown' if nil.
  pali = pali or 'Unknown'
  return string.format('%s / %s', english, pali)
end

-- Table to hold picker functions for different levels of navigation.
-- Keeps functions like nikaya_picker, division_picker, etc., in a local scope.
local pickers = {}

-- Function to perform a fuzzy search across suttas.
-- Prompts the user for a query and filters suttas based on number, titles, and Nikaya.
-- @param nikaya_filter (string or nil): Optional Nikaya to filter results (e.g., 'DN').
local function fuzzy_search(nikaya_filter)
  -- Parsed JSON metadata from the file.
  local json_data = read_json_file()
  -- List of sutta entries for the picker.
  local entries = {}

  -- Iterate through JSON data to flatten suttas into entries.
  for _, nikaya_data in ipairs(json_data) do
    -- Nikaya name (e.g., 'DN', 'MN').
    local nikaya = nikaya_data.nikaya
    -- Include Nikaya if no filter is set or it matches the filter.
    if not nikaya_filter or nikaya == nikaya_filter then
      for _, division in ipairs(nikaya_data.divisions or {}) do
        for _, subdivision in ipairs(division.subdivisions or {}) do
          for _, sutta in ipairs(subdivision.suttas or {}) do
            -- Skip invalid suttas with 'error' title or missing path.
            if sutta.sutta_title_english ~= 'error' and sutta.sutta_path then
              -- Display string for the picker (e.g., 'dn18: Title / Pali (DN)').
              local display = string.format(
                '%s: %s / %s (%s)',
                sutta.sutta_number or 'Unknown',
                sutta.sutta_title_english or 'Unknown',
                sutta.sutta_title_pali or 'Unknown',
                nikaya
              )
              -- Add entry with path, display, and searchable text.
              table.insert(entries, {
                path = sutta.sutta_path,
                display = display,
                -- Lowercase text for case-insensitive search.
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

  -- Prompt the user for a search query.
  vim.ui.input({ prompt = 'Search Suttas (e.g., King): ' }, function(query)
    -- User-entered search query, or nil if cancelled.
    if not query or query == '' then
      return
    end
    -- Convert query to lowercase for case-insensitive matching.
    query = string.lower(query)

    -- List of entries matching the query.
    local filtered = {}
    for _, entry in ipairs(entries) do
      -- Check if the query appears in the entry's search_text.
      if entry.search_text:find(query, 1, true) then
        table.insert(filtered, entry)
      end
    end

    -- Show filtered results in a picker.
    vim.ui.select(filtered, {
      prompt = 'Select Sutta (<C-n>:Next, <C-p>:Prev, <CR>:Select)',
      format_item = function(entry)
        return entry.display
      end,
    }, function(choice)
      -- Selected entry, or nil if cancelled.
      if choice then
        -- Open the selected sutta file.
        vim.api.nvim_command('edit ' .. vim.fn.fnameescape(choice.path))
      end
    end)
  end)
end

-- Function to display a picker for selecting a Nikaya or searching all suttas.
-- Entry point for the navigation hierarchy.
function pickers.nikaya_picker()
  -- Parsed JSON metadata.
  local json_data = read_json_file()
  -- List of supported Nikaya codes.
  local nikayas = { 'AN', 'DN', 'MN', 'SN' }
  -- List of picker entries, starting with a search option.
  local entries = {
    { 
      is_search = true, 
      display = 'Search All Suttas', 
      action = function()
        fuzzy_search(nil)
      end 
    },
  }

  -- Add entries for each Nikaya found in the JSON data.
  for _, nikaya in ipairs(nikayas) do
    for _, item in ipairs(json_data) do
      if item.nikaya == nikaya then
        table.insert(entries, { nikaya = nikaya, data = item })
        break
      end
    end
  end

  -- Show Nikaya picker.
  vim.ui.select(entries, {
    prompt = 'Select Nikaya or Search (<C-n>:Next, <C-p>:Prev, <CR>:Select)',
    format_item = function(entry)
      return entry.display or entry.nikaya
    end,
  }, function(choice)
    -- Selected Nikaya or search option, or nil if cancelled.
    if choice then
      if choice.is_search then
        choice.action()
      else
        -- Open division picker for the selected Nikaya.
        pickers.division_picker(choice.data)
      end
    end
  end)
end

-- Function to display a picker for selecting a division within a Nikaya.
-- @param nikaya_data (table): Data for the selected Nikaya, including divisions.
function pickers.division_picker(nikaya_data)
  -- List of picker entries, starting with back and search options.
  local entries = {
    { 
      is_back = true, 
      display = '.. [Back to Nikaya]', 
      action = pickers.nikaya_picker 
    },
    { 
      is_search = true, 
      display = 'Search ' .. nikaya_data.nikaya .. ' Suttas', 
      action = function()
        fuzzy_search(nikaya_data.nikaya)
      end 
    },
  }
  -- List of divisions in the Nikaya, or empty table if none.
  local divisions = nikaya_data.divisions or {}
  -- Special case for DN: skip to sutta picker if no divisions.
  if nikaya_data.nikaya == 'DN' and #divisions == 0 then
    pickers.sutta_picker({ subdivision_data = { suttas = nikaya_data.suttas or {} }, nikaya = nikaya_data.nikaya })
    return
  end
  -- Add entries for each division.
  for _, division in ipairs(divisions) do
    -- English name of the division, or 'Unknown' if missing.
    local english = division.english_name or 'Unknown'
    -- Pali name of the division, or 'Unknown' if missing.
    local pali = division.pali_name or 'Unknown'
    table.insert(entries, {
      division = division,
      display = format_display(english, pali),
      nikaya = nikaya_data.nikaya,
    })
  end

  -- Show division picker.
  vim.ui.select(entries, {
    prompt = 'Select Division (' .. nikaya_data.nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <CR>:Select, <BS>:Back)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Selected division, back, or search option, or nil if cancelled.
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        -- Open subdivision picker for the selected division.
        pickers.subdivision_picker({ division_data = choice.division, nikaya = choice.nikaya })
      end
    end
  end)
end

-- Function to display a picker for selecting a subdivision within a division.
-- @param opts (table): Options with division_data (table) and nikaya (string).
function pickers.subdivision_picker(opts)
  -- Division data containing subdivisions.
  local division_data = opts.division_data
  -- Nikaya name (e.g., 'DN').
  local nikaya = opts.nikaya
  -- List of picker entries, starting with back and search options.
  local entries = {
    { 
      is_back = true, 
      display = '.. [Back to Division]', 
      action = function()
        pickers.division_picker({ nikaya = nikaya, divisions = nikaya_data.divisions or {} })
      end 
    },
    { 
      is_search = true, 
      display = 'Search ' .. nikaya .. ' Suttas', 
      action = function()
        fuzzy_search(nikaya)
      end 
    },
  }
  -- List of subdivisions in the division, or empty table if none.
  local subdivisions = division_data.subdivisions or {}
  -- Special case for DN: skip to sutta picker if no subdivisions.
  if nikaya == 'DN' and #subdivisions == 0 then
    pickers.sutta_picker({ subdivision_data = { suttas = division_data.suttas or {} }, nikaya = nikaya })
    return
  end
  -- Add entries for each subdivision.
  for _, subdivision in ipairs(subdivisions) do
    -- English name of the subdivision, or 'Unknown' if missing.
    local english = subdivision.english_name or 'Unknown'
    -- Pali name of the subdivision, or 'Unknown' if missing.
    local pali = subdivision.pali_name or 'Unknown'
    table.insert(entries, {
      subdivision = subdivision,
      display = format_display(english, pali),
      nikaya = nikaya,
    })
  end

  -- Show subdivision picker.
  vim.ui.select(entries, {
    prompt = 'Select Subdivision (' .. nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <CR>:Select, <BS>:Back)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Selected subdivision, back, or search option, or nil if cancelled.
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        -- Open sutta picker for the selected subdivision.
        pickers.sutta_picker({ subdivision_data = choice.subdivision, nikaya = choice.nikaya })
      end
    end
  end)
end

-- Function to display a picker for selecting a sutta within a subdivision.
-- @param opts (table): Options with subdivision_data (table) and nikaya (string).
function pickers.sutta_picker(opts)
  -- Subdivision data containing suttas.
  local subdivision_data = opts.subdivision_data
  -- Nikaya name (e.g., 'DN').
  local nikaya = opts.nikaya
  -- List of picker entries, starting with back and search options.
  local entries = {
    { 
      is_back = true, 
      display = '.. [Back to Subdivision]', 
      action = function()
        pickers.subdivision_picker({ division_data = subdivision_data.parent_division or {}, nikaya = nikaya })
      end 
    },
    { 
      is_search = true, 
      display = 'Search ' .. nikaya .. ' Suttas', 
      action = function()
        fuzzy_search(nikaya)
      end 
    },
  }

  -- List of suttas in the subdivision, or empty table if none.
  local suttas = subdivision_data.suttas or {}
  -- Debug check for AN suttas.
  if nikaya == 'AN' then
    -- Warn if no suttas are found (for debugging).
    if #suttas == 0 then
      vim.notify('No suttas found for AN subdivision', vim.log.levels.WARN)
    end
  end
  -- Add entries for each valid sutta.
  for _, sutta in ipairs(suttas) do
    -- Skip invalid suttas with 'error' title or missing path.
    if sutta.sutta_title_english ~= 'error' and sutta.sutta_path then
      -- Warn if AN sutta path is invalid (for debugging).
      if nikaya == 'AN' and not vim.fn.filereadable(sutta.sutta_path) then
        vim.notify('Invalid sutta_path for AN: ' .. sutta.sutta_path, vim.log.levels.WARN)
      end
      -- Display string for the picker (e.g., 'dn18: Title / Pali (DN)').
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
      })
    end
  end

  -- Show sutta picker.
  vim.ui.select(entries, {
    prompt = 'Select Sutta (' .. nikaya .. ') or Search (<C-n>:Next, <C-p>:Prev, <CR>:Select, <BS>:Back)',
    format_item = function(entry)
      return entry.display
    end,
  }, function(choice)
    -- Selected sutta, back, or search option, or nil if cancelled.
    if choice then
      if choice.is_back or choice.is_search then
        choice.action()
      else
        -- Open the selected sutta file.
        vim.api.nvim_command('edit ' .. vim.fn.fnameescape(choice.path))
      end
    end
  end)
end

-- Main entry point for the sutta navigator.
-- Sets up a global <BS> keymapping for back navigation and starts the Nikaya picker.
function M.sutta_navigator()
  -- Set up <BS> keymapping for navigating back in the picker hierarchy.
  vim.keymap.set('n', '<BS>', function()
    -- Close the current picker by simulating an empty selection.
    vim.ui.select({}, { prompt = '' }, function() end)
    -- Current picker level (e.g., 'nikaya', 'division'), defaulting to 'nikaya'.
    local current_picker = vim.b.current_picker or 'nikaya'
    -- Navigate back based on the current picker level.
    if current_picker == 'division' then
      pickers.nikaya_picker()
    elseif current_picker == 'subdivision' then
      pickers.division_picker(vim.b.nikaya_data or {})
    elseif current_picker == 'sutta' then
      pickers.subdivision_picker(vim.b.subdivision_opts or {})
    end
  end, { silent = true })

  -- Set the initial picker level to 'nikaya'.
  vim.b.current_picker = 'nikaya'
  -- Start the navigation with the Nikaya picker.
  pickers.nikaya_picker()
end

-- Setup function for the module.
-- Currently only a placeholder, as keymappings are handled in init.lua.
function M.setup()
  -- Keymap handled in init.lua
end

return M
