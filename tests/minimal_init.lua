-- Minimal Neovim init for running plugin tests headlessly.
-- Adds the plugin to runtimepath and ensures plenary is available.

vim.cmd("set rtp^=" .. vim.fn.getcwd())

local plenary_paths = {
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/opt/plenary.nvim",
  os.getenv("PLENARY_PATH"),
}

for _, p in ipairs(plenary_paths) do
  if p and vim.fn.isdirectory(p) == 1 then
    vim.opt.rtp:append(p)
  end
end

local ok, _ = pcall(require, "plenary")
if not ok then
  error("plenary.nvim is required for tests; set PLENARY_PATH or install it in your runtimepath")
end

vim.o.swapfile = false
