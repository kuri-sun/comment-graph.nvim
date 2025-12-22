local api = vim.api
local graph = require "comment_graph"
local ui = require "comment_graph.ui"
local graph_utils = require "comment_graph.graph_utils"

local View = {}
View.__index = View

local uv = vim.uv or vim.loop
-- Footer hint text shown in the shortcuts row.
local instructions_normal =
  "q: close   Enter: open file   i: search   Space: expand/collapse"
local instructions_move =
  "q: close   Esc: cancel move   Enter: open file   i: search   Space: expand/collapse"

local hl_defined = false

local function get_icons()
  return {
    expanded = "[-]",
    collapsed = "[+]",
    leaf = " - ",
  }
end

local function ensure_highlights()
  if hl_defined then
    return
  end
  -- Use existing groups to stay theme-friendly.
  vim.api.nvim_set_hl(0, "CommentGraphMarker", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CommentGraphId", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "CommentGraphLoc", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "CommentGraphError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "CommentGraphWarn", { link = "DiagnosticWarn", default = true })
  hl_defined = true
end

local function node_label(node_item)
  if not node_item then
    return nil, nil
  end
  local label = node_item.label or node_item.Label
  if label and label ~= "" then
    return label, nil
  end
  local id = node_item.id or node_item.ID
  return id or nil, nil
end

local function node_matches(filter, node_item)
  if not filter or filter == "" or not node_item then
    return true
  end
  local hay =
    table.concat({ node_item.id or "", node_item.label or "", node_item.file or "" }, " \0")
  hay = hay:lower()
  return hay:find(filter:lower(), 1, true) ~= nil
end

local function file_icon(file)
  if not file or file == "" then
    return ""
  end
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok and devicons.get_icon then
    local icon = devicons.get_icon(file, nil, { default = true })
    if icon then
      return icon
    end
  end
  return "[file]"
end

local function set_footer(view, text)
  if not (view.footer_buf and api.nvim_buf_is_valid(view.footer_buf)) then
    return
  end
  local line = (text or instructions_normal):gsub("\n", " ")
  ui.buf_set_option(view.footer_buf, "modifiable", true)
  api.nvim_buf_set_lines(view.footer_buf, 0, -1, false, { line })
  ui.buf_set_option(view.footer_buf, "modifiable", false)
end

-- Compute layout sizes/positions for tree, preview, and footer.
local function layout()
  local total_width = math.max(80, math.floor(vim.o.columns * 0.9))
  local gap = 2
  local usable = total_width - gap
  local tree_width = math.max(35, math.floor(usable * 0.55))
  local preview_width = math.max(30, total_width - tree_width - gap)
  local height = math.max(24, math.floor(vim.o.lines * 0.75))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - (tree_width + gap + preview_width)) / 2)
  return {
    tree_width = tree_width,
    preview_width = preview_width,
    gap = gap,
    height = height,
    row = row,
    col = col,
    total_width = tree_width + gap + preview_width,
  }
end

-- Update preview window title (no-op if window is invalid).
local function set_preview_title(win, title)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  api.nvim_win_set_config(win, {
    title = " " .. title .. " ",
    title_pos = "center",
  })
end

local function set_input_value(view, value)
  if not (view.input_buf and api.nvim_buf_is_valid(view.input_buf)) then
    return
  end
  view.updating_input = true
  ui.buf_set_option(view.input_buf, "modifiable", true)
  local line = value or ""
  api.nvim_buf_set_lines(view.input_buf, 0, -1, false, { line })
  if view.input_win and api.nvim_win_is_valid(view.input_win) then
    pcall(api.nvim_win_set_cursor, view.input_win, { 1, #line })
  end
  view.updating_input = false
end

-- Create tree (left), preview (right), and footer (shortcuts) windows.
local function open_windows(tree_buf, preview_buf, input_buf)
  local dims = layout()
  local input_row = dims.row
  -- Input uses height=1 plus a rounded border (2 rows). Start tree below it.
  local input_total = 1 + 2
  local tree_row = input_row + input_total
  local tree_height = math.max(1, dims.height - input_total)

  local input_win = api.nvim_open_win(input_buf, false, {
    relative = "editor",
    width = dims.tree_width,
    height = 1,
    row = input_row,
    col = dims.col,
    border = "rounded",
    title = " Search ",
    title_pos = "center",
    style = "minimal",
  })
  ui.win_set_option(input_win, "number", false)
  ui.win_set_option(input_win, "relativenumber", false)
  ui.win_set_option(input_win, "signcolumn", "no")
  ui.win_set_option(input_win, "wrap", false)
  ui.win_set_option(input_win, "winfixheight", true)

  local tree_win = api.nvim_open_win(tree_buf, true, {
    relative = "editor",
    width = dims.tree_width,
    height = tree_height,
    row = tree_row,
    col = dims.col,
    border = "rounded",
    title = " Comment Graph ",
    title_pos = "center",
    style = "minimal",
  })
  -- Match picker-style focused line background.
  ui.win_set_option(
    tree_win,
    "winhighlight",
    table.concat({
      "Normal:Normal",
      "NormalNC:Normal",
      "CursorLine:CursorLine",
      "Search:CursorLine",
    }, ",")
  )

  local preview_win = api.nvim_open_win(preview_buf, false, {
    relative = "editor",
    width = dims.preview_width,
    height = dims.height,
    row = input_row,
    col = dims.col + dims.tree_width + dims.gap,
    border = "rounded",
    style = "minimal",
  })

  for _, win in ipairs { tree_win, preview_win } do
    ui.win_set_option(win, "number", false)
    ui.win_set_option(win, "relativenumber", false)
    ui.win_set_option(win, "signcolumn", "no")
    ui.win_set_option(win, "foldcolumn", "0")
    ui.win_set_option(win, "wrap", false)
  end
  ui.win_set_option(tree_win, "cursorline", true)
  ui.win_set_option(preview_win, "cursorline", false)
  ui.win_set_option(preview_win, "number", true)

  set_preview_title(preview_win, "Preview")

  -- footer window for key hints
  local footer_buf = api.nvim_create_buf(false, true)
  ui.buf_set_option(footer_buf, "bufhidden", "wipe")
  ui.buf_set_option(footer_buf, "buftype", "nofile")
  ui.buf_set_option(footer_buf, "swapfile", false)
  ui.buf_set_option(footer_buf, "modifiable", true)
  api.nvim_buf_set_lines(footer_buf, 0, -1, false, { instructions_normal })
  ui.buf_set_option(footer_buf, "modifiable", false)

  local footer_row = tree_row + tree_height + 1
  local footer_win = api.nvim_open_win(footer_buf, false, {
    relative = "editor",
    width = dims.total_width,
    height = 1,
    row = footer_row,
    col = dims.col,
    style = "minimal",
    border = "rounded",
  })
  ui.win_set_option(footer_win, "wrap", false)
  ui.win_set_option(footer_win, "cursorline", false)
  ui.win_set_option(footer_win, "number", false)
  ui.win_set_option(footer_win, "relativenumber", false)
  ui.win_set_option(footer_win, "signcolumn", "no")

  return input_win, tree_win, preview_win, footer_win, footer_buf
end

-- Build roots, adjacency, and parent map for the tree render.
local function build_index(g)
  return graph_utils.build_index {
    nodes = graph_utils.normalize_nodes(g.nodes or {}),
    edges = graph_utils.normalize_edges(g.edges or {}),
  }
end

-- Render tree lines and fill line_index[row]=id for quick lookup.
local function render_tree(
  roots,
  children,
  nodes,
  expanded,
  line_index,
  error_msgs,
  filter,
  allow,
  highlight_term
)
  local lines = {}
  local line_meta = {}
  local icons = get_icons()
  local function append_line(id, depth)
    if allow and not allow[id] then
      return
    end
    local node_item = nodes[id]
    if not node_matches(filter, node_item) then
      return
    end
    local loc = node_item and node_item.file or ""
    if loc ~= "" and node_item and node_item.line then
      loc = string.format("%s:%s", loc, node_item.line)
    end
    local icon = file_icon(node_item and node_item.file or nil)
    local label = node_label(node_item)
    local kids = children[id] or {}
    local has_children = #kids > 0
    if expanded[id] == nil then
      expanded[id] = true
    end
    local marker
    if has_children then
      marker = expanded[id] and icons.expanded or icons.collapsed
    else
      marker = icons.leaf
    end
    local prefix = string.rep("  ", depth)
    local prefix_len = #prefix
    local display = label or id
    local loc_span
    if loc ~= "" then
      local icon_part = icon ~= "" and (icon .. " ") or ""
      display = string.format("%s%s %s", icon_part, loc, display)
      local loc_start = prefix_len + #marker + 1 + #icon_part
      loc_span = { loc_start, loc_start + #loc }
    else
      if icon ~= "" then
        display = string.format("%s %s", icon, display)
      end
    end
    local errors = error_msgs and error_msgs[id] or nil
    local error_text
    local error_group = "CommentGraphError"
    if errors and #errors > 0 then
      local has_unknown = false
      local has_other = false
      for _, e in ipairs(errors) do
        if type(e) == "string" and e:find("unknown dependency", 1, true) then
          has_unknown = true
        else
          has_other = true
        end
      end
      if has_unknown and not has_other then
        error_group = "CommentGraphWarn"
      end
      error_text = "⚠ " .. table.concat(errors, "; ")
    end
    local line
    local error_span
    if error_text then
      line = string.format("%s%s %s   %s", prefix, marker, display, error_text)
      local before_err = prefix .. marker .. " " .. display .. "   "
      local start_idx = #before_err
      local err_len = #error_text
      error_span = { start_idx, start_idx + err_len }
    else
      line = string.format("%s%s %s", prefix, marker, display)
    end
    local match_spans
    if highlight_term and highlight_term ~= "" then
      local ll = line:lower()
      local lt = highlight_term:lower()
      local start = 1
      match_spans = {}
      while true do
        local s, e = ll:find(lt, start, true)
        if not s then
          break
        end
        table.insert(match_spans, { s - 1, e })
        start = e + 1
      end
      if #match_spans == 0 then
        match_spans = nil
      end
    end
    table.insert(lines, line)
    line_index[#lines] = id
    line_meta[#lines] = {
      marker_len = #marker,
      prefix_len = prefix_len,
      error_span = error_span,
      error_group = error_group,
      loc_span = loc_span,
      match_spans = match_spans,
    }
    if has_children and expanded[id] then
      for _, child in ipairs(kids) do
        append_line(child, depth + 1)
      end
    end
  end

  for _, r in ipairs(roots) do
    append_line(r, 0)
  end
  if #lines == 0 then
    lines = { "(no comment nodes found)" }
  end
  return lines, line_meta
end

local function highlight_tree(view, lines)
  ensure_highlights()
  api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
  for idx, _ in ipairs(lines) do
    local meta = view.line_meta and view.line_meta[idx] or nil
    local marker_len = meta and meta.marker_len or 0
    local prefix_len = meta and meta.prefix_len or 0
    local marker_start = prefix_len
    local marker_end = marker_start + marker_len
    if marker_len > 0 then
      api.nvim_buf_add_highlight(
        view.buf,
        view.ns,
        "CommentGraphMarker",
        idx - 1,
        marker_start,
        marker_end
      )
    end
    if meta and meta.error_span then
      local es = meta.error_span
      local group = meta.error_group or "CommentGraphError"
      api.nvim_buf_add_highlight(view.buf, view.ns, group, idx - 1, es[1], es[2])
    end
    if meta and meta.loc_span then
      local ls = meta.loc_span
      api.nvim_buf_add_highlight(view.buf, view.ns, "CommentGraphLoc", idx - 1, ls[1], ls[2])
    end
    if meta and meta.match_spans then
      for _, span in ipairs(meta.match_spans) do
        api.nvim_buf_add_highlight(view.buf, view.ns, "MatchParen", idx - 1, span[1], span[2])
      end
    end
  end
end

function View:update_preview()
  -- Sync the preview buffer with the file for the currently selected tree row.
  -- Clamp the target line to file bounds so stale line numbers still highlight.
  if not (self.preview_buf and api.nvim_buf_is_valid(self.preview_buf)) then
    return
  end

  local row = api.nvim_win_get_cursor(self.win)[1]
  local id = self.line_to_id[row]
  if not (id and self.nodes and self.nodes[id]) then
    ui.buf_set_option(self.preview_buf, "modifiable", true)
    api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, { "(select a node to preview)" })
    ui.buf_set_option(self.preview_buf, "modifiable", false)
    api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
    self.highlight_line = nil
    return
  end

  local node_item = self.nodes[id]
  local path = graph_utils.resolve_path(self.dir, node_item.file)
  local lnum = tonumber(node_item.line) or 1
  self.highlight_line = nil

  set_preview_title(self.preview_win, path and vim.fn.fnamemodify(path, ":~:.") or "(unknown file)")

  local lines
  if path and vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(vim.fn.readfile, path)
    if not ok then
      lines = { "(failed to read file)" }
    else
      lines = data
      local total = #data
      if total > 0 then
        local target = math.max(1, math.min(lnum, total))
        self.highlight_line = target - 1
      end
    end
  else
    lines = { "(file not found)" }
  end

  api.nvim_buf_clear_namespace(self.preview_buf, self.ns, 0, -1)
  ui.buf_set_option(self.preview_buf, "modifiable", true)
  api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, lines)
  ui.buf_set_option(self.preview_buf, "modifiable", false)
  local ft = path and vim.filetype.match { filename = path } or nil
  if ft then
    ui.buf_set_option(self.preview_buf, "filetype", ft)
  end
  if self.highlight_line and self.highlight_line >= 0 then
    api.nvim_buf_add_highlight(self.preview_buf, self.ns, "Search", self.highlight_line, 0, -1)
    -- Scroll the preview window to the highlighted line.
    if self.preview_win and api.nvim_win_is_valid(self.preview_win) then
      api.nvim_win_set_cursor(self.preview_win, { self.highlight_line + 1, 0 })
    end
  end
end

function View:refresh()
  -- Regenerate graph (streamed JSON) and re-render panes.
  local cwd = uv.cwd and uv.cwd() or vim.fn.getcwd()
  self.dir = vim.fn.fnamemodify(self.dir or (cwd or "."), ":p")

  local graph_data, err = graph.graph { dir = self.dir }
  if err then
    ui.buf_set_option(self.buf, "modifiable", true)
    local err_lines = vim.split(err, "\n", { plain = true, trimempty = true })
    for i, line in ipairs(err_lines) do
      err_lines[i] = "  " .. line
    end
    local msg = { "Error:" }
    vim.list_extend(msg, err_lines)
    api.nvim_buf_set_lines(self.buf, 0, -1, false, msg)
    ui.buf_set_option(self.buf, "modifiable", false)
    return
  end

  local roots, children, parents, nodes = build_index(graph_data)
  local filter = self.filter or ""
  local render_filter = filter
  local allow = nil
  local highlight_term = filter
  if filter ~= "" then
    allow = {}
    local function collect_subtree(id)
      if allow[id] then
        return
      end
      allow[id] = true
      for _, child in ipairs(children[id] or {}) do
        collect_subtree(child)
      end
    end
    local function subtree_has_match(id)
      local self_match = node_matches(filter, nodes[id])
      local child_match = false
      for _, child in ipairs(children[id] or {}) do
        if subtree_has_match(child) then
          child_match = true
        end
      end
      if self_match or child_match then
        collect_subtree(id)
        return true
      end
      return false
    end
    for _, r in ipairs(roots) do
      subtree_has_match(r)
    end
    render_filter = "" -- allow governs visibility; render all kept nodes
  end
  local error_msgs = {}
  local rep = graph_data.report or {}
  local function to_list(value)
    if type(value) ~= "table" then
      return {}
    end
    return value
  end
  for _, e in ipairs(to_list(rep.undefinedEdges or rep.UndefinedEdges)) do
    if type(e) == "table" then
      local from = e.from or e.From
      local to = e.to or e.To
      if type(from) == "string" then
        error_msgs[from] = error_msgs[from] or {}
        table.insert(error_msgs[from], "undefined edge")
      end
      if type(to) == "string" then
        error_msgs[to] = error_msgs[to] or {}
        table.insert(error_msgs[to], string.format('unknown dependency "%s"', from or "?"))
      end
    end
  end
  for _, cycle in ipairs(to_list(rep.cycles or rep.Cycles)) do
    if type(cycle) == "table" then
      for _, id in ipairs(cycle) do
        if type(id) == "string" then
          error_msgs[id] = error_msgs[id] or {}
          table.insert(error_msgs[id], "cycle")
        end
      end
    end
  end
  for _, id in ipairs(to_list(rep.isolated or rep.Isolated)) do
    if type(id) == "string" then
      error_msgs[id] = error_msgs[id] or {}
      table.insert(error_msgs[id], "isolated")
    end
  end
  self.nodes = nodes
  self.parents = parents or {}
  self.move_source = nil
  self.line_to_id = {}
  set_footer(self, instructions_normal)
  local tree_line_to_id = {}
  local tree_lines, tree_meta =
    render_tree(
      roots,
      children,
      nodes,
      self.expanded,
      tree_line_to_id,
      error_msgs,
      render_filter,
      allow,
      highlight_term
    )

  ui.buf_set_option(self.buf, "modifiable", true)
  api.nvim_buf_set_lines(self.buf, 0, -1, false, tree_lines)
  ui.buf_set_option(self.buf, "modifiable", false)
  self.line_meta = tree_meta
  self.lines = tree_lines
  self.line_to_id = tree_line_to_id
  highlight_tree(self, tree_lines)
  if filter ~= "" then
    local target
    for idx, id in ipairs(tree_line_to_id) do
      if node_matches(filter, nodes[id]) then
        target = idx
        break
      end
    end
    if target then
      pcall(api.nvim_win_set_cursor, self.win, { target, 0 })
    end
  end
  self:update_preview()
end

function View:toggle_line()
  local row = api.nvim_win_get_cursor(self.win)[1]
  local id = self.line_to_id[row]
  if not id then
    return
  end
  self.expanded[id] = not self.expanded[id]
  self:refresh()
end

local function focus_tree(view)
  -- Set focus to tree window if valid.
  if view.win and api.nvim_win_is_valid(view.win) then
    api.nvim_set_current_win(view.win)
  end
end

local function close_all(view)
  -- Close tree, preview, and footer windows.
  view.move_source = nil
  for _, win in ipairs { view.input_win, view.win, view.preview_win, view.footer_win } do
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end
end

local function open_file_at_cursor(view)
  local row = api.nvim_win_get_cursor(view.win)[1]
  local id = view.line_to_id[row]
  if not (id and view.nodes and view.nodes[id]) then
    return
  end
  local node_item = view.nodes[id]
  local path = graph_utils.resolve_path(view.dir, node_item.file)
  if not path or vim.fn.filereadable(path) ~= 1 then
    vim.notify("Node file not found: " .. (node_item.file or "?"), vim.log.levels.WARN)
    return
  end
  local lnum = tonumber(node_item.line) or 1
  close_all(view)
  vim.cmd(string.format("edit %s", vim.fn.fnameescape(path)))
  pcall(api.nvim_win_set_cursor, 0, { lnum, 0 })
end

local function move_to_target(view)
  local row = api.nvim_win_get_cursor(view.win)[1]
  local target = view.line_to_id[row]
  if not (target and view.move_source and target ~= view.move_source) then
    view.move_source = nil
    set_footer(view, instructions_normal)
    highlight_tree(view, view.lines or {})
    return
  end

  local current_parents = (view.parents and view.parents[view.move_source]) or {}
  local new_parents = {}
  -- drop the first parent (current) to "move"
  for idx, p in ipairs(current_parents) do
    if idx ~= 1 then
      table.insert(new_parents, p)
    end
    if p == target then
      -- already under target; no-op
      view.move_source = nil
      highlight_tree(view, view.lines or {})
      return
    end
  end
  local already = false
  for _, p in ipairs(new_parents) do
    if p == target then
      already = true
      break
    end
  end
  if not already then
    table.insert(new_parents, 1, target)
  end

  local _, err = graph.move {
    dir = view.dir,
    id = view.move_source,
    parent = target,
    parents = new_parents,
  }
  view.move_source = nil
  if err then
    vim.notify("move failed: " .. err, vim.log.levels.ERROR)
    return
  end
  set_footer(view, instructions_normal)
  view:refresh()
end

local function set_keymaps(view)
  -- Wire up core shortcuts across both panes.
  local function map(buf, lhs, fn)
    api.nvim_buf_set_keymap(buf, "n", lhs, "", {
      nowait = true,
      noremap = true,
      callback = fn,
    })
  end
  local function focus_input()
    if view.input_win and api.nvim_win_is_valid(view.input_win) then
      api.nvim_set_current_win(view.input_win)
      set_input_value(view, view.filter or "")
      vim.cmd.startinsert()
    end
  end

  map(view.buf, "q", function()
    close_all(view)
  end)
  map(view.preview_buf, "q", function()
    close_all(view)
  end)

  map(view.buf, "<CR>", function()
    if view.move_source then
      move_to_target(view)
    else
      open_file_at_cursor(view)
    end
  end)

  map(view.buf, "<Space>", function()
    view:toggle_line()
  end)

  map(view.buf, "m", function()
    local row = api.nvim_win_get_cursor(view.win)[1]
    local id = view.line_to_id[row]
    if not id then
      return
    end
    if view.move_source == id then
      view.move_source = nil
      set_footer(view, instructions_normal)
    else
      view.move_source = id
      set_footer(view, instructions_move)
    end
    highlight_tree(view, view.lines or {})
  end)

  map(view.buf, "i", focus_input)

  map(view.buf, "<Esc>", function()
    if view.move_source then
      view.move_source = nil
      set_footer(view, instructions_normal)
      highlight_tree(view, view.lines or {})
    end
  end)

  local group = api.nvim_create_augroup("CommentGraphView" .. view.buf, { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = view.buf,
    callback = function()
      view:update_preview()
    end,
  })

  if view.input_buf then
    local function move_selection(delta)
      if not (view.win and api.nvim_win_is_valid(view.win)) then
        return
      end
      local pos = api.nvim_win_get_cursor(view.win)
      local target = math.max(1, math.min(#(view.lines or {}), pos[1] + delta))
      api.nvim_win_set_cursor(view.win, { target, 0 })
      view:update_preview()
    end
    local function move_input_col(delta)
      if not (view.input_win and api.nvim_win_is_valid(view.input_win)) then
        return
      end
      local pos = api.nvim_win_get_cursor(view.input_win)
      local line = table.concat(api.nvim_buf_get_lines(view.input_buf, 0, 1, false), "")
      local col = math.max(0, math.min(#line, (pos[2] or 0) + delta))
      api.nvim_win_set_cursor(view.input_win, { 1, col })
    end

    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = view.input_buf,
      callback = function()
        if view.updating_input then
          return
        end
        local raw = api.nvim_buf_get_lines(view.input_buf, 0, -1, false)
        local line = table.concat(raw, " ")
        view.filter = line
        view:refresh()
      end,
    })

    api.nvim_buf_set_keymap(view.input_buf, "i", "<Esc>", "", {
      noremap = true,
      callback = function()
        vim.cmd.stopinsert()
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "j", "", {
      noremap = true,
      callback = function()
        move_selection(1)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "k", "", {
      noremap = true,
      callback = function()
        move_selection(-1)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "h", "", {
      noremap = true,
      callback = function()
        move_input_col(-1)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "l", "", {
      noremap = true,
      callback = function()
        move_input_col(1)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "i", "", {
      noremap = true,
      callback = function()
        if view.input_win and api.nvim_win_is_valid(view.input_win) then
          api.nvim_set_current_win(view.input_win)
          vim.cmd.startinsert()
        end
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "<CR>", "", {
      noremap = true,
      callback = function()
        -- focus tree; do not open file automatically
        if view.win and api.nvim_win_is_valid(view.win) then
          api.nvim_set_current_win(view.win)
        end
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "i", "<CR>", "", {
      noremap = true,
      callback = function()
        -- focus tree while keeping current filter
        if view.win and api.nvim_win_is_valid(view.win) then
          api.nvim_set_current_win(view.win)
        end
        vim.cmd.stopinsert()
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "q", "", {
      noremap = true,
      callback = function()
        close_all(view)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "<Space>wq", "", {
      noremap = true,
      callback = function()
        close_all(view)
      end,
    })
    api.nvim_buf_set_keymap(view.input_buf, "n", "<Space>", "", {
      noremap = true,
      callback = function()
        local row = api.nvim_win_get_cursor(view.win)[1]
        local id = view.line_to_id[row]
        if not id then
          return
        end
        view.expanded[id] = not view.expanded[id]
        view:refresh()
      end,
    })
  end
end

function View.open(opts)
  -- Entrypoint used by the user command; sets up windows and initial render.
  opts = opts or {}
  local view = setmetatable({}, View)
  view.dir = opts.dir
  view.filter = ""
  view.updating_input = false
  view.buf = ui.create_buf "comment-graph"
  view.preview_buf = ui.create_buf()
  view.input_buf = ui.create_buf()
  ui.buf_set_option(view.input_buf, "bufhidden", "wipe")
  ui.buf_set_option(view.input_buf, "buftype", "nofile")
  ui.buf_set_option(view.input_buf, "filetype", "comment-graph-filter")
  ui.buf_set_option(view.input_buf, "swapfile", false)
  ui.buf_set_option(view.input_buf, "modifiable", true)
  view.input_win, view.win, view.preview_win, view.footer_win, view.footer_buf =
    open_windows(view.buf, view.preview_buf, view.input_buf)
  view.expanded = {}
  view.line_to_id = {}
  view.line_meta = {}
  view.file_cache = {}
  view.move_source = nil
  view.parents = {}
  view.ns = api.nvim_create_namespace "comment_graph_view"
  view.nodes = {}

  set_keymaps(view)
  set_footer(view, instructions_normal)
  set_input_value(view, "")
  view:refresh()
  if view.win and api.nvim_win_is_valid(view.win) then
    api.nvim_set_current_win(view.win)
  end
end

return View
