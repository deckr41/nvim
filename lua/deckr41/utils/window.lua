local Logger = require("deckr41.utils.loggr")("WindowUtils")

--- @class WindowUtils
local M = {}

--- Replace a range in a buffer with the given new lines.
--- @param range string[]
--- @param opts { buf_id: integer, with_lines: string[] }
local replace_range = function(range, opts)
  local start_row = range[1] - 1
  local end_row = range[2] - 1

  -- Replace range with the new lines
  vim.api.nvim_buf_set_lines(
    opts.buf_id,
    start_row,
    end_row + 1,
    false,
    opts.with_lines
  )
end

--- Insert text in a buffer at a cursor position.
--- @param lines string[]
--- @param opts { buf_id: integer, cursor: integer[], clear_ahead: boolean }
local insert_lines = function(lines, opts)
  local row, col = opts.cursor[1] - 1, opts.cursor[2]

  -- Optionally clear text ahead of the cursor
  if opts.clear_ahead then
    local current_line =
      vim.api.nvim_buf_get_lines(opts.buf_id, row, row + 1, false)[1]
    local text_before_cursor = string.sub(current_line, 1, col)
    vim.api.nvim_buf_set_lines(
      opts.buf_id,
      row,
      row + 1,
      false,
      { text_before_cursor }
    )
  end

  -- Put the lines at the cursor position and follow the cursor to the end of the inserted text
  vim.api.nvim_buf_set_text(opts.buf_id, row, col, row, col, lines)
end

--- @class WriteAtCursorOpts
--- @field win_id integer
--- @field cursor integer[]
--- @field range? integer[]
--- @field clear_ahead? boolean
---

--- Write a string at the current cursor position in the current window
--- @param input string
--- @param opts WriteAtCursorOpts
M.insert_text_at = function(input, opts)
  local buf_id = vim.api.nvim_win_get_buf(opts.win_id)
  local lines = vim.split(input, "\n")

  if opts.range then
    replace_range(opts.range, {
      buf_id = buf_id,
      with_lines = lines,
    })
  else
    insert_lines(lines, {
      buf_id = buf_id,
      cursor = opts.cursor or vim.api.nvim_win_get_cursor(opts.win_id),
      clear_ahead = opts.clear_ahead or false,
    })
  end

  -- Set the cursor to the very end of the inserted text
  local lines_count = #lines
  local last_line_length = #lines[lines_count]
  local row, col = opts.cursor[1] - 1, opts.cursor[2]
  vim.api.nvim_win_set_cursor(
    opts.win_id,
    { row + lines_count, col + last_line_length }
  )
end

-- Get the lines before & after the current line and
-- text before & after the cursor on the current line.
--- @param opts { win_id: integer, cursor: integer[] }
--- @return string[]: Lines before row position
--- @return string[]: Lines after row position
--- @return string: Text before col position on the current line
--- @return string: Text after col position on the current line
M.split_lines_by_cursor = function(opts)
  local buf_id = vim.api.nvim_win_get_buf(opts.win_id)
  local row = opts.cursor[1]
  local col = opts.cursor[2]

  local lines_before = vim.api.nvim_buf_get_lines(buf_id, 0, row - 1, false)
  local lines_after = vim.api.nvim_buf_get_lines(buf_id, row, -1, false)

  local current_line =
    vim.api.nvim_buf_get_lines(buf_id, row - 1, row, false)[1]
  local text_before = string.sub(current_line, 1, col)
  local text_after = string.sub(current_line, col + 1)

  return lines_before, lines_after, text_before, text_after
end

--- @param opts ?{ win_id?: integer }
--- @return string
M.get_text = function(opts)
  opts = opts or {}
  local win_id = opts.win_id or vim.api.nvim_get_current_win()
  local buf_id = vim.api.nvim_win_get_buf(win_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  return table.concat(lines, "\n")
end

--- @param opts ?{ win_id?: integer }
--- @return string
M.get_file_content = function(opts)
  opts = opts or {}
  local win_id = opts.win_id or vim.api.nvim_get_current_win()
  local buf_id = vim.api.nvim_win_get_buf(win_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  return table.concat(lines, "\n")
end

--- @param buf_id integer
--- @param opts { range: integer[] }
--- @return string
M.get_selected_text = function(buf_id, opts)
  local start_pos = opts.range[1]
  local end_pos = opts.range[2]
  local lines =
    vim.api.nvim_buf_get_text(buf_id, start_pos - 1, 0, end_pos, 0, {})

  return table.concat(lines, "\n")
end

--- @type table<string, fun(buf_id:integer, opts: { range?: integer[], cursor: integer[] }): string>
local metadata_getters = {
  FILE_PATH = function(buf_id) return vim.api.nvim_buf_get_name(buf_id) end,
  FILE_SYNTAX = function(buf_id)
    return vim.api.nvim_get_option_value("filetype", { buf = buf_id })
  end,
  LINES_BEFORE_CURRENT = function(buf_id, opts)
    local row = opts.cursor[1]
    local lines_before = vim.api.nvim_buf_get_lines(buf_id, 0, row - 1, false)
    return table.concat(lines_before, "\n")
  end,
  LINES_AFTER_CURRENT = function(buf_id, opts)
    local row = opts.cursor[1]
    local lines_after = vim.api.nvim_buf_get_lines(buf_id, row, -1, false)
    return table.concat(lines_after, "\n")
  end,
  TEXT_BEFORE_CURSOR = function(buf_id, opts)
    local row = opts.cursor[1]
    local col = opts.cursor[2]
    local current_line =
      vim.api.nvim_buf_get_lines(buf_id, row - 1, row, false)[1]

    return string.sub(current_line, 1, col)
  end,
  TEXT_AFTER_CURSOR = function(buf_id, opts)
    local row = opts.cursor[1]
    local col = opts.cursor[2]
    local current_line =
      vim.api.nvim_buf_get_lines(buf_id, row - 1, row, false)[1]
    return string.sub(current_line, col + 1)
  end,
  TEXT = function(buf_id, opts)
    local lines = {}

    if opts.range then
      local start_pos = opts.range[1]
      local end_pos = opts.range[2]
      lines =
        vim.api.nvim_buf_get_text(buf_id, start_pos - 1, 0, end_pos, 0, {})
    else
      lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    end

    return table.concat(lines, "\n")
  end,
}

--- @param names string[]
--- @param opts { win_id: integer, range?: integer[], cursor: integer[]}
--- @return table<string, string>
M.get_metadata = function(names, opts)
  local buf_id = vim.api.nvim_win_get_buf(opts.win_id)
  local metadata_dict = {}

  for _, var_name in ipairs(names) do
    local getter = metadata_getters[var_name]
    if getter then
      metadata_dict[var_name] =
        getter(buf_id, { range = opts.range, cursor = opts.cursor })
    end
  end

  return metadata_dict
end

return M
