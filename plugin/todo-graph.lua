if vim.fn.has("nvim-0.8") == 0 then
  return
end

local todo = require("todo_graph")
local view = require("todo_graph.view")
local util = require("todo_graph.util")

local function run_and_notify(label, fn, dir)
  local out, err = fn({ dir = dir })
  if err then
    util.notify_err(err)
    return
  end
  out = util.trim(out or "")
  local msg = out ~= "" and out or ("todo-graph " .. label .. " ok")
  vim.notify(msg, vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("TodoGraphInfo", function()
  local out, err = todo.version()
  if err then
    util.notify_err(err)
    return
  end
  out = (out or ""):gsub("%s+$", "")
  vim.notify(out == "" and "todo-graph: ok" or out, vim.log.levels.INFO)
end, { desc = "Show todo-graph version (binary resolver aware)" })

vim.api.nvim_create_user_command("TodoGraphGenerate", function(opts)
  run_and_notify("generate", todo.generate, opts.fargs[1])
end, { desc = "Run `todo-graph generate` for the current project (optional dir override)", nargs = "?", complete = "dir" })

vim.api.nvim_create_user_command("TodoGraphCheck", function(opts)
  run_and_notify("check", todo.check, opts.fargs[1])
end, { desc = "Run `todo-graph check` for the current project (optional dir override)", nargs = "?", complete = "dir" })

vim.api.nvim_create_user_command("TodoGraphFix", function(opts)
  run_and_notify("fix", todo.fix, opts.fargs[1])
end, { desc = "Run `todo-graph fix` to fill missing @todo-id placeholders (optional dir override)", nargs = "?", complete = "dir" })

vim.api.nvim_create_user_command("TodoGraphView", function(opts)
  view.open({ dir = opts.fargs[1] })
end, {
  desc = "Show TODO graph tree (generate to temp JSON, expand/collapse with <CR>, refresh with r, close with q)",
  nargs = "?",
  complete = "dir",
})
