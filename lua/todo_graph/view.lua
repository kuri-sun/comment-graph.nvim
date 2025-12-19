local api = vim.api
local todo = require("todo_graph")
local util = require("todo_graph.util")

local View = {}

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "filetype", "todo-graph")
  return buf
end

local function open_window(buf, title)
  local width = math.floor(vim.o.columns * 0.3)
  local height = math.floor(vim.o.lines * 0.4)
  local row = math.floor((vim.o.lines - height) / 3)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = title or "TODO Graph",
  })
  return win
end

local function set_lines(buf, lines)
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_buf_set_option(buf, "modifiable", false)
end

local function map_close(buf, win)
  api.nvim_buf_set_keymap(buf, "n", "q", "", {
    nowait = true,
    noremap = true,
    callback = function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end,
  })
end

local M = {}

function M.open_roots(opts)
  opts = opts or {}
  local roots, err = todo.roots({ dir = opts.dir })
  if err then
    util.notify_err(err)
    return
  end
  local buf = create_buf()
  local win = open_window(buf, "TODO Graph (roots)")
  map_close(buf, win)
  roots = roots or {}
  table.sort(roots)
  local lines = { "Roots:" }
  for _, id in ipairs(roots) do
    table.insert(lines, "  - " .. id)
  end
  if #roots == 0 then
    table.insert(lines, "  (none)")
  end
  set_lines(buf, lines)
end

return M
