local TextareaUI = require("deckr41.ui.textarea")
local WindowUtils = require("deckr41.utils.window")

--- @class SuggestionUI
local M = {}

--- @alias SuggestionUIStatus "asking"|"writing"|"done"

--- @class SuggestionUIConfig
--- @field value TextareaUIValue? The initial value for the textarea
--- @field filetype string? The filetype for syntax highlighting
--- @field meta string? Only the right side of the meta bar
--- @field max_width integer? The maximum width, borders included
--- @field status SuggestionUIStatus? The current status, displayed in meta bar
--- @field status_icons table<SuggestionUIStatus, string>? Icons for different statuses
--- @field win_opts vim.api.keyset.win_config? Window options for the UI

--- Create a new SuggestionUI instance.
--- @param user_config SuggestionUIConfig?
--- @return SuggestionUIInstance
function M.build(user_config)
  --- @class SuggestionUIInstance
  local instance = {}

  --- @type SuggestionUIConfig
  local config = {
    value = "",
    filetype = "markdown",
    meta = nil,
    max_width = 80,
    status = "asking",
    status_icons = {
      asking = "",
      writing = "",
      done = "",
    },
    win_opts = {
      relative = "cursor",
      row = -1, -- Adjust for meta bar
      col = 0,
      style = "minimal",
      focusable = false,
      border = "rounded",
    },
  }

  -- Merge user options into the default config
  config = vim.tbl_deep_extend("force", config, user_config or {})

  --- @class SuggestionUIState
  local state = {
    loading_start_time = nil, --- @type integer?
    loading_duration = nil, --- @type number?
    textarea_ui = nil, --- @type TextareaUIInstance?
  }

  --- Update the underlying TextareaUI with local meta value.
  local function render_meta()
    local status_suffix = config.status ~= "done" and " ..." or ""
    if config.status == "done" and state.loading_duration ~= nil then
      status_suffix = string.format(" in %.2fs", state.loading_duration)
    end

    local status_text = string.format(
      "%s %s",
      config.status_icons[config.status],
      config.status .. status_suffix
    )

    local meta = {
      left = status_text,
      right = config.meta,
    }

    if state.textarea_ui then state.textarea_ui.set_meta(meta) end
  end

  --- Render the suggestion UI.
  local function render()
    if not state.is_visible then return end
    render_meta()
  end

  --- Show the suggestion UI.
  function instance.show()
    if state.is_visible then return end
    state.is_visible = true

    if not state.textarea_ui then
      state.textarea_ui = TextareaUI.build({
        max_width = config.max_width,
        filetype = config.filetype,
        value = config.value,
        win_opts = config.win_opts,
      })
    end

    state.textarea_ui.show()
    render()
  end

  --- Hide the suggestion UI.
  function instance.hide()
    if not state.is_visible then return end
    state.is_visible = false
    config.status = "asking"
    state.loading_start_time = nil
    state.loading_duration = nil

    if state.textarea_ui then
      state.textarea_ui.hide()
      state.textarea_ui = nil
    end
  end

  --- @param status SuggestionUIStatus
  local function set_status(status)
    if status == "asking" then
      state.loading_start_time = vim.uv.hrtime()
      state.loading_duration = nil
    elseif status == "done" then
      if state.loading_start_time then
        local loading_end_time = vim.uv.hrtime()
        local duration_ns = loading_end_time - state.loading_start_time
        state.loading_duration = duration_ns / 1e9 -- Convert nanoseconds to seconds
      end
      state.loading_start_time = nil
    end

    config.status = status
    render_meta()
  end

  --- Set the meta information.
  --- @param right_side string
  local function set_meta(right_side)
    config.meta = right_side
    render_meta()
  end

  --- @param new_config SuggestionUIConfig
  function instance.update(new_config)
    config = vim.tbl_deep_extend("force", config, new_config)

    if state.textarea_ui then
      state.textarea_ui.update({
        value = new_config.value,
        filetype = new_config.filetype,
      })
    end

    if new_config.meta then set_meta(new_config.meta) end
    if new_config.status then set_status(new_config.status) end

    if state.is_visible then render() end
  end

  --- Append text to the suggestion.
  --- @param text string
  function instance.append_text(text)
    if not state.textarea_ui then return end
    if state.textarea_ui.is_empty() then config.status = "writing" end
    state.textarea_ui.append_text(text)
  end

  --- Check if the suggestion is empty.
  --- @return boolean
  function instance.is_empty()
    if state.textarea_ui then return state.textarea_ui.is_empty() end
    return true
  end

  --- Check if the suggestion has finished loading.
  --- @return boolean
  function instance.is_finished() return config.status == "done" end

  --- Check if the component is visible.
  --- @return boolean
  function instance.is_visible()
    return state.textarea_ui and state.textarea_ui.is_visible() or false
  end

  --- Apply the suggestion by inserting it at the cursor position.
  function instance.apply()
    if not instance.is_finished() or instance.is_empty() then return end

    -- Insert text at cursor position
    WindowUtils.insert_text_at(state.textarea_ui.get_text(), {
      win_id = vim.api.nvim_get_current_win(),
      cursor = vim.api.nvim_win_get_cursor(0),
      range = nil,
      clear_ahead = true,
    })

    instance.hide()
  end

  --- Get the current text content of the suggestion.
  --- @return string
  function instance.get_text()
    return state.textarea_ui and state.textarea_ui.get_text() or ""
  end

  return instance
end

return M
