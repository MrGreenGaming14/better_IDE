-- omp (oh-my-pi) panel on the right, sending context to it, and the RPC surface used by
-- omp/bide-bridge.ts (`on_change`, `context`) via `nvim --server $NVIM --remote-expr`.
local M = {}

---@type integer? last window showing a normal file buffer
M.last_code_win = nil
---@type integer? quickfix list id of the latest omp turn
M.qf_id = nil

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, gif = true, webp = true }

local function is_code_buf(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

function M.cmd()
  return { "omp", "-e", vim.env.BIDE_ROOT .. "/omp/bide-bridge.ts" }
end

-- Must be identical on every call: the snacks terminal id hashes cmd/cwd/env/count.
function M.term_opts()
  return {
    cwd = vim.fn.getcwd(),
    env = { BIDE_NVIM_BIN = vim.v.progpath },
    count = 1,
    win = { position = "right", width = 0.4 },
    interactive = true,
  }
end

local function have_omp()
  if vim.fn.executable("omp") == 1 then
    return true
  end
  vim.notify("bide: omp not found on PATH — install oh-my-pi on this machine", vim.log.levels.ERROR)
  return false
end

---@return integer? buf
function M.code_buf()
  local win = M.last_code_win
  if win and vim.api.nvim_win_is_valid(win) and is_code_buf(vim.api.nvim_win_get_buf(win)) then
    return vim.api.nvim_win_get_buf(win)
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if is_code_buf(b) then
      M.last_code_win = w
      return b
    end
  end
end

--- Show/focus the omp panel; hide it if it is already focused.
function M.toggle()
  if not have_omp() then
    return
  end
  Snacks.terminal.focus(M.cmd(), M.term_opts())
end

--- Paste `text` into the omp composer (bracketed paste), starting omp if needed.
---@param text string
function M.send(text)
  if not have_omp() then
    return
  end
  local term, created = Snacks.terminal.get(M.cmd(), vim.tbl_extend("force", M.term_opts(), { create = true }))
  if not term then
    return
  end
  local function deliver()
    if not term:buf_valid() then
      return
    end
    vim.api.nvim_chan_send(vim.bo[term.buf].channel, "\27[200~" .. text .. "\27[201~")
    if not term:valid() then
      term:show()
    end
    term:focus()
    vim.cmd.startinsert()
  end
  if not created then
    return deliver()
  end
  -- fresh omp: wait for its UI to draw something before pasting
  local waited = 0
  local function poll()
    if not term:buf_valid() then
      return
    end
    for _, line in ipairs(vim.api.nvim_buf_get_lines(term.buf, 0, -1, false)) do
      if line:find("%S") then
        return vim.defer_fn(deliver, 800)
      end
    end
    waited = waited + 100
    if waited >= 15000 then
      return vim.notify("bide: omp did not start within 15s; nothing sent", vim.log.levels.ERROR)
    end
    vim.defer_fn(poll, 100)
  end
  vim.defer_fn(poll, 100)
end

--- Mention files/directories in omp: `@file`, `` `dir` ``; images are sent alone by absolute path.
---@param paths string[] absolute paths
function M.add_paths(paths)
  local cwd = vim.fn.getcwd()
  local tokens = {}
  for _, p in ipairs(paths) do
    local ext = (p:match("%.([^./]+)$") or ""):lower()
    if IMAGE_EXT[ext] then
      M.send(p)
    else
      local rel = vim.fs.relpath(cwd, p) or p
      if vim.fn.isdirectory(p) == 1 or rel:find("%s") then
        tokens[#tokens + 1] = "`" .. rel .. "`"
      else
        tokens[#tokens + 1] = "@" .. rel
      end
    end
  end
  if #tokens > 0 then
    M.send(table.concat(tokens, " ") .. " ")
  end
end

function M.add_file()
  local buf = M.code_buf()
  if not buf then
    return vim.notify("bide: no file buffer to send", vim.log.levels.WARN)
  end
  M.add_paths({ vim.api.nvim_buf_get_name(buf) })
end

--- Send the visual selection as a fenced block with its file and line range.
function M.add_selection()
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  if a > b then
    a, b = b, a
  end
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  vim.cmd("normal! \27")
  local name = vim.api.nvim_buf_get_name(0)
  local rel = vim.fs.relpath(vim.fn.getcwd(), name) or name
  M.send(("%s:L%d-L%d\n```%s\n%s\n```\n"):format(rel, a, b, vim.bo.filetype, table.concat(lines, "\n")))
end

--- Pick any files under $HOME (Tab to multi-select) and mention them in omp.
function M.pick_files()
  Snacks.picker.files({
    cwd = vim.uv.os_homedir(),
    title = "Add files to omp",
    confirm = function(picker)
      local paths = vim.tbl_map(Snacks.picker.util.path, picker:selected({ fallback = true }))
      picker:close()
      -- picker:close() restores focus/mode in a scheduled callback; queue behind it
      vim.schedule(function()
        M.add_paths(paths)
      end)
    end,
  })
end

function M.toggle_explorer()
  local p = Snacks.picker.get({ source = "explorer" })[1]
  if p then
    p:close()
  else
    Snacks.explorer()
  end
end

--- Open the quickfix list of the latest omp turn.
function M.review()
  local nr = M.qf_id and vim.fn.getqflist({ id = M.qf_id, nr = 0 }).nr or 0
  if nr == 0 then
    return vim.notify("bide: no omp turn yet")
  end
  vim.cmd(nr .. "chistory")
  vim.cmd("copen")
end

local function same_file(a, b)
  local ra, rb = vim.uv.fs_realpath(a), vim.uv.fs_realpath(b)
  return ra ~= nil and ra == rb
end

--- RPC: called by bide-bridge.ts after mutating tools ("edit") and at the end of a turn ("turn").
---@param json string
---@return string
function M.on_change(json)
  local ok, ev = pcall(vim.json.decode, json)
  if not ok or type(ev) ~= "table" or type(ev.files) ~= "table" then
    return ""
  end
  if ev.kind == "edit" then
    local watch = require("bide.watch")
    for _, f in ipairs(ev.files) do
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and same_file(vim.api.nvim_buf_get_name(b), f.path) then
          watch.reload(b)
        end
      end
    end
  elseif ev.kind == "turn" then
    local n = #ev.files
    if n == 0 then
      return ""
    end
    local items = {}
    for _, f in ipairs(ev.files) do
      items[#items + 1] = { filename = f.path, lnum = tonumber(f.line) or 1, col = 1, text = "changed by omp" }
    end
    vim.fn.setqflist({}, " ", {
      title = ("omp: last turn (%d file%s)"):format(n, n == 1 and "" or "s"),
      items = items,
    })
    M.qf_id = vim.fn.getqflist({ id = 0 }).id
    vim.notify(("omp changed %d file(s) — <leader>aq to review"):format(n))
  end
  return ""
end

local MAX_SEL_LINES, MAX_DIAGS = 400, 200

--- RPC: editor state as JSON for omp's `nvim_context` tool.
---@return string
function M.context()
  local null = vim.NIL
  local buf = M.code_buf()
  local current, selection = null, null
  if buf then
    local cursor = { 1, 1 }
    if M.last_code_win and vim.api.nvim_win_is_valid(M.last_code_win) then
      local c = vim.api.nvim_win_get_cursor(M.last_code_win)
      cursor = { c[1], c[2] + 1 }
    end
    local path = vim.api.nvim_buf_get_name(buf)
    current = { path = path, filetype = vim.bo[buf].filetype, cursor = cursor, modified = vim.bo[buf].modified }
    local s, e = vim.api.nvim_buf_get_mark(buf, "<"), vim.api.nvim_buf_get_mark(buf, ">")
    if s[1] > 0 and e[1] > 0 then
      local lines = vim.api.nvim_buf_get_lines(buf, s[1] - 1, e[1], false)
      local truncated = #lines > MAX_SEL_LINES
      if truncated then
        lines = vim.list_slice(lines, 1, MAX_SEL_LINES)
      end
      selection = {
        path = path,
        start_line = s[1],
        end_line = e[1],
        text = table.concat(lines, "\n") .. (truncated and "\n…(truncated)" or ""),
      }
    end
  end

  local open, diags = {}, {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) and is_code_buf(b) then
      local path = vim.api.nvim_buf_get_name(b)
      open[#open + 1] = { path = path, modified = vim.bo[b].modified }
      for _, d in ipairs(vim.diagnostic.get(b)) do
        diags[#diags + 1] = {
          path = path,
          line = d.lnum + 1,
          col = d.col + 1,
          severity = vim.diagnostic.severity[d.severity] or "INFO",
          sev = d.severity,
          source = d.source or null,
          message = d.message,
        }
      end
    end
  end
  table.sort(diags, function(x, y)
    if x.sev ~= y.sev then
      return x.sev < y.sev
    end
    if x.path ~= y.path then
      return x.path < y.path
    end
    return x.line < y.line
  end)
  local out_diags = {}
  for i = 1, math.min(#diags, MAX_DIAGS) do
    diags[i].sev = nil
    out_diags[i] = diags[i]
  end
  -- empty Lua tables must encode as JSON arrays
  local arr_mt = { __jsontype = "array" }
  return vim.json.encode({
    cwd = vim.fn.getcwd(),
    current = current,
    selection = selection,
    open_buffers = setmetatable(open, arr_mt),
    diagnostics = setmetatable(out_diags, arr_mt),
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("bide_omp", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    callback = function()
      if is_code_buf(vim.api.nvim_get_current_buf()) then
        M.last_code_win = vim.api.nvim_get_current_win()
      end
    end,
  })
  if is_code_buf(vim.api.nvim_get_current_buf()) then
    M.last_code_win = vim.api.nvim_get_current_win()
  end
end

return M
