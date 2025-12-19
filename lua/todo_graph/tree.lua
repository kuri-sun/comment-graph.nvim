local api = vim.api
local todo = require("todo_graph")

local Tree = {}
Tree.__index = Tree

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "filetype", "todo-graph")
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  return buf
end

local function open_window(buf, title)
  local width = math.floor(vim.o.columns * 0.4)
  local height = math.floor(vim.o.lines * 0.5)
  local row = math.floor((vim.o.lines - height) / 3)
  local col = math.floor((vim.o.columns - width) / 2)

  return api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = title or "TODO Graph",
  })
end

local function render(nodes, expanded, prefix)
  prefix = prefix or ""
  local lines = {}
  for _, n in ipairs(nodes) {
    local has_children = n.children and #n.children > 0
    local marker = has_children and (expanded[n.id] and "" or "") or " "
    table.insert(lines, ("%s%s %s"):format(prefix, marker, n.id))
    if has_children and expanded[n.id] then
      local child_lines = render(n.children, expanded, prefix .. "  ")
      vim.list_extend(lines, child_lines)
    end
  end
  return lines
end

function Tree:new(opts)
  local t = setmetatable({}, self)
  t.dir = opts.dir
  t.buf = create_buf()
  t.win = open_window(t.buf, "TODO Graph (tree)")
  t.expanded = {}
  api.nvim_buf_set_keymap(t.buf, "n", "q", "", {
    nowait = true,
    noremap = true,
    callback = function()
      if api.nvim_win_is_valid(t.win) then
        api.nvim_win_close(t.win, true)
      end
    end,
  })
  api.nvim_buf_set_keymap(t.buf, "n", "r", "", {
    nowait = true,
    noremap = true,
    callback = function()
      t:refresh()
    end,
  })
  api.nvim_buf_set_keymap(t.buf, "n", "<CR>", "", {
    nowait = true,
    noremap = true,
    callback = function()
      t:toggle_line()
    end,
  })
  return t
end

function Tree:refresh()
  local nodes, err = todo.tree({ dir = self.dir })
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  nodes = nodes or {}
  local lines = render(nodes, self.expanded, "")
  if #lines == 0 then
    lines = { "(no todos)" }
  end
  api.nvim_buf_set_option(self.buf, "modifiable", true)
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_buf_set_option(self.buf, "modifiable", false)
end

function Tree:toggle_line()
  local row = api.nvim_win_get_cursor(self.win)[1]
  local line = api.nvim_buf_get_lines(self.buf, row - 1, row, false)[1] or ""
  local id = line:match("[-]%s+([%w%-%_%.]+)")
  if not id then
    return
  end
  if self.expanded[id] then
    self.expanded[id] = false
  else
    self.expanded[id] = true
  end
  self:refresh()
end

return {
  open = function(opts)
    local t = Tree:new(opts or {})
    t:refresh()
  end,
}
