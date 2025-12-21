if vim.fn.has("nvim-0.8") == 0 then
  return
end

local view = require("comment_graph.view")
local util = require("comment_graph.util")

vim.api.nvim_create_user_command("CommentGraphView", function(opts)
  view.open({ dir = opts.fargs[1] })
end, {
  desc = "Show comment graph tree with preview (streams JSON via `comment-graph graph`; expand/collapse with <CR>, refresh with r, close with q)",
  nargs = "?",
  complete = "dir",
})

-- Legacy alias for older configs.
vim.api.nvim_create_user_command("TodoGraphView", function(opts)
  view.open({ dir = opts.fargs[1] })
end, {
  desc = "[deprecated] Use :CommentGraphView",
  nargs = "?",
  complete = "dir",
})
