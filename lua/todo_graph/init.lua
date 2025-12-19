local M = {}

local util = require("todo_graph.util")

local config = {
  bin = nil, -- user override
}

local function path_exists(path)
  return vim.loop.fs_stat(path) ~= nil
end

local function join(...)
  return table.concat({ ... }, "/")
end

local function resolve_bin()
  if config.bin and path_exists(config.bin) then
    return config.bin
  end

  -- Try project-local node_modules/.bin/todo-graph
  local cwd = vim.loop.cwd() or "."
  local local_bin = join(cwd, "node_modules", ".bin", "todo-graph")
  if path_exists(local_bin) then
    return local_bin
  end

  -- Fallback to PATH
  return "todo-graph"
end

local function run_version()
  local bin = resolve_bin()
  local cmd = { bin, "--version" }
  local ok, out, err = pcall(vim.fn.system, cmd)
  if not ok then
    return nil, ("failed to run todo-graph: %s"):format(out)
  end
  local status = vim.v.shell_error
  if status ~= 0 then
    return nil, err ~= "" and err or out
  end
  return out, nil
end

local function run_cli(subcommand, opts)
  opts = opts or {}
  local bin = resolve_bin()
  local dir = opts.dir or vim.loop.cwd() or "."
  local args = { bin, subcommand, "--dir", dir }
  if opts.args then
    for _, a in ipairs(opts.args) do
      table.insert(args, a)
    end
  end
  local ok, out, err = pcall(vim.fn.system, args)
  if not ok then
    return nil, ("failed to run todo-graph: %s"):format(out)
  end
  if vim.v.shell_error ~= 0 then
    return nil, err ~= "" and err or out
  end
  return util.trim(out), nil
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
end

function M.version()
  return run_version()
end

function M.generate(opts)
  return run_cli("generate", opts)
end

function M.check(opts)
  return run_cli("check", opts)
end

function M.fix(opts)
  return run_cli("fix", opts)
end

return M
