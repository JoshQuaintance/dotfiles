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

      local is_mobile = vim.fn.has("android") == 1
        or vim.fn.filereadable("/data/data/com.termux/files/usr/bin/termux-info") == 1
        or os.getenv("TERMUX_VERSION") ~= nil
        or os.getenv("PROOT_TMP_DIR") ~= nil
        or (vim.fn.filereadable("/proc/version") == 1 and (vim.fn.readfile("/proc/version")[1] or ""):lower():match("android") ~= nil)

      local parsers
      if is_mobile then
        parsers = { "bash", "json", "lua", "markdown", "markdown_inline", "vim", "vimdoc" }
      else
        parsers = {
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
      end

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
