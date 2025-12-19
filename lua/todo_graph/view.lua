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

local function open_window(buf)
  local width = math.max(50, math.floor(vim.o.columns * 0.5))
  local height = math.max(20, math.floor(vim.o.lines * 0.7))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    style = "minimal",
  })

  api.nvim_win_set_option(win, "number", false)
  api.nvim_win_set_option(win, "relativenumber", false)
  api.nvim_win_set_option(win, "signcolumn", "no")
  api.nvim_win_set_option(win, "foldcolumn", "0")
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "cursorline", true)

  return win
end

local function build_index(g)
  local todos = g.todos or {}
  if type(todos) ~= "table" then
    todos = {}
  end

  local edges = g.edges or {}
  if type(edges) ~= "table" or not vim.tbl_islist(edges) then
    edges = {}
  end

  local children = {}
  local indegree = {}
  for id in pairs(todos) do
    indegree[id] = 0
    children[id] = {}
  end

  for _, e in ipairs(edges) do
    children[e.from] = children[e.from] or {}
    table.insert(children[e.from], e.to)
    indegree[e.to] = (indegree[e.to] or 0) + 1
    if indegree[e.from] == nil then
      indegree[e.from] = 0
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

function View:refresh()
  local graph, err = todo.graph({ dir = self.dir })
  if err then
    api.nvim_buf_set_option(self.buf, "modifiable", true)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, { "Error:", "  " .. err })
    api.nvim_buf_set_option(self.buf, "modifiable", false)
    return
  end

  local roots, children, todos = build_index(graph)
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
end

function View.open(opts)
  opts = opts or {}
  local view = setmetatable({}, View)
  view.dir = opts.dir
  view.buf = create_buf()
  view.win = open_window(view.buf)
  view.expanded = {}
  view.line_to_id = {}

  set_keymaps(view)
  view:refresh()
end

return View
