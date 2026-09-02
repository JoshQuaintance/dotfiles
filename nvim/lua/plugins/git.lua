return {
  -- Interactive visual diff tool
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview - Open Git Diff" },
      { "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview - Close" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview - Current File History" },
    },
    opts = {},
  },

  -- Git Graph visualization in Neovim
  {
    "isakbm/gitgraph.nvim",
    dependencies = { "sindrets/diffview.nvim" },
    opts = {
      symbols = {
        merge_commit = "M",
        commit = "*",
      },
      format = {
        timestamp = "%Y-%m-%d %H:%M",
        fields = { "hash", "timestamp", "author", "branch_name", "tag" },
      },
      hooks = {
        on_select_commit = function(from, to)
          vim.notify("Opening diff for commit: " .. from.hash, vim.log.levels.INFO)
          vim.cmd(":DiffviewOpen " .. from.hash .. "~1.." .. from.hash)
        end,
        on_select_range_commit = function(from, to)
          vim.notify("Opening range diff: " .. from.hash .. " -> " .. to.hash, vim.log.levels.INFO)
          vim.cmd(":DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
        end,
      },
    },
    keys = {
      {
        "<leader>gl",
        function()
          require("gitgraph").draw({}, { all = true, max_count = 5000 })
        end,
        desc = "GitGraph - View Git Graph",
      },
    },
  },
}
