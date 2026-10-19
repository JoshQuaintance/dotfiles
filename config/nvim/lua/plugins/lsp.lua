return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    cmd = { "Mason", "MasonInstall", "MasonUpdate", "LspInfo" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      require("mason").setup({
        ui = {
          border = "rounded",
        },
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = "LSP: " .. desc })
          end

          map("gd", vim.lsp.buf.definition, "Goto Definition")
          map("gD", vim.lsp.buf.declaration, "Goto Declaration")
          map("gr", vim.lsp.buf.references, "Goto References")
          map("gi", vim.lsp.buf.implementation, "Goto Implementation")
          map("K", vim.lsp.buf.hover, "Hover Documentation")
          map("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")
          map("<leader>ca", vim.lsp.buf.code_action, "Code Action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
          map("[d", function()
            vim.diagnostic.jump({ count = -1, float = true })
          end, "Previous Diagnostic")
          map("]d", function()
            vim.diagnostic.jump({ count = 1, float = true })
          end, "Next Diagnostic")
          map("<leader>cd", vim.diagnostic.open_float, "Show Line Diagnostics")
        end,
      })

      local servers = {
        ts_ls = {},
        html = {},
        cssls = {},
        tailwindcss = {},
        jsonls = {},
        eslint = {},
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = {
                globals = { "vim" },
              },
              workspace = {
                checkThirdParty = false,
              },
            },
          },
        },
      }

      local is_mobile = vim.fn.has("android") == 1
        or vim.fn.filereadable("/data/data/com.termux/files/usr/bin/termux-info") == 1
        or os.getenv("TERMUX_VERSION") ~= nil
        or os.getenv("PROOT_TMP_DIR") ~= nil
        or (vim.fn.filereadable("/proc/version") == 1 and (vim.fn.readfile("/proc/version")[1] or ""):lower():match("android") ~= nil)

      local lsp_ensure = is_mobile and { "lua_ls" } or vim.tbl_keys(servers)

      require("mason-lspconfig").setup({
        ensure_installed = lsp_ensure,
        handlers = {
          function(server_name)
            local server_opts = servers[server_name] or {}
            server_opts.capabilities = capabilities
            require("lspconfig")[server_name].setup(server_opts)
          end,
        },
      })
    end,
  },
}
