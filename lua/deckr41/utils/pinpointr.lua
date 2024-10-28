--- @class Pinpointr
local M = {}

--- @class PinpointrState User's current state in the file
local state = {
  win_id = nil, --- @type integer?
  cursor = nil, --- @type integer[]?
  range = nil, --- @type integer[]?
  filetype = nil, --- @type string?
}

--- Update the user's whereabouts
--- @param opts { range?: integer[] }?
--- @return PinpointrState
M.take_snapshot = function(opts)
  opts = opts or {}
  local buf_id = vim.api.nvim_get_current_buf()
  local win_id = vim.api.nvim_get_current_win()

  state.win_id = win_id
  state.cursor = vim.api.nvim_win_get_cursor(win_id)
  state.range = opts.range
  state.filetype = vim.bo[buf_id].filetype

  return state
end

M.get = function() return vim.deepcopy(state) end

return M
