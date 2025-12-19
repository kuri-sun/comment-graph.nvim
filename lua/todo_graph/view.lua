local api = vim.api
local todo = require("todo_graph")

local View = {}
View.__index = View

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "filetype", "todo-graph")
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  return buf
end

local function create_preview_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "modifiable", false)
  return buf
end

local function layout()
  local total_width = math.max(80, math.floor(vim.o.columns * 0.9))
  local gap = 2
  local tree_width = math.max(35, math.floor(total_width * 0.4))
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
  }
end

local function open_windows(tree_buf, preview_buf)
  local dims = layout()

  local tree_win = api.nvim_open_win(tree_buf, true, {
    relative = "editor",
    width = dims.tree_width,
    height = dims.height,
    row = dims.row,
    col = dims.col,
    border = "rounded",
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
    api.nvim_win_set_option(win, "number", false)
    api.nvim_win_set_option(win, "relativenumber", false)
    api.nvim_win_set_option(win, "signcolumn", "no")
    api.nvim_win_set_option(win, "foldcolumn", "0")
    api.nvim_win_set_option(win, "wrap", false)
  end
  api.nvim_win_set_option(tree_win, "cursorline", true)
  api.nvim_win_set_option(preview_win, "cursorline", false)
  -- We render line numbers manually inside the preview content.
  api.nvim_win_set_option(preview_win, "number", false)

  return tree_win, preview_win
end

local function normalize_todos(raw)
  if type(raw) ~= "table" then
    return {}
  end
  -- If already a map, normalize values; if it's a list, re-map by id.
  local is_list = vim.tbl_islist(raw)
  local todos = {}
  if is_list then
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

local function build_index(g)
  local todos = g.todos or {}
  todos = normalize_todos(todos)

  local edges = g.edges or {}
  edges = normalize_edges(edges)

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

local function render_tree(roots, children, todos, expanded, line_index)
  local lines = {}

  local function append_line(id, depth)
    local todo = todos[id]
    local loc = ""
    if todo and todo.file then
      loc = string.format(" (%s:%s)", todo.file, todo.line or "?")
    end
    local kids = children[id] or {}
    local has_children = #kids > 0
    if expanded[id] == nil then
      expanded[id] = depth == 0
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
  table.insert(lines, "")
  table.insert(lines, "q:close  <CR>:toggle  r:refresh")
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
  local joined = vim.fn.fnamemodify(root .. "/" .. path, ":p")
  return joined
end

function View:update_preview()
  if not (self.preview_buf and api.nvim_buf_is_valid(self.preview_buf)) then
    return
  end

  local row = api.nvim_win_get_cursor(self.win)[1]
  local id = self.line_to_id[row]
  if not (id and self.todos and self.todos[id]) then
    api.nvim_buf_set_option(self.preview_buf, "modifiable", true)
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, { "(select a TODO to preview)" })
    api.nvim_buf_set_option(self.preview_buf, "modifiable", false)
    api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
    self.highlight_line = nil
    return
  end

  local todo = self.todos[id]
  local path = resolve_path(self.dir, todo.file)
  local lnum = tonumber(todo.line) or 1
  self.highlight_line = nil
  local header = {
    "ID: " .. id,
    "File: " .. (path and vim.fn.fnamemodify(path, ":~:.") or (todo.file or "(unknown)")),
    "",
  }

  local lines
  if path and vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(vim.fn.readfile, path)
    if not ok then
      lines = { "(failed to read file)" }
    else
      local total = #data
      local start = math.max(1, lnum - 8)
      local finish = math.min(total, lnum + 8)
      lines = {}
      for i = start, finish do
        lines[#lines + 1] = string.format("%5d %s", i, data[i])
      end
      self.highlight_line = (lnum - start)
    end
  else
    lines = { "(file not found)" }
  end

  api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
  api.nvim_buf_set_option(self.preview_buf, "modifiable", true)
  api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, vim.list_extend(vim.deepcopy(header), lines))
  api.nvim_buf_set_option(self.preview_buf, "modifiable", false)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  if ft then
    api.nvim_buf_set_option(self.preview_buf, "filetype", ft)
  end
  if self.highlight_line and self.highlight_line >= 0 then
    local hl_line = #header + self.highlight_line
    api.nvim_buf_add_highlight(self.preview_buf, self.ns, "Search", hl_line, 0, -1)
  end
end

function View:refresh()
  local graph, err = todo.graph({ dir = self.dir })
  if err then
    api.nvim_buf_set_option(self.buf, "modifiable", true)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, { "Error:", "  " .. err })
    api.nvim_buf_set_option(self.buf, "modifiable", false)
    return
  end

  local roots, children, todos = build_index(graph)
  self.todos = todos
  self.line_to_id = {}
  local lines = render_tree(roots, children, todos, self.expanded, self.line_to_id)

  local dir_display = self.dir or vim.loop.cwd() or "."
  dir_display = vim.fn.fnamemodify(dir_display, ":~")
  local header = { "TODO Graph", "Dir: " .. dir_display, "" }
  local new_index = {}
  for line_num, id in pairs(self.line_to_id) do
    new_index[line_num + #header] = id
  end
  self.line_to_id = new_index
  for i = #header, 1, -1 do
    table.insert(lines, 1, header[i])
  end

  api.nvim_buf_set_option(self.buf, "modifiable", true)
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_buf_set_option(self.buf, "modifiable", false)
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

local function set_keymaps(view)
  api.nvim_buf_set_keymap(view.buf, "n", "q", "", {
    nowait = true,
    noremap = true,
    callback = function()
      if api.nvim_win_is_valid(view.win) then
        api.nvim_win_close(view.win, true)
      end
      if view.preview_win and api.nvim_win_is_valid(view.preview_win) then
        api.nvim_win_close(view.preview_win, true)
      end
    end,
  })
  api.nvim_buf_set_keymap(view.buf, "n", "r", "", {
    nowait = true,
    noremap = true,
    callback = function()
      view:refresh()
    end,
  })
  api.nvim_buf_set_keymap(view.buf, "n", "<CR>", "", {
    nowait = true,
    noremap = true,
    callback = function()
      view:toggle_line()
    end,
  })

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
  view.buf = create_buf()
  view.preview_buf = create_preview_buf()
  view.win, view.preview_win = open_windows(view.buf, view.preview_buf)
  view.expanded = {}
  view.line_to_id = {}
  view.ns = api.nvim_create_namespace("todo_graph_view")
  view.todos = {}

  set_keymaps(view)
  view:refresh()
end

return View
