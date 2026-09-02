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
          map("[d", vim.diagnostic.goto_prev, "Previous Diagnostic")
          map("]d", vim.diagnostic.goto_next, "Next Diagnostic")
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

      require("mason-lspconfig").setup({
        ensure_installed = vim.tbl_keys(servers),
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
