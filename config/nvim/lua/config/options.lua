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

-- Providers
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
if vim.fn.executable("python3") == 1 then
  vim.g.python3_host_prog = vim.fn.exepath("python3")
end

-- Mobile / Termux / PRoot environment detection (shared across plugins)
vim.g.is_mobile = vim.fn.has("android") == 1
  or vim.fn.filereadable("/data/data/com.termux/files/usr/bin/termux-info") == 1
  or os.getenv("TERMUX_VERSION") ~= nil
  or os.getenv("PROOT_TMP_DIR") ~= nil
  or (
    vim.fn.filereadable("/proc/version") == 1
    and (vim.fn.readfile("/proc/version")[1] or ""):lower():match("android") ~= nil
  )
