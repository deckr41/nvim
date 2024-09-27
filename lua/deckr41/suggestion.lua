local StringUtils = require("deckr41.utils.string") --- @class StringUtils
local WindowUtils = require("deckr41.utils.window") --- @class WindowUtils
local VimAPI = vim.api

--- @class SuggestionModule
--- @field text string
--- @field is_visible boolean
--- @field is_loading boolean
--- @field win_id integer | nil
--- @field buf_id integer | nil
--- @field max_width number Max width of the suggestion window, default is 80
--- @field meta { left: string, right: string }
local M = {
  text = "",
  is_visible = false,

  is_loading = false,
  loading_start_time = nil,
  loading_duration = nil,

  win_id = nil,
  buf_id = nil,

  max_width = 80,
  meta = {
    left = "${STATUS}",
    right = "",
  },
}

--- Builds the meta line for the suggestion window.
--- @return string meta_line: The formatted meta line.
--- @return integer display_width: The display width of the meta line.
local build_meta_bar = function(self)
  local status_icons = { asking = "", writing = "", done = "" }
  local status = self.is_loading and (self.text == "" and "asking" or "writing")
    or "done"

  local meta_left = StringUtils.interpolate(self.meta.left, {
    STATUS = string.format(
      " %s %s",
      status_icons[status],
      status .. (status ~= "done" and " ..." or "")
    ),
  })

  if self.loading_duration ~= nil and not self.is_loading then
    meta_left = meta_left
      .. " in "
      .. math.floor(self.loading_duration * 100) / 100
      .. "s"
  end

  local meta_right = self.meta.right
  local line = "%#deckr41Left#"
    .. meta_left
    .. " %=%#deckr41Right# "
    .. meta_right

  return line,
    vim.fn.strdisplaywidth(meta_left) + vim.fn.strdisplaywidth(meta_right)
end

--- Prepares the content for display.
--- @return table lines: The content lines.
--- @return string filetype: The filetype for syntax highlighting.
local prepare_content = function(self)
  local lines = vim.split(self.text, "\n")
  local filetype = vim.bo.filetype
  if self.text == "" and self:is_finished() then
    -- Loading finished with no content
    lines = { "¯\\_(◔_◔)_/¯" }
    filetype = "text"
  end
  return lines, filetype
end

--- Calculates the dimensions needed for the suggestion window.
--- @param lines string[]
--- @param opts { max_width: number, meta_bar_length: number }
--- @return integer width: The maximum line width.
--- @return integer height: The number of lines.
local calculate_dimensions = function(lines, opts)
  -- First find the max width based on raw content and enforced user max_width
  local width = 0
  for _, line in ipairs(lines) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > width then width = line_width end
  end

  -- Needs to be between the meta_bar width and the user defined max_width
  width = math.max(opts.meta_bar_length + 2, math.min(opts.max_width, width))

  -- Calculate the height taking into account the max width and potential
  -- word wrapping
  local height = 0
  for _, line in ipairs(lines) do
    -- The `#line or 1` is for when the line is empty (0/X = nan -> ceil(nan) = nan)
    local line_length = #line == 0 and 1 or #line
    height = height + math.ceil(line_length / width)
  end

  return math.max(opts.meta_bar_length + 2, width), height
end

--- Ensures the buffer and window are valid or create them.
--- @param opts {win: table, buf: table}
local ensure_buf_and_win = function(self, opts)
  -- Ensure we have a valid buffer
  if not self.buf_id or not VimAPI.nvim_buf_is_valid(self.buf_id) then
    self.buf_id = VimAPI.nvim_create_buf(false, true)
    -- Inherit the same filetype as the buffer we're editing
    VimAPI.nvim_buf_set_option(self.buf_id, "filetype", opts.buf.filetype)
  end

  -- Ensure we have a valid window
  if not self.win_id or not VimAPI.nvim_win_is_valid(self.win_id) then
    self.win_id = VimAPI.nvim_open_win(self.buf_id, false, opts.win)
  else
    VimAPI.nvim_win_set_config(self.win_id, opts.win)
  end
end

--- Redraws the suggestion window.
function M:redraw()
  if not self.is_visible then return end

  local meta_bar, meta_bar_length = build_meta_bar(self)
  local lines, filetype = prepare_content(self)
  local content_width, content_height = calculate_dimensions(lines, {
    meta_bar_length = meta_bar_length,
    max_width = self.max_width,
  })

  ensure_buf_and_win(self, {
    buf = {
      filetype = filetype,
    },
    win = {
      relative = "cursor",
      -- Compensate for the top metabar so the first line is next to the cursor
      row = -1,
      col = 0,
      -- The width should at least fit the meta content
      width = content_width,
      -- +1 for the metabar
      height = content_height + 1,
      style = "minimal",
      focusable = false,
      border = "none",
    },
  })

  VimAPI.nvim_win_set_option(self.win_id, "winbar", meta_bar)
  VimAPI.nvim_buf_set_lines(self.buf_id, 0, -1, false, lines)
end

--- Checks if the suggestion finished loading.
--- Same as checking if `is_visible=true` and `is_loading=false`.
--- @return boolean
function M:is_finished() return self.is_visible and not self.is_loading end

-- Set `is_loading=true` and (re)start the timer.
-- Internaly runs `redraw()`.
function M:start_loading()
  if self.is_loading then return end
  self.is_loading = true
  self.loading_start_time = vim.loop.hrtime()
  self.loading_duration = nil
end

-- Set `is_loading=false` and sets `loading_duration` as the amount of
-- seconds it took since last call of `start_loading`.
-- Internaly runs `redraw()`.
function M:finish_loading()
  if not self.is_loading then return end

  self.is_loading = false
  local loading_end_time = vim.loop.hrtime()
  if self.loading_start_time then
    local duration_ns = loading_end_time - self.loading_start_time
    self.loading_duration = duration_ns / 1e9 -- Convert nanoseconds to seconds
  end

  self.loading_start_time = nil
end

--- Shows the suggestion window.
function M:show()
  if self.is_visible then return end

  self.is_visible = true
  self:redraw()
end

--- Resets the suggestion state and closes the window.
function M:reset()
  if self.win_id and VimAPI.nvim_win_is_valid(self.win_id) then
    VimAPI.nvim_win_close(self.win_id, true)
    self.win_id = nil
  end

  if self.buf_id and VimAPI.nvim_buf_is_valid(self.buf_id) then
    VimAPI.nvim_buf_delete(self.buf_id, { force = true })
    self.buf_id = nil
  end

  self.is_visible = false
  self.text = ""
end

--- Insert the suggestion text at the cursor position.
--- Only works if the the suggestion window is visible, loading is
--- finished and the text itself is not empty.
function M:apply()
  if not self.is_visible or self.is_loading or self.text == "" then return end

  WindowUtils.write_at_cursor({
    input = self.text,
    should_clear_ahead = true,
  })

  self:reset()
end

return M
