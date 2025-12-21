local M = {}

function M.notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

function M.trim(s)
  return (s or ""):gsub("%s+$", "")
end

return M
