return {
  {
    "folke/which-key.nvim",
    opts = { spec = { { "<leader>a", group = "ai (omp)" } } },
  },
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            actions = {
              -- `A` in the explorer: mention the selected files/dirs in omp; explorer stays open
              bide_send = function(picker)
                require("bide.omp").add_paths(
                  vim.tbl_map(Snacks.picker.util.path, picker:selected({ fallback = true }))
                )
              end,
            },
            win = { list = { keys = { ["A"] = "bide_send" } } },
          },
        },
      },
    },
  },
}
