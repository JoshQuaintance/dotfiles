return {
  {
    "wallpants/github-preview.nvim",
    cmd = { "GithubPreviewToggle", "GithubPreviewStart", "GithubPreviewStop" },
    ft = { "markdown" },
    keys = {
      { "<leader>mp", "<cmd>GithubPreviewToggle<cr>", desc = "Toggle GitHub Markdown Preview" },
    },
    opts = {},
    config = function(_, opts)
      local ghp = require("github-preview")
      ghp.setup(opts)

      local fns = ghp.fns
      vim.keymap.set("n", "<leader>mp", fns.toggle, { desc = "Toggle GitHub Markdown Preview" })
      vim.keymap.set("n", "<leader>ms", fns.single_file_toggle, { desc = "Toggle Single File Preview" })
      vim.keymap.set("n", "<leader>md", fns.details_tags_toggle, { desc = "Toggle Details Tags" })
    end,
  },
}
