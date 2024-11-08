local Logger = require("deckr41.utils.loggr")("Pinpointr")

--- @class Pinpointr
local M = {}

--- @class PinpointrState User's current position in the file
local state = {
  win_id = nil, --- @type integer?
  cursor = nil, --- @type integer[]?
  range = nil, --- @type { start_pos: integer[], end_pos: integer[] }?
  filetype = nil, --- @type string?
}

--- Update the user's whereabouts
--- @param opts { with_range: boolean }?
--- @return PinpointrState
M.take_snapshot = function(opts)
  opts = opts or {}
  local buf_id = vim.api.nvim_get_current_buf()
  local win_id = vim.api.nvim_get_current_win()

  state.win_id = win_id
  state.cursor = vim.api.nvim_win_get_cursor(win_id)
  state.filetype = vim.bo[buf_id].filetype

  state.range = nil
  if opts.with_range then
    state.range = {
      start_pos = vim.api.nvim_buf_get_mark(buf_id, "<"),
      end_pos = vim.api.nvim_buf_get_mark(buf_id, ">"),
    }
  end

  return state
end

M.get = function() return vim.deepcopy(state) end

return M
