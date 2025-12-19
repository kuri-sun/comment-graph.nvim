if vim.fn.has("nvim-0.8") == 0 then
  return
end

local todo = require("todo_graph")
local view = require("todo_graph.view")
local tree = require("todo_graph.tree")
local util = require("todo_graph.util")

vim.api.nvim_create_user_command("TodoGraphInfo", function()
  local out, err = todo.version()
  if err then
    util.notify_err(err)
    return
  end
  out = (out or ""):gsub("%s+$", "")
  vim.notify(out == "" and "todo-graph: ok" or out, vim.log.levels.INFO)
end, { desc = "Show todo-graph version (binary resolver aware)" })

vim.api.nvim_create_user_command("TodoGraphRoots", function(opts)
  view.open_roots({ dir = opts.fargs[1] })
end, {
  desc = "Show TODO roots (roots-only view in a window)",
  nargs = "?",
  complete = "dir",
})

vim.api.nvim_create_user_command("TodoGraphView", function(opts)
  tree.open({ dir = opts.fargs[1] })
end, {
  desc = "Show full TODO graph tree (expand/collapse with <CR>, refresh with r, close with q)",
  nargs = "?",
  complete = "dir",
})
