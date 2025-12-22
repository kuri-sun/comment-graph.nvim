local uv = vim.uv or vim.loop

local M = {}

local function is_list(tbl)
  if vim.islist then
    return vim.islist(tbl)
  end
  return vim.tbl_islist(tbl)
end

local function file_exists(path)
  return path and uv.fs_stat(path) ~= nil
end

function M.resolve_path(root, path)
  if not path or path == "" then
    return nil
  end
  if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
    return path
  end
  root = root or "."
  return vim.fn.fnamemodify(root .. "/" .. path, ":p")
end

function M.graph_exists(root)
  local base = vim.fn.fnamemodify(root or ".", ":p")
  return file_exists(base .. "/.comment-graph") or file_exists(base .. "/.comment-graph.json")
end

function M.normalize_nodes(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local nodes = {}
  if is_list(raw) then
    for _, t in ipairs(raw) do
      local id = t and (t.id or t.ID)
      if type(id) == "string" then
        nodes[id] = {
          id = id,
          file = t.file or t.File,
          line = t.line or t.Line,
          label = t.label or t.Label,
        }
      end
    end
  else
    for id, t in pairs(raw) do
      if type(id) == "string" and type(t) == "table" then
        nodes[id] = {
          id = id,
          file = t.file or t.File,
          line = t.line or t.Line,
          label = t.label or t.Label,
        }
      end
    end
  end
  return nodes
end

function M.normalize_edges(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local edges = {}
  for _, e in ipairs(raw) do
    if type(e) == "table" then
      local from = e.from or e.From
      local to = e.to or e.To
      if type(from) == "string" and type(to) == "string" then
        table.insert(edges, { from = from, to = to })
      end
    end
  end
  return edges
end

function M.build_index(g)
  local nodes = M.normalize_nodes(g.nodes or {})
  local edges = M.normalize_edges(g.edges or {})

  local children = {}
  local parents = {}
  local indegree = {}
  for id in pairs(nodes) do
    indegree[id] = 0
    children[id] = {}
    parents[id] = {}
  end

  for _, e in ipairs(edges) do
    local from = e and e.from
    local to = e and e.to
    if type(from) == "string" and type(to) == "string" then
      children[from] = children[from] or {}
      table.insert(children[from], to)
      parents[to] = parents[to] or {}
      table.insert(parents[to], from)
      indegree[to] = (indegree[to] or 0) + 1
      if indegree[from] == nil then
        indegree[from] = 0
      end
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

  return roots, children, parents, nodes
end

return M
