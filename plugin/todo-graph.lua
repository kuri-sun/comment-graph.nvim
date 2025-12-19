if vim.fn.has("nvim-0.8") == 0 then
  return
end

local view = require("todo_graph.view")
local util = require("todo_graph.util")

vim.api.nvim_create_user_command("TodoGraphView", function(opts)
  view.open({ dir = opts.fargs[1] })
end, {
  desc = "Show TODO graph tree with preview (generate to temp JSON, expand/collapse with <CR>, refresh with r, close with q)",
  nargs = "?",
  complete = "dir",
})
