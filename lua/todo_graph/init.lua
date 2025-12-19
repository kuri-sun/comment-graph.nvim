local M = {}

local config = {
  bin = nil, -- user override
}

local function trim_trailing(s)
  return (s or ""):gsub("%s+$", "")
end

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

local function run_view(opts)
  opts = opts or {}
  local bin = resolve_bin()
  local dir = opts.dir or vim.loop.cwd() or "."
  local args = { bin, "view", "--dir", dir }
  if opts.roots_only then
    table.insert(args, "--roots-only")
  end
  local ok, out, err = pcall(vim.fn.system, args)
  if not ok then
    return nil, ("failed to run todo-graph: %s"):format(out)
  end
  if vim.v.shell_error ~= 0 then
    return nil, err ~= "" and err or out
  end
  return trim_trailing(out), nil
end

local function parse_view(output)
  local roots = {}
  for line in output:gmatch("[^\r\n]+") do
    line = vim.trim(line)
    if line ~= "" and vim.startswith(line, "- []") then
      local id = line:match("%- %[%] ([^%s]+)")
      if id then
        table.insert(roots, id)
      end
    end
  end
  return roots
end

local function parse_tree(output)
  local root = { id = "ROOT", children = {}, level = 0 }
  local stack = { root }
  for line in output:gmatch("[^\r\n]+") do
    local leading = line:match("^(%s*)")
    local depth = math.floor(#leading / 2)
    local id = line:match("%- %[%] ([^%s]+)")
    if id then
      local node = { id = id, children = {}, line = line, level = depth }
      while #stack > depth + 1 do
        table.remove(stack)
      end
      local parent = stack[#stack] or root
      table.insert(parent.children, node)
      table.insert(stack, node)
    end
  end
  return root.children
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
end

function M.version()
  return run_version()
end

function M.roots(opts)
  local out, err = run_view(vim.tbl_extend("force", { roots_only = true }, opts or {}))
  if err then
    return nil, err
  end
  return parse_view(out), nil
end

function M.tree(opts)
  local out, err = run_view(vim.tbl_extend("force", { roots_only = false }, opts or {}))
  if err then
    return nil, err
  end
  return parse_tree(out), nil
end

-- Status helper: returns counts for statusline or logging.
-- { roots = n, total = m }
function M.status(opts)
  local out, err = run_view(vim.tbl_extend("force", { roots_only = false }, opts or {}))
  if err then
    return nil, err
  end
  local tree = parse_tree(out)
  local total = 0
  local function walk(nodes)
    for _, n in ipairs(nodes) do
      total = total + 1
      if n.children then
        walk(n.children)
      end
    end
  end
  walk(tree or {})
  return { roots = #(tree or {}), total = total }, nil
end

return M
