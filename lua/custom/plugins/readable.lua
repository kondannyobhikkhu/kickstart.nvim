return {
  -- Goyo: Distraction-free reading
  {
    'junegunn/goyo.vim',
    config = function()
      -- Goyo keybinding
      vim.keymap.set('n', '<Leader>g', ':Goyo<CR>', { noremap = true, silent = true })
    end,
  },
  -- Limelight: Dim inactive text
  {
    'junegunn/limelight.vim',
    config = function()
      -- Limelight: auto-toggle with Goyo
      vim.api.nvim_create_autocmd('User', {
        pattern = 'GoyoEnter',
        command = 'Limelight',
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'GoyoLeave',
        command = 'Limelight!',
      })
      vim.g.limelight_conceal_ctermfg = 'gray'
    end,
  },
  -- vim-pencil: Prose editing
  {
    'reedes/vim-pencil',
    config = function()
      -- vim-pencil: soft wrap for text files
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'text',
        callback = function()
          vim.fn['pencil#init'] { wrap = 'soft' }
        end,
      })
    end,
  },
  --  -- Solarized: Readable colorscheme
  --  {
  --    'altercation/vim-colors-solarized',
  --    config = function()
  --      -- Solarized colorscheme
  --      vim.o.background = 'dark' -- or 'dark'
  --      vim.cmd 'colorscheme solarized'
  --    end,
  --  },
}
