local M = {}

function M.trim(s)
  return (s or ""):gsub("%s+$", "")
end

return M
