-- VS Code Neovim Keybindings & Leader Shortcuts
-- Automatically loaded when running inside VS Code (asvetliakov.vscode-neovim)

local keymap = vim.keymap.set

-- Helper to invoke VS Code commands cleanly via the extension's lua bridge
local function vsc(command, args)
  return function()
    local ok, vscode = pcall(require, "vscode")
    if ok then
      if args then
        vscode.action(command, { args = args })
      else
        vscode.action(command)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- 1. General & File Management (<leader>w, <leader>q, <leader>e)
-------------------------------------------------------------------------------
keymap("n", "<leader>w", vsc("workbench.action.files.save"), { desc = "Save File" })
keymap("n", "<leader>q", vsc("workbench.action.closeActiveEditor"), { desc = "Close Editor" })
keymap("n", "<leader>Q", vsc("workbench.action.closeAllEditors"), { desc = "Close All Editors" })

-- File Explorer
keymap("n", "<leader>e", vsc("workbench.view.explorer"), { desc = "Toggle File Explorer" })
keymap("n", "<leader>o", vsc("workbench.files.action.focusFilesExplorer"), { desc = "Focus File Explorer" })

-------------------------------------------------------------------------------
-- 2. Find & Navigation (<leader>f...)
-------------------------------------------------------------------------------
keymap("n", "<leader>ff", vsc("workbench.action.quickOpen"), { desc = "Find Files (Quick Open)" })
keymap("n", "<leader>fg", vsc("workbench.action.findInFiles"), { desc = "Live Grep (Find in Files)" })
keymap("n", "<leader>fb", vsc("workbench.action.showAllEditorsByMostRecentlyUsed"), { desc = "Find Buffers (Open Editors)" })
keymap("n", "<leader>fr", vsc("workbench.action.openRecent"), { desc = "Recent Files" })
keymap("n", "<leader>fs", vsc("actions.find"), { desc = "Search Current Buffer" })
keymap("n", "<leader>fh", vsc("workbench.action.openGlobalKeybindings"), { desc = "Help / Keybindings" })
keymap("n", "<leader>fn", vsc("workbench.action.files.newUntitledFile"), { desc = "New File" })

-------------------------------------------------------------------------------
-- 3. Code, Refactoring & LSP (<leader>c...)
-------------------------------------------------------------------------------
keymap({ "n", "v" }, "<leader>ca", vsc("editor.action.quickFix"), { desc = "Code Action / Quick Fix" })
keymap("n", "<leader>rn", vsc("editor.action.rename"), { desc = "Rename Symbol" })
keymap("n", "<leader>cf", vsc("editor.action.formatDocument"), { desc = "Format Document" })
keymap("n", "<leader>cd", vsc("editor.action.showHover"), { desc = "Show Diagnostics / Hover" })
keymap("n", "<leader>cr", vsc("editor.action.goToReferences"), { desc = "Go to References" })
keymap("n", "<leader>ci", vsc("editor.action.goToImplementation"), { desc = "Go to Implementation" })

-------------------------------------------------------------------------------
-- 4. Window & Split Management (<leader>s...)
-------------------------------------------------------------------------------
keymap("n", "<leader>sv", vsc("workbench.action.splitEditor"), { desc = "Split Vertically" })
keymap("n", "<leader>sh", vsc("workbench.action.splitEditorOrthogonal"), { desc = "Split Horizontally" })
keymap("n", "<leader>se", vsc("workbench.action.evenEditorWidths"), { desc = "Equalize Splits" })
keymap("n", "<leader>sx", vsc("workbench.action.closeEditorsInGroup"), { desc = "Close Split Group" })

-- Window navigation (<C-h>, <C-j>, <C-k>, <C-l>)
keymap("n", "<C-h>", vsc("workbench.action.navigateLeft"), { desc = "Navigate Left" })
keymap("n", "<C-j>", vsc("workbench.action.navigateDown"), { desc = "Navigate Down" })
keymap("n", "<C-k>", vsc("workbench.action.navigateUp"), { desc = "Navigate Up" })
keymap("n", "<C-l>", vsc("workbench.action.navigateRight"), { desc = "Navigate Right" })

-------------------------------------------------------------------------------
-- 5. Buffer / Tab Navigation (<S-h>, <S-l>, <leader>b...)
-------------------------------------------------------------------------------
keymap("n", "<S-h>", vsc("workbench.action.previousEditor"), { desc = "Previous Editor Tab" })
keymap("n", "<S-l>", vsc("workbench.action.nextEditor"), { desc = "Next Editor Tab" })
keymap("n", "<leader>bd", vsc("workbench.action.closeActiveEditor"), { desc = "Close Current Buffer" })
keymap("n", "<leader>ba", vsc("workbench.action.closeOtherEditors"), { desc = "Close Other Buffers" })

-------------------------------------------------------------------------------
-- 6. Git & Diff (<leader>g..., <leader>h...)
-------------------------------------------------------------------------------
keymap("n", "<leader>gd", vsc("git.openChange"), { desc = "Git Diff" })
keymap("n", "<leader>gD", vsc("workbench.action.closeActiveEditor"), { desc = "Close Diff" })
keymap("n", "<leader>gs", vsc("workbench.view.scm"), { desc = "Git Source Control" })
keymap("n", "<leader>hp", vsc("workbench.action.editor.nextChange"), { desc = "Next Git Change / Hunk" })
keymap("n", "<leader>hP", vsc("workbench.action.editor.previousChange"), { desc = "Previous Git Change / Hunk" })
keymap("n", "<leader>hb", vsc("gitlens.toggleFileBlame"), { desc = "Toggle Git Blame (GitLens)" })

-------------------------------------------------------------------------------
-- 7. Markdown & Utilities (<leader>m..., <leader>t...)
-------------------------------------------------------------------------------
keymap("n", "<leader>mp", vsc("markdown.showPreviewToSide"), { desc = "Toggle Markdown Preview" })
keymap("n", "<leader>th", vsc("workbench.action.selectTheme"), { desc = "Select Color Theme" })
keymap("n", "<leader>tt", vsc("workbench.action.terminal.toggleTerminal"), { desc = "Toggle Terminal" })
