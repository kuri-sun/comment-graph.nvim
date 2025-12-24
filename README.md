# comment-graph.nvim

Neovim integration for [comment-graph](https://github.com/kuri-sun/comment-graph).

![comment-graph.nvim preview](assets/preview.gif)

## Installation

Use your plugin manager of choice, e.g. with lazy.nvim:

```lua
{
  "kuri-sun/comment-graph.nvim",
}
```

## Commands

- `:CommentGraphView [dir]` — modal tree view with right-hand preview.

## Configuration

You can tune visuals and behavior via `setup`:

```lua
require("comment_graph").setup({
  bin = "/absolute/path/to/comment-graph", -- optional; falls back to node_modules/.bin or PATH
  icons = { expanded = "[-]", collapsed = "[+]", leaf = " - " },
  layout = {
    width_ratio = 0.9,    -- overall width vs Neovim columns
    height_ratio = 0.75,  -- overall height vs Neovim lines
    tree_ratio = 0.55,    -- portion of width for tree
    min_total_width = 80,
    min_tree_width = 35,
    min_preview_width = 30,
    gap = 2,
  },
  preview = {
    number = true,        -- show line numbers in preview
    cursorline = false,
    title = "Preview",
  },
  filter = {
    initial = "",         -- pre-fill search input
    case_sensitive = false,
  },
  -- Optional: override default keymaps by providing a function.
  -- ctx.default_map(buf, lhs, callback) is available for convenience.
  -- function(view, ctx)
  --   -- Tree buffer (view.buf)
  --   ctx.default_map(view.buf, "q", function() ctx.close_all(view) end)
  --   ctx.default_map(view.buf, "<CR>", function() vim.notify("open file") end)
  --   ctx.default_map(view.buf, "<Space>", function() vim.notify("toggle expand") end)
  --   ctx.default_map(view.buf, "i", function() ctx.focus_input(view) end)
  --   -- Search input (view.input_buf)
  --   ctx.default_map(view.input_buf, "q", function() ctx.close_all(view) end)
  --   ctx.default_map(view.input_buf, "<Space>wq", function() ctx.close_all(view) end)
  --   ctx.default_map(view.input_buf, "<CR>", function()
  --     if view.win and vim.api.nvim_win_is_valid(view.win) then
  --       vim.api.nvim_set_current_win(view.win)
  --     end
  --   end)
  --   -- Preview buffer (view.preview_buf)
  --   ctx.default_map(view.preview_buf, "q", function() ctx.close_all(view) end)
  --   ctx.default_map(view.preview_buf, "<Space>wq", function() ctx.close_all(view) end)
  -- end,
})
```

Default keymaps:

- `<Space>wq` or `q` to close (tree, search input, preview).
- `<CR>` to open file in the tree-view; `<CR>` in search returns focus to tree.
- `<Space>` to expand/collapse.
- `i` to focus search.
