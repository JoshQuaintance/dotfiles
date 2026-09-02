local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Clear search highlight on <Esc>
keymap("n", "<Esc>", "<cmd>nohlsearch<CR>", opts)

-- Fast escape from Insert mode
keymap("i", "jk", "<Esc>", { desc = "Exit insert mode" })
keymap("i", "kj", "<Esc>", { desc = "Exit insert mode" })

-- macOS Cmd (<D-...>) & Ctrl key mappings
-- Undo & Redo (Cmd+Z / Cmd+Shift+Z / Cmd+Y / Ctrl+Z / Ctrl+Y)
keymap({ "n", "v" }, "<D-z>", "<cmd>undo<CR>", { desc = "Undo" })
keymap("i", "<D-z>", "<Esc><cmd>undo<CR>a", { desc = "Undo" })
keymap({ "n", "v" }, "<D-Z>", "<cmd>redo<CR>", { desc = "Redo" })
keymap("i", "<D-Z>", "<Esc><cmd>redo<CR>a", { desc = "Redo" })
keymap({ "n", "v" }, "<D-y>", "<cmd>redo<CR>", { desc = "Redo" })
keymap({ "n", "v" }, "<C-z>", "<cmd>undo<CR>", { desc = "Undo" })
keymap({ "n", "v" }, "<C-y>", "<cmd>redo<CR>", { desc = "Redo" })

-- Save mappings (Cmd+S / Ctrl+S / Ctrl+W Ctrl+R / <leader>w)
keymap({ "n", "v" }, "<D-s>", "<cmd>w<CR>", { desc = "Save file" })
keymap("i", "<D-s>", "<Esc><cmd>w<CR>a", { desc = "Save file" })
keymap({ "n", "v" }, "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
keymap("i", "<C-s>", "<Esc><cmd>w<CR>a", { desc = "Save file" })
keymap({ "n", "v" }, "<C-w><C-r>", "<cmd>w<CR>", { desc = "Save file" })
keymap("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
keymap("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
keymap("n", "<leader>Q", "<cmd>qa!<CR>", { desc = "Force quit all" })

-- macOS Native Clipboard (Cmd+C / Cmd+V)
keymap("v", "<D-c>", [["+y]], { desc = "Copy to clipboard (Cmd+C)" })
keymap({ "n", "v" }, "<D-v>", [["+p]], { desc = "Paste from clipboard (Cmd+V)" })
keymap("i", "<D-v>", [[<C-r>+]], { desc = "Paste from clipboard (Cmd+V)" })

-- Select All (Cmd+A)
keymap({ "n", "v" }, "<D-a>", "ggVG", { desc = "Select all" })
keymap("i", "<D-a>", "<Esc>ggVG", { desc = "Select all" })

-- Leader-based System Clipboard shortcuts
keymap({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to OS clipboard" })
keymap("n", "<leader>Y", [["+Y]], { desc = "Yank line to OS clipboard" })
keymap({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from OS clipboard" })
keymap({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from OS clipboard" })

-- Quick toggle between Catppuccin and Tokyo Night
local current_theme = "catppuccin-mocha"
keymap("n", "<leader>tt", function()
  if current_theme == "catppuccin-mocha" then
    current_theme = "tokyonight"
    vim.cmd("colorscheme tokyonight")
    vim.notify("Colorscheme: Tokyo Night", vim.log.levels.INFO)
  else
    current_theme = "catppuccin-mocha"
    vim.cmd("colorscheme catppuccin-mocha")
    vim.notify("Colorscheme: Catppuccin Mocha", vim.log.levels.INFO)
  end
end, { desc = "Toggle Theme (Catppuccin / Tokyo Night)" })

-- Better window navigation
keymap("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Window splitting
keymap("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Split window vertically" })
keymap("n", "<leader>sh", "<cmd>split<CR>", { desc = "Split window horizontally" })
keymap("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

-- Buffer navigation (next/previous buffer)
keymap("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Close buffer" })

-- Move lines up and down in visual mode
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Keep indent selection in visual mode
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

-- Keep cursor centered when scrolling & searching
keymap("n", "<C-d>", "<C-d>zz", opts)
keymap("n", "<C-u>", "<C-u>zz", opts)
keymap("n", "n", "nzzzv", opts)
keymap("n", "N", "Nzzzv", opts)

-- Better paste within Neovim (don't overwrite register when pasting over selection in visual mode)
keymap("x", "p", [["_dP]])

-- Comment toggle shortcuts (Cmd+/ or Ctrl+/ or Ctrl+_)
keymap({ "n", "v", "i" }, "<D-/>", function() require("Comment.api").toggle.linewise.current() end, { desc = "Toggle comment" })
keymap("n", "<C-/>", function() require("Comment.api").toggle.linewise.current() end, { desc = "Toggle comment" })
keymap("n", "<C-_>", function() require("Comment.api").toggle.linewise.current() end, { desc = "Toggle comment" })
keymap("v", "<C-/>", "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", { desc = "Toggle comment" })
keymap("v", "<C-_>", "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", { desc = "Toggle comment" })
