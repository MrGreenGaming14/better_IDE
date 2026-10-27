-- Loaded by LazyVim on VeryLazy. Alt keys avoid omp's own Alt/Ctrl bindings.
local map = vim.keymap.set
local function omp(fn)
  return function()
    require("bide.omp")[fn]()
  end
end

map({ "n", "t" }, "<M-o>", omp("toggle"), { desc = "omp panel (toggle)" })
map("n", "<leader>aa", omp("toggle"), { desc = "omp panel (toggle)" })
map({ "n", "t" }, "<M-e>", omp("toggle_explorer"), { desc = "Explorer (toggle)" })
map("t", "<M-w>", "<C-\\><C-n><C-w>", { desc = "Leave terminal + window command" })
map("n", "<leader>af", omp("add_file"), { desc = "Add file to omp" })
map("x", "<leader>as", omp("add_selection"), { desc = "Add selection to omp" })
map("n", "<leader>aF", omp("pick_files"), { desc = "Add any files to omp" })
map("n", "<leader>aq", omp("review"), { desc = "Review omp's last turn" })
