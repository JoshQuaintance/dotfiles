return {
  {
    name = "commitlint",
    dir = vim.fn.stdpath("config"),
    ft = { "gitcommit" },
    config = function()
      local ns = vim.api.nvim_create_namespace("commitlint")

      -- Conventional Commit Types
      local valid_types = {
        feat = "A new feature",
        fix = "A bug fix",
        docs = "Documentation only changes",
        style = "Changes that do not affect the meaning of the code",
        refactor = "A code change that neither fixes a bug nor adds a feature",
        perf = "A code change that improves performance",
        test = "Adding missing tests or correcting existing tests",
        build = "Changes that affect the build system or external dependencies",
        ci = "Changes to CI configuration files and scripts",
        chore = "Other changes that don't modify src or test files",
        revert = "Reverts a previous commit",
      }

      -- Extract Jira ticket from current git branch (e.g. feature/SALES-1234-something -> SALES-1234)
      local function get_branch_ticket()
        local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("%s+", "")
        if branch == "" then return nil end
        return branch:match("([A-Z]+%-%d+)")
      end

      -- Main linting function
      local function lint_commit_buffer(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if vim.bo[bufnr].filetype ~= "gitcommit" then return end

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local diagnostics = {}

        -- Find non-comment lines
        local content_lines = {}
        for idx, line in ipairs(lines) do
          if not line:match("^%s*#") then
            table.insert(content_lines, { idx = idx - 1, text = line })
          end
        end

        if #content_lines == 0 or content_lines[1].text:match("^%s*$") then
          table.insert(diagnostics, {
            lnum = 0,
            col = 0,
            severity = vim.diagnostic.severity.ERROR,
            source = "commitlint",
            message = "Commit message header cannot be empty",
          })
          vim.diagnostic.set(ns, bufnr, diagnostics, { virtual_text = true })
          return
        end

        local header_entry = content_lines[1]
        local header = header_entry.text
        local header_lnum = header_entry.idx
        local branch_ticket = get_branch_ticket()

        -- 1. Header length check
        if #header > 100 then
          table.insert(diagnostics, {
            lnum = header_lnum,
            col = 100,
            end_col = #header,
            severity = vim.diagnostic.severity.ERROR,
            source = "commitlint",
            message = string.format("Header is too long (%d/100 chars max) [header-max-length]", #header),
          })
        elseif #header > 72 then
          table.insert(diagnostics, {
            lnum = header_lnum,
            col = 72,
            end_col = #header,
            severity = vim.diagnostic.severity.WARN,
            source = "commitlint",
            message = string.format("Header exceeds recommended 72 chars (%d/72)", #header),
          })
        end

        -- 2. Header format: type(scope)?: (TICKET - )? subject
        local c_type, c_scope, c_rest
        if header:match("^[%w_]+%(") then
          c_type, c_scope, c_rest = header:match("^([%w_]+)%(([^)]*)%):%s*(.*)$")
        else
          c_type, c_rest = header:match("^([%w_]+):%s*(.*)$")
        end

        if not c_type then
          table.insert(diagnostics, {
            lnum = header_lnum,
            col = 0,
            end_col = #header,
            severity = vim.diagnostic.severity.ERROR,
            source = "commitlint",
            message = "Header must follow format: <type>(<scope>): <subject> (e.g. feat: add login) [header-format]",
          })
        else
          -- Check type validity
          local lower_type = c_type:lower()
          if not valid_types[lower_type] then
            table.insert(diagnostics, {
              lnum = header_lnum,
              col = 0,
              end_col = #c_type,
              severity = vim.diagnostic.severity.ERROR,
              source = "commitlint",
              message = string.format("Invalid type '%s'. Allowed: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert [type-enum]", c_type),
            })
          elseif c_type ~= lower_type then
            table.insert(diagnostics, {
              lnum = header_lnum,
              col = 0,
              end_col = #c_type,
              severity = vim.diagnostic.severity.ERROR,
              source = "commitlint",
              message = string.format("Type must be lowercase ('%s') [type-case]", lower_type),
            })
          end

          -- Check scope if present
          if c_scope then
            if c_scope == "" then
              table.insert(diagnostics, {
                lnum = header_lnum,
                col = #c_type,
                end_col = #c_type + 2,
                severity = vim.diagnostic.severity.ERROR,
                source = "commitlint",
                message = "Scope cannot be empty when parentheses are present [scope-empty]",
              })
            elseif c_scope ~= c_scope:lower() then
              table.insert(diagnostics, {
                lnum = header_lnum,
                col = #c_type + 1,
                end_col = #c_type + 1 + #c_scope,
                severity = vim.diagnostic.severity.WARN,
                source = "commitlint",
                message = "Scope should be lowercase [scope-case]",
              })
            end
          end

          -- Check Jira ticket (if branch has ticket or repo uses ticket format)
          local ticket, separator, subject = c_rest:match("^([A-Z]+%-%d+)%s*([%-:]?)%s*(.*)$")

          if branch_ticket then
            if not ticket then
              table.insert(diagnostics, {
                lnum = header_lnum,
                col = #header - #c_rest,
                end_col = #header,
                severity = vim.diagnostic.severity.WARN,
                source = "commitlint",
                message = string.format("Branch has ticket '%s'. Expected format: %s: %s - <subject> [ticket-empty]", branch_ticket, c_type, branch_ticket),
              })
              subject = c_rest
            else
              if separator ~= "-" then
                table.insert(diagnostics, {
                  lnum = header_lnum,
                  col = #header - #c_rest,
                  end_col = #header,
                  severity = vim.diagnostic.severity.ERROR,
                  source = "commitlint",
                  message = "Ticket must be followed by ' - ' (e.g. " .. ticket .. " - <subject>)",
                })
              end
            end
          elseif ticket and separator == "-" then
            -- Ticket provided without branch ticket
          else
            subject = c_rest
          end

          -- Check subject
          if not subject or subject:match("^%s*$") then
            table.insert(diagnostics, {
              lnum = header_lnum,
              col = #header,
              severity = vim.diagnostic.severity.ERROR,
              source = "commitlint",
              message = "Commit subject cannot be empty [subject-empty]",
            })
          else
            -- Check trailing period
            if subject:match("%s*%.$") then
              table.insert(diagnostics, {
                lnum = header_lnum,
                col = #header - 1,
                end_col = #header,
                severity = vim.diagnostic.severity.ERROR,
                source = "commitlint",
                message = "Subject must not end with a period '.' [subject-full-stop]",
              })
            end
          end
        end

        -- 3. Line 2 blank check (if body exists)
        if #content_lines >= 2 then
          local second_line = content_lines[2]
          if second_line.idx == header_lnum + 1 and not second_line.text:match("^%s*$") then
            table.insert(diagnostics, {
              lnum = second_line.idx,
              col = 0,
              end_col = #second_line.text,
              severity = vim.diagnostic.severity.ERROR,
              source = "commitlint",
              message = "Second line must be blank to separate header from body [body-leading-blank]",
            })
          end
        end

        -- 4. Body line length check (lines 3+)
        for i = 2, #content_lines do
          local entry = content_lines[i]
          if #entry.text > 100 then
            table.insert(diagnostics, {
              lnum = entry.idx,
              col = 100,
              end_col = #entry.text,
              severity = vim.diagnostic.severity.WARN,
              source = "commitlint",
              message = string.format("Body line exceeds 100 chars (%d/100) [body-max-line-length]", #entry.text),
            })
          end
        end

        vim.diagnostic.set(ns, bufnr, diagnostics, {
          virtual_text = {
            prefix = "●",
            spacing = 2,
          },
          underline = true,
          signs = true,
        })
      end

      -- Pre-fill template with branch ticket if buffer is empty
      local function prefill_commit_template(bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local first_line = lines[1] or ""
        
        -- Only prefill if first line is completely empty
        if first_line == "" then
          local ticket = get_branch_ticket()
          local template = ""
          if ticket then
            template = ": " .. ticket .. " - "
          else
            template = ": "
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { template })
          -- Place cursor at beginning before the colon
          if vim.api.nvim_get_current_buf() == bufnr then
            pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
          end
        end
      end

      -- Setup autocommands for gitcommit filetype
      local group = vim.api.nvim_create_augroup("CommitLintGroup", { clear = true })

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "gitcommit",
        callback = function(args)
          local bufnr = args.buf

          -- Enable spell check and colorcolumn for commit editing
          vim.opt_local.spell = true
          vim.opt_local.colorcolumn = "72,100"

          -- Pre-fill template if fresh commit
          prefill_commit_template(bufnr)

          -- Initial lint
          vim.defer_fn(function()
            lint_commit_buffer(bufnr)
          end, 50)

          -- Real-time lint on text changes
          vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
            group = group,
            buffer = bufnr,
            callback = function()
              lint_commit_buffer(bufnr)
            end,
          })

          -- Warn on save if errors exist
          vim.api.nvim_create_autocmd("BufWritePre", {
            group = group,
            buffer = bufnr,
            callback = function()
              lint_commit_buffer(bufnr)
              local diags = vim.diagnostic.get(bufnr, { namespace = ns, severity = vim.diagnostic.severity.ERROR })
              if #diags > 0 then
                vim.notify(string.format("⚠️ Commitlint: %d error(s) found! Check inline diagnostics.", #diags), vim.log.levels.WARN)
              end
            end,
          })

          -- Keymap: <leader>ct to pick commit type interactively
          vim.keymap.set("n", "<leader>ct", function()
            local items = {}
            for k, desc in pairs(valid_types) do
              table.insert(items, string.format("%-10s - %s", k, desc))
            end
            table.sort(items)

            vim.ui.select(items, { prompt = "Select Commit Type:" }, function(choice)
              if choice then
                local selected_type = choice:match("^(%S+)")
                local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
                -- Replace or insert type before colon
                if line:match("^[%w_]*:") then
                  line = line:gsub("^[%w_]*:", selected_type .. ":", 1)
                else
                  line = selected_type .. ": " .. line
                end
                vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { line })
                lint_commit_buffer(bufnr)
              end
            end)
          end, { buffer = bufnr, desc = "Commitlint - Choose commit type" })
        end,
      })
    end,
  },
}
