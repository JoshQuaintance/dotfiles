-- Set leader keys before loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load core settings
require("config.options")
require("config.keymaps")

-- When running inside VS Code (asvetliakov.vscode-neovim), load VS Code leader mappings
if vim.g.vscode then
  require("config.vscode_keymaps")
else
  -- Bootstrap & initialize lazy.nvim (standalone Neovim only)
  require("config.lazy")
end
