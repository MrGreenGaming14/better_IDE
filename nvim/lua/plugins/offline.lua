-- Keep mason packages and treesitter parsers inside $BIDE_ROOT/vendor; never install when offline.
-- Loads after lang.lua (alphabetical), so these opts functions run last.
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, o)
      o.install_root_dir = vim.env.BIDE_ROOT .. "/vendor/mason"
      if vim.g.bide_offline then
        o.ensure_installed = {}
      end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, o)
      o.install_dir = vim.env.BIDE_ROOT .. "/vendor/treesitter"
      if vim.g.bide_offline then
        o.ensure_installed = {}
      end
    end,
  },
}
