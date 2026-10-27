-- bide: BIDE_ROOT is the parent of this config dir (reached via ~/.config/bide symlink).
local root = vim.fs.dirname(vim.uv.fs_realpath(vim.fn.stdpath("config")))
vim.env.BIDE_ROOT = root
local v = root .. "/vendor"
vim.env.PATH = table.concat({ v .. "/bin", v .. "/node/bin", v .. "/mason/bin", v .. "/nvim/bin" }, ":")
  .. ":"
  .. vim.env.PATH
vim.g.bide_offline = vim.uv.fs_stat(root .. "/.offline") ~= nil

require("config.lazy")
