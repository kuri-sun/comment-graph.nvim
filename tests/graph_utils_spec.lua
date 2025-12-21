local Path = require("plenary.path")
local graph_utils = require("comment_graph.graph_utils")

describe("graph_utils", function()
  it("normalizes node maps", function()
    local raw = {
      a = { file = "a.go", line = 1 },
      b = { File = "b.go", Line = 2 },
    }
    local nodes = graph_utils.normalize_nodes(raw)
    assert.same({
      a = { id = "a", file = "a.go", line = 1 },
      b = { id = "b", file = "b.go", line = 2 },
    }, nodes)
  end)

  it("normalizes node lists", function()
    local raw = {
      { id = "x", file = "x.ts", line = 3 },
      { ID = "y", File = "y.ts", Line = 4 },
    }
    local nodes = graph_utils.normalize_nodes(raw)
    assert.same({
      x = { id = "x", file = "x.ts", line = 3 },
      y = { id = "y", file = "y.ts", line = 4 },
    }, nodes)
  end)

  it("normalizes edges", function()
    local raw = {
      { from = "a", to = "b" },
      { From = "b", To = "c" },
      { from = "invalid" }, -- skipped
    }
    local edges = graph_utils.normalize_edges(raw)
    assert.same({ { from = "a", to = "b" }, { from = "b", to = "c" } }, edges)
  end)

  it("builds roots and adjacency", function()
    local roots, children, parents, nodes = graph_utils.build_index {
      nodes = {
        a = { id = "a" },
        b = { id = "b" },
        c = { id = "c" },
      },
      edges = {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
      },
    }

    assert.same({ "a" }, roots)
    assert.same({ a = { "b" }, b = { "c" }, c = {} }, children)
    assert.same({ a = {}, b = { "a" }, c = { "b" } }, parents)
    assert.truthy(nodes.a)
    assert.truthy(nodes.b)
    assert.truthy(nodes.c)
  end)

  it("detects graph files", function()
    local tmp = Path:new(vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/cgraph-test-XXXXXX"))
    tmp:mkdir({ parents = true, exist_ok = true })
    assert.is_false(graph_utils.graph_exists(tmp:absolute()))
    local graph_path = tmp:joinpath(".comment-graph")
    graph_path:write("version: 1\n", "w")
    assert.is_true(graph_utils.graph_exists(tmp:absolute()))
    graph_path:rm()
    tmp:rm({ recursive = true })
  end)
end)
