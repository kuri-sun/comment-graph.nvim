# todo-graph.nvim (work in progress)

Neovim integration for [todo-graph](https://github.com/kuri-sun/todo-graph).

## Status

Early scaffold with basic UI:
- Resolves the `todo-graph` binary (override, then `./node_modules/.bin`, then PATH).
- `:TodoGraphInfo` checks the binary version.
- `:TodoGraphRoots [dir]` opens a small window showing roots (`todo-graph view --roots-only`).
- `:TodoGraphView [dir]` shows a full tree (expand/collapse with `<CR>`, refresh with `r`, close with `q`).

## Installation

Use your plugin manager of choice, e.g. with lazy.nvim:

```lua
{
  "kuri-sun/todo-graph.nvim",
  config = function()
    require("todo_graph").setup({
      -- bin = "/absolute/path/to/todo-graph", -- optional override
    })
  end,
}
```

The plugin will try these locations for the binary (in order):
1. `bin` passed to `setup()`
2. `<cwd>/node_modules/.bin/todo-graph`
3. `todo-graph` on PATH

## Commands

- `:TodoGraphInfo` — runs `todo-graph --version` using the resolver.
- `:TodoGraphRoots [dir]` — roots-only list in a floating window.
- `:TodoGraphView [dir]` — full tree with expand/collapse in a floating window.

More commands and UI are coming next.
