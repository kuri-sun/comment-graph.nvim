# todo-graph.nvim (work in progress)

Neovim integration for [todo-graph](https://github.com/kuri-sun/todo-graph).

## Status

Early scaffold with basic UI:
- Resolves the `todo-graph` binary (override, then `./node_modules/.bin`, then PATH).
- `:TodoGraphInfo` checks the binary version.
- `:TodoGraphGenerate [dir]` runs `todo-graph generate`.
- `:TodoGraphCheck [dir]` runs `todo-graph check`.
- `:TodoGraphFix [dir]` runs `todo-graph fix` to add missing `@todo-id`s.
- `:TodoGraphView [dir]` opens a modal tree view with a live preview (runs `generate --format json --output <temp>` to render the tree).

## Installation

Use your plugin manager of choice, e.g. with lazy.nvim:

```lua
{
  "kuri-sun/todo-graph.nvim",
  config = function()
    require("todo_graph").setup({
      -- bin = "/absolute/path/to/todo-graph", -- optional override
      -- keywords = { "TODO", "FIXME", "NOTE" }, -- optional override (defaults to TODO,FIXME,NOTE,WARNING,HACK,CHANGED,REVIEW)
    })
  end,
}
```

The plugin will try these locations for the binary (in order):
1. `bin` passed to `setup()`
2. `<cwd>/node_modules/.bin/todo-graph`
3. `todo-graph` on PATH

## Commands

- `:TodoGraphView [dir]` — modal tree view with right-hand preview (toggle nodes with `<CR>`, refresh with `r`, close with `q`; generates JSON to a temp file). Honors `keywords` from setup or per-command dir override.

More commands and UI are coming next.
