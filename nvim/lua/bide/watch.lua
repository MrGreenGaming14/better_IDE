-- Live reload of files changed on disk (e.g. by omp) while their buffers are visible.
-- LazyVim only runs :checktime on focus/terminal events; this watches each file directly.
local M = {}

---@type table<integer, { handle: uv.uv_fs_event_t, timer: uv.uv_timer_t }>
local watchers = {}
---@type table<integer, boolean> buffers already warned about a disk/unsaved-edit conflict
local warned = {}

local function stop(buf)
  local w = watchers[buf]
  if not w then
    return
  end
  watchers[buf] = nil
  for _, h in ipairs({ w.handle, w.timer }) do
    if not h:is_closing() then
      h:stop()
      h:close()
    end
  end
end

---@param buf integer
function M.reload(buf)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "") then
    return
  end
  if not vim.bo[buf].modified then
    -- autoread is on; reload keeps undo history so `u` reverts an external change
    vim.cmd.checktime(buf)
    return
  end
  if warned[buf] then
    return
  end
  warned[buf] = true
  local name = vim.api.nvim_buf_get_name(buf)
  local rel = vim.fs.relpath(vim.fn.getcwd(), name) or name
  vim.notify(
    "bide: " .. rel .. " changed on disk while you have unsaved edits (:e! loads disk version, :w! keeps yours)",
    vim.log.levels.WARN
  )
end

---@param buf integer
function M.arm(buf)
  stop(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not vim.uv.fs_stat(path) then
    return
  end
  local handle, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
  if not handle or not timer then
    return
  end
  watchers[buf] = { handle = handle, timer = timer }
  handle:start(path, {}, function(err)
    if err or timer:is_closing() then
      return
    end
    timer:stop()
    timer:start(100, 0, function()
      vim.schedule(function()
        if watchers[buf] and watchers[buf].timer == timer then
          M.reload(buf)
          -- re-arm: atomic rename-writes replace the inode the handle watched
          M.arm(buf)
        end
      end)
    end)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("bide_watch", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost" }, {
    group = group,
    callback = function(args)
      warned[args.buf] = nil
      M.arm(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      warned[args.buf] = nil
      stop(args.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.arm(buf)
    end
  end
end

return M
