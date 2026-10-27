-- Headless vendoring: install every mason package and treesitter parser the config needs
-- into $BIDE_ROOT/vendor, verify, then exit (0 = ok, 1 = something missing).
local M = {}

local function fail(msg)
  io.stderr:write("bide vendor: " .. msg .. "\n")
  vim.cmd("cquit 1")
end

function M.packages()
  local pkgs, seen = {}, {}
  local function add(p)
    if p and not seen[p] then
      seen[p] = true
      pkgs[#pkgs + 1] = p
    end
  end
  for _, p in ipairs(LazyVim.opts("mason.nvim").ensure_installed or {}) do
    add(p)
  end
  local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  for name, cfg in pairs(LazyVim.opts("nvim-lspconfig").servers or {}) do
    if name ~= "*" and type(cfg) == "table" and cfg.enabled ~= false and cfg.mason ~= false then
      add(map[name])
    end
  end
  table.sort(pkgs)
  return pkgs
end

function M.sync()
  local ok, err = pcall(function()
    require("lazy").load({ plugins = { "mason.nvim", "mason-lspconfig.nvim", "nvim-lspconfig", "nvim-treesitter" } })
    local registry = require("mason-registry")
    local pkgs = M.packages()
    io.stdout:write("bide vendor: mason " .. table.concat(pkgs, " ") .. "\n")
    vim.cmd("MasonInstall " .. table.concat(pkgs, " "))

    local parsers = LazyVim.opts("nvim-treesitter").ensure_installed or {}
    require("nvim-treesitter").install(parsers, { summary = true }):wait(900000)

    local missing = {}
    for _, p in ipairs(pkgs) do
      if not registry.get_package(p):is_installed() then
        missing[#missing + 1] = p
      end
    end
    local have = {}
    for _, p in ipairs(require("nvim-treesitter").get_installed("parsers")) do
      have[p] = true
    end
    for _, p in ipairs(parsers) do
      if not have[p] then
        missing[#missing + 1] = "parser:" .. p
      end
    end
    if #missing > 0 then
      error("missing " .. table.concat(missing, " "), 0)
    end
  end)
  if not ok then
    return fail(tostring(err))
  end
  io.stdout:write("bide vendor: ok\n")
  vim.cmd("qa!")
end

return M
