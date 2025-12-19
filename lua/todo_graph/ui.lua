local api = vim.api

local M = {}

-- Tiny shims to support both nvim_set_option_value and older APIs.
local function set_option(target, name, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(name, value, target)
  end
  if target.buf then
    return api.nvim_buf_set_option(target.buf, name, value)
  end
  if target.win then
    return api.nvim_win_set_option(target.win, name, value)
  end
end

function M.buf_set_option(buf, name, value)
  return set_option({ buf = buf }, name, value)
end

function M.win_set_option(win, name, value)
  return set_option({ win = win }, name, value)
end

-- Scratch buffer with sane defaults for floating UI.
function M.create_buf(filetype)
  local buf = api.nvim_create_buf(false, true)
  M.buf_set_option(buf, "bufhidden", "wipe")
  M.buf_set_option(buf, "buftype", "nofile")
  M.buf_set_option(buf, "swapfile", false)
  M.buf_set_option(buf, "modifiable", false)
  if filetype then
    M.buf_set_option(buf, "filetype", filetype)
  end
  return buf
end

return M
