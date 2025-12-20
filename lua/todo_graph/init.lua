local M = {}

local util = require("todo_graph.util")

local config = {
	bin = nil, -- user override
	keywords = nil, -- optional list or comma-separated string
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

local function run_cli(subcommand, opts)
	opts = opts or {}
	local bin = resolve_bin()
	local dir = opts.dir or vim.loop.cwd() or "."
	local args = { bin, subcommand, "--dir", dir }
	local keywords = opts.keywords or config.keywords
	if type(keywords) == "string" then
		keywords = vim.split(keywords, ",", { trimempty = true, plain = true })
	end
	if keywords and #keywords > 0 then
		table.insert(args, "--keywords")
		table.insert(args, table.concat(keywords, ","))
	end
	if opts.args then
		for _, a in ipairs(opts.args) do
			table.insert(args, a)
		end
	end
	local ok, out, err = pcall(vim.fn.system, args)
	if not ok then
		return nil, ("failed to run todo-graph: %s"):format(out)
	end
	if vim.v.shell_error ~= 0 then
		return nil, err ~= "" and err or out
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

function M.fix(opts)
	return run_cli("fix", opts)
end

-- Move a TODO under a new parent by detaching existing deps and setting the target.
function M.move(opts)
	opts = opts or {}
	local id = opts.id
	local parent = opts.parent
	if not id or not parent then
		return nil, "id and parent are required"
	end
	local dir = opts.dir
	-- detach all current parents
	local _, err = run_cli("deps", {
		dir = dir,
		args = { "detach", "--id", id, "--all" },
	})
	if err then
		return nil, err
	end
	-- set new parent
	local _, err2 = run_cli("deps", {
		dir = dir,
		args = { "set", "--id", id, "--depends-on", parent },
	})
	if err2 then
		return nil, err2
	end
	return true, nil
end

-- Generate a fresh graph as JSON (written to a temp file) and return decoded table.
-- Does not mutate the user's .todo-graph because output is redirected to a temp path.
function M.graph(opts)
	opts = opts or {}
	local dir = opts.dir
	local tmp = vim.fn.tempname() .. ".json"
	local _, err = run_cli("generate", {
		dir = dir,
		args = { "--format", "json", "--output", tmp },
	})
	if err then
		return nil, err
	end
	local data = vim.fn.readfile(tmp)
	vim.fn.delete(tmp)
	local ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	if not ok then
		return nil, "failed to decode todo-graph output"
	end
	if type(decoded) ~= "table" then
		return nil, "unexpected todo-graph output"
	end
	return decoded, nil
end

return M
