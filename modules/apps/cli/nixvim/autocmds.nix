# modules/apps/cli/nixvim/autocmds.nix
# Autocommands: yank highlight, split resize, filetype-local quit binding
_: {
  programs.nixvim.extraConfigLua = ''
    -- Highlight on yank
    local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
    vim.api.nvim_create_autocmd('TextYankPost', {
      callback = function()
        vim.highlight.on_yank({ timeout = 200 })
      end,
      group = highlight_group,
      pattern = '*',
    })

    -- Auto-resize splits when terminal is resized
    vim.api.nvim_create_autocmd('VimResized', {
      callback = function()
        vim.cmd('tabdo wincmd =')
      end,
    })

    -- Close certain filetypes with 'q'
    vim.api.nvim_create_autocmd('FileType', {
      pattern = {
        'qf',
        'help',
        'man',
        'notify',
        'lspinfo',
        'spectre_panel',
        'startuptime',
        'tsplayground',
        'PlenaryTestPopup',
      },
      callback = function(event)
        vim.bo[event.buf].buflisted = false
        vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = event.buf, silent = true })
      end,
    })

    -- Remember cursor position
    vim.api.nvim_create_autocmd('BufReadPost', {
      callback = function()
        local mark = vim.api.nvim_buf_get_mark(0, '"')
        local lcount = vim.api.nvim_buf_line_count(0)
        if mark[1] > 0 and mark[1] <= lcount then
          pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
      end,
    })

    -- Close the snacks explorer before saving a session (persistence.nvim).
    -- A restored session that reopens an explorer window hits "Buffer with
    -- this name already exists" on the next toggle. Guarded so it is inert
    -- when snacks is not loaded, since the explorer sits behind a preset.
    vim.api.nvim_create_autocmd('User', {
      pattern = 'PersistenceSavePre',
      callback = function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
          if ft:match('^snacks_') then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
      end,
    })
  '';
}
