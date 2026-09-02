return {
  -- Tokyo Night
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = false,
      styles = {
        sidebars = "dark",
        floats = "dark",
      },
    },
  },

  -- Catppuccin (Mocha, Macchiato, Frappe, Latte)
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha", -- mocha, macchiato, frappe, latte
      transparent_background = false,
      integrations = {
        cmp = true,
        gitsigns = true,
        neotree = true,
        treesitter = true,
        which_key = true,
        telescope = { enabled = true },
        bufferline = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      -- Set default active colorscheme
      vim.cmd("colorscheme catppuccin-mocha")
    end,
  },
}
