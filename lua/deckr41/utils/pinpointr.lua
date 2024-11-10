local Logger = require("deckr41.utils.loggr")("Pinpointr")

--- @class Range
--- @field start_pos integer[]
--- @field end_pos integer[]

--- @class Pinpointr
local M = {}

--- @class PinpointrConfig
--- @field hl_ns integer
--- @field mark_chars { top: string, body: string, bottom: string }

--- @type PinpointrConfig
local config = {
  hl_ns = vim.api.nvim_create_namespace("pinpointr_mark"),
  mark_chars = {
    top = "╗",
    body = "║",
    bottom = "╝",
  },
}

--- @class PinpointrState
--- @field win_id integer?
--- @field buf_id integer?
--- @field cursor integer[]?
--- @field range Range?
--- @field filetype string?

--- @type PinpointrState
local state = {
  win_id = nil,
  buf_id = nil,
  cursor = nil,
  range = nil,
  filetype = nil,
}

--- Update the user's whereabouts
--- @param opts? { with_range: boolean }
--- @return PinpointrState
function M.take_snapshot(opts)
  opts = opts or {}
  M.clear_marks()

  local buf_id = vim.api.nvim_get_current_buf()
  local win_id = vim.api.nvim_get_current_win()

  state.win_id = win_id
  state.buf_id = buf_id
  state.cursor = vim.api.nvim_win_get_cursor(win_id)
  state.filetype = vim.bo[buf_id].filetype

  if opts.with_range then state.range = M.mark() end
  return state
end

---Clear visual marks from buffer
function M.clear_marks()
  local buf_id = state.buf_id or vim.api.nvim_get_current_buf()
  if not buf_id then return end

  vim.api.nvim_buf_clear_namespace(buf_id, config.hl_ns, 0, -1)
  state.range = nil
end

--- Mark visual selection with indicators
--- @return Range
function M.mark()
  local buf_id = vim.api.nvim_get_current_buf()
  local start_pos = vim.api.nvim_buf_get_mark(buf_id, "<")
  local end_pos = vim.api.nvim_buf_get_mark(buf_id, ">")

  for line_row = start_pos[1], end_pos[1] do
    local char = ""
    if line_row == start_pos[1] then
      char = config.mark_chars.top
    elseif line_row == end_pos[1] then
      char = config.mark_chars.bottom
    else
      char = config.mark_chars.body
    end

    vim.api.nvim_buf_set_extmark(buf_id, config.hl_ns, line_row - 1, 0, {
      virt_text = { { char, "DiagnosticSignInfo" } },
      virt_text_pos = "right_align",
    })
  end

  return { start_pos = start_pos, end_pos = end_pos }
end

--- Get current state
--- @return PinpointrState
function M.get() return vim.deepcopy(state) end

return M
