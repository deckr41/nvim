local Logger = require("deckr41.utils.loggr")("WindowUtils")

local MAX_LINE_LENGTH = 2 ^ 31 - 1

--- @class WindowUtils
local M = {}

--- Replace a range in a buffer with the given new lines.
--- @param range { start_pos: integer[], end_pos: integer[] }
--- @param opts { buf_id: integer, with_lines: string[] }
local replace_range = function(range, opts)
  local start_row = range.start_pos[1] - 1
  local end_row = range.end_pos[1] - 1

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
--- @field range? { start_pos: integer[], end_pos: integer[] }
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

--- @param buf_id integer
--- @return string
M.get_buffer_content = function(buf_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  return table.concat(lines, "\n")
end

--- @param buf_id integer
--- @param range { start_pos: integer[], end_pos: integer[]  }
--- @return string
M.get_text_by_range = function(buf_id, range)
  -- Adjust row indices: Neovim uses 0-based indexing, so subtract 1 from row numbers
  local start_row_zero_indexed = range.start_pos[1] - 1
  local end_row_zero_indexed = range.end_pos[1] - 1

  local lines = vim.api.nvim_buf_get_text(
    buf_id,
    start_row_zero_indexed,
    range.start_pos[2],
    end_row_zero_indexed,
    -- extends the end column to include the last character under the cursor
    range.end_pos[2] + 1,
    {}
  )

  return table.concat(lines, "\n")
end

--- @class MetadataGetterOptions
--- @field cursor integer[]
--- @field range { start_pos: integer[], end_pos: integer[] }

--- @type table<string, fun(buf_id:integer, opts: MetadataGetterOptions): string>
local META_GETTERS = {
  FILE_PATH = vim.api.nvim_buf_get_name,
  FILE_CONTENT = M.get_buffer_content,
  FILE_SYNTAX = function(buf_id)
    return vim.api.nvim_get_option_value("filetype", { buf = buf_id })
  end,
  LINES_BEFORE_CURRENT = function(buf_id, opts)
    return M.get_text_by_range(buf_id, {
      start_pos = { 1, 0 },
      end_pos = { opts.cursor[1] - 1, MAX_LINE_LENGTH },
    })
  end,
  LINES_AFTER_CURRENT = function(buf_id, opts)
    local max_lines = vim.api.nvim_buf_line_count(buf_id)

    return M.get_text_by_range(buf_id, {
      start_pos = { math.min(max_lines, opts.cursor[1] + 1), 0 },
      end_pos = { 0, MAX_LINE_LENGTH },
    })
  end,
  TEXT_BEFORE_CURSOR = function(buf_id, opts)
    return M.get_text_by_range(buf_id, {
      start_pos = { opts.cursor[1], 0 },
      end_pos = opts.cursor,
    })
  end,
  TEXT_AFTER_CURSOR = function(buf_id, opts)
    return M.get_text_by_range(buf_id, {
      start_pos = opts.cursor,
      end_pos = { opts.cursor[1], MAX_LINE_LENGTH },
    })
  end,
  TEXT = function(buf_id, opts)
    if opts.range then return M.get_text_by_range(buf_id, opts.range) end

    return M.get_buffer_content(buf_id)
  end,
}

--- @param names string[]
--- @param opts { win_id: integer, range?: integer[], cursor: integer[]}
--- @return table<string, string>
M.get_metadata = function(names, opts)
  local buf_id = vim.api.nvim_win_get_buf(opts.win_id)
  local metadata_dict = {}

  for _, var_name in ipairs(names) do
    local getter = META_GETTERS[var_name]
    if getter then
      metadata_dict[var_name] =
        getter(buf_id, { range = opts.range, cursor = opts.cursor })
    end
  end

  return metadata_dict
end

return M
