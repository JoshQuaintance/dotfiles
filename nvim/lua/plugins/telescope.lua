return {
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    keys = {
      {
        "<leader>ff",
        function()
          -- Smart search: git files if in git repo, otherwise find files, always strictly excluding node_modules
          local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+", "") == "true"
          if is_git then
            require("telescope.builtin").git_files({
              show_untracked = true,
              file_ignore_patterns = { "node_modules", "node_modules/.*", "%.git/" },
            })
          else
            require("telescope.builtin").find_files({
              hidden = true,
              find_command = { "fd", "--type", "f", "--strip-cwd-prefix", "--hidden", "--exclude", "node_modules", "--exclude", ".git" },
            })
          end
        end,
        desc = "Find Files (Ignoring node_modules)",
      },
      {
        "<leader>fn",
        function()
          -- Explicitly search ALL files including node_modules and ignored files
          require("telescope.builtin").find_files({
            hidden = true,
            no_ignore = true,
            file_ignore_patterns = { "%.git/" },
            prompt_title = "Find All Files (Including node_modules)",
          })
        end,
        desc = "Find All Files (Include node_modules)",
      },
      {
        "<leader>fg",
        function()
          require("telescope.builtin").live_grep({
            additional_args = function()
              return { "--hidden", "--glob", "!node_modules/*", "--glob", "!.git/*" }
            end,
          })
        end,
        desc = "Live Grep (Ignoring node_modules)",
      },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find Buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent Files" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
      { "<leader>fs", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search Current Buffer" },
      { "<leader>th", "<cmd>Telescope colorscheme enable_preview=true<cr>", desc = "Select Colorscheme (Live Preview)" },
    },
    opts = {
      defaults = {
        prompt_prefix = " ",
        selection_caret = " ",
        path_display = { "truncate" },
        file_ignore_patterns = {
          "node_modules",
          "node_modules/.*",
          "%.git/",
          "%.npm/",
          "%.yarn/",
          "%.cache/",
          "%.local/",
          "Library/",
          "%.Trash/",
          "dist/",
          "build/",
          "%.next/",
          "%.turbo/",
          "%.venv/",
          "env/",
          "venv/",
          "target/",
          "%.DS_Store",
          "%.lock",
          "package%-lock%.json",
        },
        mappings = {
          i = {
            ["<C-j>"] = "move_selection_next",
            ["<C-k>"] = "move_selection_previous",
            ["<C-q>"] = "send_to_qflist",
            ["<Esc>"] = "close",
          },
        },
      },
      pickers = {
        find_files = {
          hidden = true,
          find_command = { "fd", "--type", "f", "--strip-cwd-prefix", "--hidden", "--exclude", "node_modules", "--exclude", ".git" },
        },
        colorscheme = {
          enable_preview = true,
        },
      },
    },
  },
}
