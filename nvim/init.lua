-- Set leader keys before loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load core settings
require("config.options")
require("config.keymaps")

-- Bootstrap & initialize lazy.nvim
require("config.lazy")
