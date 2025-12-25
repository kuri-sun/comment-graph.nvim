local M = {}

local util = require "comment_graph.util"

local config = {
  bin = nil, -- user override
  icons = {
    expanded = "[-]",
    collapsed = "[+]",
    leaf = " - ",
  },
  layout = {
    width_ratio = 0.9,
    height_ratio = 0.75,
    min_total_width = 80,
    min_tree_width = 35,
    min_preview_width = 30,
    gap = 2,
    tree_ratio = 0.55,
  },
  preview = {
    number = true,
    cursorline = false,
    title = "Preview",
  },
  filter = {
    case_sensitive = false,
    initial = "",
  },
  -- keymaps can be overridden with a function(view, ctx) that calls ctx.default_map(...)
  keymaps = nil,
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

  -- Try project-local node_modules/.bin/comment-graph
  local cwd = vim.loop.cwd() or "."
  local local_bin = join(cwd, "node_modules", ".bin", "comment-graph")
  if path_exists(local_bin) then
    return local_bin
  end

  -- Fallback to PATH
  return "comment-graph"
end

local function ensure_bin()
  local bin = resolve_bin()
  -- vim.fn.executable works for both absolute paths and PATH lookups.
  local ok = (vim.fn.executable(bin) == 1)
  if not ok then
    local msg = table.concat({
      "comment-graph binary not found or not executable.",
      "Install the CLI (e.g., npm i -D @comment-graph/comment-graph, or use a platform package),",
      "or set require('comment_graph').setup{ bin = '/absolute/path/to/comment-graph' }.",
    }, " ")
    return nil, msg
  end
  return bin, nil
end

local function run_version()
  local bin, err = ensure_bin()
  if not bin then
    return nil, err
  end
  local cmd = { bin, "--version" }
  local ok, out, sys_err = pcall(vim.fn.system, cmd)
  if not ok then
    return nil, ("failed to run comment-graph: %s"):format(out)
  end
  local status = vim.v.shell_error
  if status ~= 0 then
    return nil, sys_err ~= "" and sys_err or out
  end
  return out, nil
end

local function run_cli(subcommand, opts)
  opts = opts or {}
  local bin, err = ensure_bin()
  if not bin then
    return nil, err
  end
  local dir = opts.dir or vim.loop.cwd() or "."
  local args = { bin, subcommand, "--dir", dir }
  if opts.args then
    for _, a in ipairs(opts.args) do
      table.insert(args, a)
    end
  end
  local ok, out, sys_err = pcall(vim.fn.system, args)
  if not ok then
    return nil, ("failed to run comment-graph: %s"):format(out)
  end
  if vim.v.shell_error ~= 0 then
    return nil, sys_err ~= "" and sys_err or out
  end
  return util.trim(out), nil
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
end

function M.get_config()
  return config
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

-- Generate a fresh graph as JSON streamed to stdout and return decoded table.
-- Does not write any files in the user's repo; includes validation report.
function M.graph(opts)
  opts = opts or {}
  local dir = opts.dir
  local args = { "--allow-errors" }
  local out, err = run_cli("graph", {
    dir = dir,
    args = args,
  })
  if err then
    return nil, err
  end
  local ok, decoded = pcall(vim.json.decode, out)
  if not ok then
    return nil, "failed to decode comment-graph output"
  end
  if type(decoded) ~= "table" then
    return nil, "unexpected comment-graph output"
  end
  local graph = decoded.graph or decoded
  graph.report = decoded.report or graph.report
  return graph, nil
end

return M
