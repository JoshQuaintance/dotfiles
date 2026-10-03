return {
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local ok, ts = pcall(require, "nvim-treesitter")
      if not ok then
        return
      end

      ts.setup()

      local parsers = {
        "bash",
        "css",
        "html",
        "javascript",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
      }

      local ok_config, config = pcall(require, "nvim-treesitter.config")
      if ok_config then
        local installed = config.get_installed("parsers") or {}
        local to_install = {}
        for _, p in ipairs(parsers) do
          if not vim.tbl_contains(installed, p) then
            table.insert(to_install, p)
          end
        end
        if #to_install > 0 then
          pcall(require("nvim-treesitter.install").install, to_install)
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterHighlight", { clear = true }),
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },
}
