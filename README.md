# todo-graph.nvim (work in progress)

Neovim integration for [todo-graph](https://github.com/kuri-sun/todo-graph).

## Status

Early scaffold with basic UI:
- Resolves the `todo-graph` binary (override, then `./node_modules/.bin`, then PATH).
- `:TodoGraphInfo` checks the binary version.
- `:TodoGraphGenerate [dir]` runs `todo-graph generate`.
- `:TodoGraphCheck [dir]` runs `todo-graph check`.
- `:TodoGraphFix [dir]` runs `todo-graph fix` to add missing `@todo-id`s.

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
- `:TodoGraphGenerate [dir]` — run `todo-graph generate` (optional dir override).
- `:TodoGraphCheck [dir]` — run `todo-graph check` (optional dir override).
- `:TodoGraphFix [dir]` — run `todo-graph fix` (optional dir override).

More commands and UI are coming next.
