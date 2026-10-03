local opt = vim.opt

-- Appearance & UI
opt.termguicolors = true
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.showmode = false
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Indentation & Tabs
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- System & Performance
-- (Separate Neovim register from OS clipboard; use <leader>y / <leader>p for OS clipboard)
opt.clipboard = ""
opt.mouse = "a"
opt.updatetime = 250
opt.timeoutlen = 300
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.splitright = true
opt.splitbelow = true
opt.wrap = false
