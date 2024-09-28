local VimAPI = vim.api

--- @class WindowUtils
local M = {}

--- @param opts ?{ window_id?: integer }
--- @return string
M.get_syntax = function(opts)
  opts = opts or {}
  local window_id = opts.window_id or VimAPI.nvim_get_current_win()
  local buffer_id = vim.api.nvim_win_get_buf(window_id)

  return vim.api.nvim_buf_get_option(buffer_id, "syntax")
end

--- @param opts ?{ window_id?: integer }
--- @return string
M.get_path = function(opts)
  opts = opts or {}
  local window_id = opts.window_id or VimAPI.nvim_get_current_win()
  local buffer_id = vim.api.nvim_win_get_buf(window_id)

  return vim.api.nvim_buf_get_name(buffer_id)
end

--- @param opts ?{ window_id?: integer }
--- @return number
--- @return number
M.get_cursor_position = function(opts)
  opts = opts or {}
  local win_id = opts.window_id or vim.api.nvim_get_current_win()
  local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
  return cursor_pos[1], cursor_pos[2]
end

-- Write a string at the current cursor position in the current window
--- @param opts { input: string, window_id?: integer, should_clear_ahead?: boolean }
--- @return nil
M.write_at_cursor = function(opts)
  local input = opts.input
  local window_id = opts.window_id or VimAPI.nvim_get_current_win()
  local buffer_id = vim.api.nvim_win_get_buf(window_id)
  local should_clear_ahead = opts.should_clear_ahead or false

  -- Get the current cursor position (0 based index)
  local cursor_position = vim.api.nvim_win_get_cursor(window_id)
  -- Decrement row in order to 0 index it required by nvim commands
  -- Decrement col because we want the place before the current char, the
  -- same behaviour as when entering Insert mode.
  local row, col = cursor_position[1] - 1, cursor_position[2]

  -- Split the string into lines
  --- @type string[]
  local lines = vim.split(input, "\n")

  -- Optionally clear text ahead of the cursor
  if should_clear_ahead then
    local current_line =
      vim.api.nvim_buf_get_lines(buffer_id, row, row + 1, false)[1]
    local text_before_cursor = string.sub(current_line, 1, col)
    vim.api.nvim_buf_set_lines(
      buffer_id,
      row,
      row + 1,
      false,
      { text_before_cursor }
    )
  end

  -- Put the lines at the cursor position and follow the cursor to the end of the inserted text
  vim.api.nvim_buf_set_text(buffer_id, row, col, row, col, lines)

  -- Set the cursor to the very end of the inserted text
  local lines_count = #lines
  local last_line_length = #lines[lines_count]
  vim.api.nvim_win_set_cursor(
    window_id,
    { row + lines_count, col + last_line_length }
  )
end

-- Get all the lines of text under the current line.
-- Excluding the current line.
--- @param opts ?{ window_id?: integer }
--- @return string[]
--- @return string
--- @return string[]
M.get_lines_split_by_current = function(opts)
  opts = opts or {}
  local win_id = opts.window_id or vim.api.nvim_get_current_win()
  local buf_id = vim.api.nvim_win_get_buf(win_id)

  local row = vim.api.nvim_win_get_cursor(win_id)[1]

  local lines_before = vim.api.nvim_buf_get_lines(buf_id, 0, row - 1, false)
  local current_line =
    vim.api.nvim_buf_get_lines(buf_id, row - 1, row, false)[1]
  local lines_after = vim.api.nvim_buf_get_lines(buf_id, row, -1, false)

  return lines_before, current_line, lines_after
end

--- @param opts ?{ window_id?: integer }
--- @return string
M.get_text = function(opts)
  opts = opts or {}
  local window_id = opts.window_id or VimAPI.nvim_get_current_win()
  local buffer_id = vim.api.nvim_win_get_buf(window_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  return table.concat(lines, "\n")
end

--- @param opts ?{ window_id?: integer }
--- @return string
M.get_file_content = function(opts)
  opts = opts or {}
  local window_id = opts.window_id or VimAPI.nvim_get_current_win()
  local buffer_id = vim.api.nvim_win_get_buf(window_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  return table.concat(lines, "\n")
end

return M
