local api = vim.api
local todo = require("todo_graph")

local View = {}
View.__index = View

local uv = vim.uv or vim.loop
-- Footer hint text shown in the shortcuts row.
local instructions = "q: close   r: refresh   Enter: toggle"

-- option helpers (handle newer nvim_set_option_value when available)
-- Tiny shims to support both nvim_set_option_value and older APIs.
local function buf_set_option(buf, name, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(name, value, { buf = buf })
  end
  return api.nvim_buf_set_option(buf, name, value)
end

local function win_set_option(win, name, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(name, value, { win = win })
  end
  return api.nvim_win_set_option(win, name, value)
end

-- Backward-compatible list detector.
local function is_list(tbl)
  if vim.islist then
    return vim.islist(tbl)
  end
  return vim.tbl_islist(tbl)
end

-- filesystem helpers
-- Safe fs stat helper that works on both vim.uv and vim.loop.
local function file_exists(path)
  return path and uv.fs_stat(path) ~= nil
end

-- Does a .todo-graph or .todo-graph.json exist at the root?
local function graph_exists(root)
  local base = vim.fn.fnamemodify(root or ".", ":p")
  return file_exists(base .. "/.todo-graph") or file_exists(base .. "/.todo-graph.json")
end

-- buffers/windows
-- Scratch buffer with sane defaults for floating UI.
local function create_buf(filetype)
  local buf = api.nvim_create_buf(false, true)
  buf_set_option(buf, "bufhidden", "wipe")
  buf_set_option(buf, "buftype", "nofile")
  buf_set_option(buf, "swapfile", false)
  buf_set_option(buf, "modifiable", false)
  if filetype then
    buf_set_option(buf, "filetype", filetype)
  end
  return buf
end

-- Compute layout sizes/positions for tree, preview, and footer.
local function layout()
  local total_width = math.max(80, math.floor(vim.o.columns * 0.9))
  local gap = 2
  local usable = total_width - gap
  local tree_width = math.max(35, math.floor(usable * 0.4))
  local preview_width = math.max(40, total_width - tree_width - gap)
  local height = math.max(20, math.floor(vim.o.lines * 0.7))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - (tree_width + gap + preview_width)) / 2)
  return {
    tree_width = tree_width,
    preview_width = preview_width,
    gap = gap,
    height = height,
    row = row,
    col = col,
    total_width = tree_width + gap + preview_width,
  }
end

-- Update preview window title (no-op if window is invalid).
local function set_preview_title(win, title)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  api.nvim_win_set_config(win, {
    title = " " .. title .. " ",
    title_pos = "center",
  })
end

-- Create tree (left), preview (right), and footer (shortcuts) windows.
local function open_windows(tree_buf, preview_buf)
  local dims = layout()

  local tree_win = api.nvim_open_win(tree_buf, true, {
    relative = "editor",
    width = dims.tree_width,
    height = dims.height,
    row = dims.row,
    col = dims.col,
    border = "rounded",
    title = " TODO Graph ",
    title_pos = "center",
    style = "minimal",
  })

  local preview_win = api.nvim_open_win(preview_buf, false, {
    relative = "editor",
    width = dims.preview_width,
    height = dims.height,
    row = dims.row,
    col = dims.col + dims.tree_width + dims.gap,
    border = "rounded",
    style = "minimal",
  })

  for _, win in ipairs({ tree_win, preview_win }) do
    win_set_option(win, "number", false)
    win_set_option(win, "relativenumber", false)
    win_set_option(win, "signcolumn", "no")
    win_set_option(win, "foldcolumn", "0")
    win_set_option(win, "wrap", false)
  end
  win_set_option(tree_win, "cursorline", true)
  win_set_option(preview_win, "cursorline", false)
  win_set_option(preview_win, "number", true)

  set_preview_title(preview_win, "Preview")

  -- footer window for key hints
  local footer_buf = api.nvim_create_buf(false, true)
  buf_set_option(footer_buf, "bufhidden", "wipe")
  buf_set_option(footer_buf, "buftype", "nofile")
  buf_set_option(footer_buf, "swapfile", false)
  buf_set_option(footer_buf, "modifiable", true)
  api.nvim_buf_set_lines(footer_buf, 0, -1, false, { instructions })
  buf_set_option(footer_buf, "modifiable", false)

  local footer_row = dims.row + dims.height + 2
  local footer_win = api.nvim_open_win(footer_buf, false, {
    relative = "editor",
    width = dims.total_width,
    height = 1,
    row = footer_row,
    col = dims.col,
    style = "minimal",
    border = "rounded",
  })
  win_set_option(footer_win, "wrap", false)
  win_set_option(footer_win, "cursorline", false)
  win_set_option(footer_win, "number", false)
  win_set_option(footer_win, "relativenumber", false)
  win_set_option(footer_win, "signcolumn", "no")

  return tree_win, preview_win, footer_win, footer_buf
end

-- graph normalization
  -- Normalize todos from map or list into a map keyed by id.
local function normalize_todos(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local todos = {}
  if is_list(raw) then
    for _, t in ipairs(raw) do
      local id = t and (t.id or t.ID)
      if type(id) == "string" then
        todos[id] = {
          id = id,
          file = t.file or t.File,
          line = t.line or t.Line,
        }
      end
    end
  else
    for id, t in pairs(raw) do
      if type(id) == "string" and type(t) == "table" then
        todos[id] = {
          id = id,
          file = t.file or t.File,
          line = t.line or t.Line,
        }
      end
    end
  end
  return todos
end

-- Normalize edges; accept lower/upper-case keys.
local function normalize_edges(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local edges = {}
  for _, e in ipairs(raw) do
    if type(e) == "table" then
      local from = e.from or e.From
      local to = e.to or e.To
      if type(from) == "string" and type(to) == "string" then
        table.insert(edges, { from = from, to = to })
      end
    end
  end
  return edges
end

-- Build roots and adjacency for the tree render.
local function build_index(g)
  local todos = normalize_todos(g.todos or {})
  local edges = normalize_edges(g.edges or {})

  local children = {}
  local indegree = {}
  for id in pairs(todos) do
    indegree[id] = 0
    children[id] = {}
  end

  for _, e in ipairs(edges) do
    local from = e and e.from
    local to = e and e.to
    if type(from) == "string" and type(to) == "string" then
      children[from] = children[from] or {}
      table.insert(children[from], to)
      indegree[to] = (indegree[to] or 0) + 1
      if indegree[from] == nil then
        indegree[from] = 0
      end
    end
  end

  for _, list in pairs(children) do
    table.sort(list)
  end

  local roots = {}
  for id, deg in pairs(indegree) do
    if deg == 0 then
      table.insert(roots, id)
    end
  end
  if #roots == 0 then
    for id in pairs(children) do
      table.insert(roots, id)
    end
  end
  table.sort(roots)

  return roots, children, todos
end

-- Render tree lines and fill line_index[row]=id for quick lookup.
local function render_tree(roots, children, todos, expanded, line_index)
  local lines = {}
  local function append_line(id, depth)
    local todo_item = todos[id]
    local loc = ""
    if todo_item and todo_item.file then
      loc = string.format(" (%s:%s)", todo_item.file, todo_item.line or "?")
    end
    local kids = children[id] or {}
    local has_children = #kids > 0
    if expanded[id] == nil then
      expanded[id] = true
    end
    local marker = has_children and (expanded[id] and "[-]" or "[+]") or "   "
    local prefix = string.rep("  ", depth)
    table.insert(lines, string.format("%s%s %s%s", prefix, marker, id, loc))
    line_index[#lines] = id
    if has_children and expanded[id] then
      for _, child in ipairs(kids) do
        append_line(child, depth + 1)
      end
    end
  end

  for _, r in ipairs(roots) do
    append_line(r, 0)
  end
  if #lines == 0 then
    lines = { "(no TODOs found)" }
  end
  return lines
end

local function resolve_path(root, path)
  if not path or path == "" then
    return nil
  end
  if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
    return path
  end
  root = root or "."
  return vim.fn.fnamemodify(root .. "/" .. path, ":p")
end

function View:update_preview()
  if not (self.preview_buf and api.nvim_buf_is_valid(self.preview_buf)) then
    return
  end

  local row = api.nvim_win_get_cursor(self.win)[1]
  local id = self.line_to_id[row]
  if not (id and self.todos and self.todos[id]) then
    buf_set_option(self.preview_buf, "modifiable", true)
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, { "(select a TODO to preview)" })
    buf_set_option(self.preview_buf, "modifiable", false)
    api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
    self.highlight_line = nil
    return
  end

  local todo_item = self.todos[id]
  local path = resolve_path(self.dir, todo_item.file)
  local lnum = tonumber(todo_item.line) or 1
  self.highlight_line = nil

  set_preview_title(self.preview_win, path and vim.fn.fnamemodify(path, ":~:.") or "(unknown file)")

  local lines
  if path and vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(vim.fn.readfile, path)
    if not ok then
      lines = { "(failed to read file)" }
    else
      lines = data
      local total = #data
      if total > 0 then
        local target = math.max(1, math.min(lnum, total))
        self.highlight_line = target - 1
      end
    end
  else
    lines = { "(file not found)" }
  end

  api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
  buf_set_option(self.preview_buf, "modifiable", true)
  api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, lines)
  buf_set_option(self.preview_buf, "modifiable", false)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  if ft then
    buf_set_option(self.preview_buf, "filetype", ft)
  end
  if self.highlight_line and self.highlight_line >= 0 then
    api.nvim_buf_add_highlight(self.preview_buf, self.ns, "Search", self.highlight_line, 0, -1)
  end
end

function View:refresh()
  local cwd = uv.cwd and uv.cwd() or vim.fn.getcwd()
  self.dir = vim.fn.fnamemodify(self.dir or (cwd or "."), ":p")

  if not graph_exists(self.dir) then
    local msg = {
      "No .todo-graph or .todo-graph.json found.",
      "Root: " .. vim.fn.fnamemodify(self.dir, ":~"),
    }
    self.line_to_id = {}
    self.todos = {}
    buf_set_option(self.buf, "modifiable", true)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, msg)
    buf_set_option(self.buf, "modifiable", false)
    buf_set_option(self.preview_buf, "modifiable", true)
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, { "(no graph to preview)" })
    buf_set_option(self.preview_buf, "modifiable", false)
    set_preview_title(self.preview_win, "No graph")
    return
  end

  local graph, err = todo.graph({ dir = self.dir })
  if err then
    buf_set_option(self.buf, "modifiable", true)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, { "Error:", "  " .. err })
    buf_set_option(self.buf, "modifiable", false)
    return
  end

  local roots, children, todos = build_index(graph)
  self.todos = todos
  self.line_to_id = {}
  local lines = render_tree(roots, children, todos, self.expanded, self.line_to_id)

  buf_set_option(self.buf, "modifiable", true)
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  buf_set_option(self.buf, "modifiable", false)
  self:update_preview()
end

function View:toggle_line()
  local row = api.nvim_win_get_cursor(self.win)[1]
  local id = self.line_to_id[row]
  if not id then
    return
  end
  self.expanded[id] = not self.expanded[id]
  self:refresh()
end

local function focus_tree(view)
  if view.win and api.nvim_win_is_valid(view.win) then
    api.nvim_set_current_win(view.win)
  end
end

local function focus_preview(view)
  if view.preview_win and api.nvim_win_is_valid(view.preview_win) then
    api.nvim_set_current_win(view.preview_win)
  end
end

local function close_all(view)
  for _, win in ipairs({ view.win, view.preview_win, view.footer_win }) do
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end
end

local function set_keymaps(view)
  local function map(buf, lhs, fn)
    api.nvim_buf_set_keymap(buf, "n", lhs, "", {
      nowait = true,
      noremap = true,
      callback = fn,
    })
  end

  map(view.buf, "q", function()
    close_all(view)
  end)
  map(view.preview_buf, "q", function()
    close_all(view)
  end)

  map(view.buf, "r", function()
    view:refresh()
  end)
  map(view.preview_buf, "r", function()
    view:refresh()
  end)

  map(view.buf, "<CR>", function()
    view:toggle_line()
  end)

  map(view.buf, "<Tab>", function()
    focus_preview(view)
  end)
  map(view.buf, "<S-Tab>", function()
    focus_tree(view)
  end)

  map(view.preview_buf, "<Tab>", function()
    focus_tree(view)
  end)
  map(view.preview_buf, "<S-Tab>", function()
    focus_tree(view)
  end)

  local group = api.nvim_create_augroup("TodoGraphView" .. view.buf, { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = view.buf,
    callback = function()
      view:update_preview()
    end,
  })
end

function View.open(opts)
  opts = opts or {}
  local view = setmetatable({}, View)
  view.dir = opts.dir
  view.buf = create_buf("todo-graph")
  view.preview_buf = create_buf()
  view.win, view.preview_win, view.footer_win, view.footer_buf = open_windows(view.buf, view.preview_buf)
  view.expanded = {}
  view.line_to_id = {}
  view.ns = api.nvim_create_namespace("todo_graph_view")
  view.todos = {}

  set_keymaps(view)
  view:refresh()
end

return View
