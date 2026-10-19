local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- 1. Highlight yanked text briefly
autocmd("TextYankPost", {
  group = augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.hl.on_yank({ timeout = 150 })
  end,
})

-- 2. Restore last cursor position when reopening a file (skip gitcommit)
autocmd("BufReadPost", {
  group = augroup("RestoreCursor", { clear = true }),
  callback = function(event)
    local exclude = { "gitcommit" }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].last_loc_restored then
      return
    end
    vim.b[buf].last_loc_restored = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- 3. Close utility/help buffers with 'q'
autocmd("FileType", {
  group = augroup("CloseWithQ", { clear = true }),
  pattern = { "help", "qf", "lspinfo", "man", "checkhealth" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true, desc = "Close window" })
  end,
})

-- 4. Auto-equalize splits when the terminal window is resized
autocmd("VimResized", {
  group = augroup("ResizeSplits", { clear = true }),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. current_tab)
  end,
})
