-- Based on LazyVim/starter lua/config/lazy.lua; all plugin bytes live in $BIDE_ROOT/vendor/lazy.
local root = vim.env.BIDE_ROOT .. "/vendor/lazy"
local lazypath = root .. "/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  if vim.g.bide_offline then
    error("bide: vendor/lazy missing from offline bundle")
  end
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  root = root,
  rocks = { enabled = false },
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- extras are fixed in git (not managed via :LazyExtras)
    { import = "lazyvim.plugins.extras.editor.snacks_explorer" },
    { import = "lazyvim.plugins.extras.editor.snacks_picker" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.clangd" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit (pinned by lazy-lock.json)
  },
  install = { missing = not vim.g.bide_offline, colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = not vim.g.bide_offline, notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
