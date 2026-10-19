return {
  -- Git integration in gutter
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        map("n", "]h", gs.next_hunk, { desc = "Next Git hunk" })
        map("n", "[h", gs.prev_hunk, { desc = "Prev Git hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview Git hunk" })
        map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, { desc = "Blame line" })
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage Git hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset Git hunk" })
        map("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Stage selected Git hunk" })
        map("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Reset selected Git hunk" })
        map("n", "<leader>hS", gs.stage_buffer, { desc = "Stage entire buffer" })
        map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "Undo stage Git hunk" })
      end,
    },
  },

  -- Auto-close quotes and brackets
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true,
  },

  -- Fast commenting with gcc / gc
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = true,
  },

  -- Indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      indent = { char = "│" },
      scope = { enabled = false },
    },
  },
}
