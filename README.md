# comment-graph.nvim (work in progress)

Neovim integration for [comment-graph](https://github.com/kuri-sun/comment-graph).

## Installation

Use your plugin manager of choice, e.g. with lazy.nvim:

```lua
{
  "kuri-sun/comment-graph.nvim",
  config = function()
    require("comment_graph").setup({
      -- bin = "/absolute/path/to/comment-graph", -- optional override
    })
  end,
}
```

The plugin will try these locations for the binary (in order):

1. `bin` passed to `setup()`
2. `<cwd>/node_modules/.bin/comment-graph`
3. `comment-graph` on PATH

## Commands

- `:CommentGraphView [dir]` — modal tree view with right-hand preview (toggle nodes with `<CR>`, refresh with `r`, close with `q`; streams JSON without writing repo files).

More commands and UI are coming next.
