return {
  -- Icons
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },

  -- Statusline (Auto-adapts to active colorscheme)
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = { left = "|", right = "|" },
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  -- Bufferline (Tabs on top)
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        always_show_bufferline = false,
        offsets = {
          {
            filetype = "neo-tree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left",
          },
        },
      },
    },
  },

  -- Keybinding helper popup
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      spec = {
        { "<leader>f", group = "Find / Telescope" },
        { "<leader>b", group = "Buffer" },
        { "<leader>s", group = "Split Window" },
        { "<leader>c", group = "Code / LSP" },
        { "<leader>g", group = "Git / GitGraph / Diff" },
        { "<leader>h", group = "Git Hunk" },
        { "<leader>m", group = "Markdown Preview" },
        { "<leader>t", group = "Theme / Toggle" },
      },
    },
  },
}
