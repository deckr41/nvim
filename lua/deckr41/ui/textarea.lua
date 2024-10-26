local ArrayUtils = require("deckr41.utils.array")
local Logger = require("deckr41.utils.loggr")("TextareaUI")
local NVimUtils = require("deckr41.utils.nvim")
local StringUtils = require("deckr41.utils.string")
local TableUtils = require("deckr41.utils.table")

--- @class TextareaUI
local M = {}

--- @class TextareaUITab
--- @field id string Unique identifier for the tab
--- @field label string? Display label for the tab (defaults to id if not provided)
--- @field value string|fun():string The content of the tab, or a function that returns the content
--- @field _resolved_value string? Cached content after resolving `value` if it's a function
--- @field filetype string? The filetype for syntax highlighting in the tab

--- @alias TextareaUIValue string|(fun():string)|TextareaUITab[]

--- @class TextareaUIConfig
--- @field title string? Window title
--- @field title_pos "left"|"center"|"right"? Position of the window title
--- @field max_width integer? Max window width, including borders
--- @field number boolean? Display line numbers
--- @field meta table<"left"|"right", string?>? Meta bar content
--- @field highlights table<string, string>? Highlight groups
--- @field win_opts vim.api.keyset.win_config? Window options
--- @field filetype string? Default filetype for tabs
--- @field value TextareaUIValue? Content or tabs configuration
--- @field default_tab_id string? Default tab to display

--- Build a new TextareaUI instance.
--- @param user_config TextareaUIConfig
--- @return TextareaUIInstance
M.build = function(user_config)
  --- @class TextareaUIInstance
  local instance = {}

  --- @type TextareaUIConfig
  local config = {
    title = nil,
    title_pos = "center",
    max_width = 80,
    number = false,
    meta = {
      left = nil,
      right = nil,
    },
    highlights = {
      normal = "Normal",
    },
    win_opts = {
      relative = "cursor",
      row = -1, -- Compensate for the top meta bar
      col = 0,
      width = 80,
      height = 25,
      style = "minimal",
      focusable = false,
      border = "rounded",
    },
    filetype = "markdown",
    value = nil,
    default_tab_id = nil,
  }

  -- Merge user options into the default config
  config = vim.tbl_deep_extend("force", config, user_config)

  --- @class TextareaUIState
  --- @field buf_id integer? Buffer id
  --- @field win_id integer? Window id
  --- @field is_visible boolean Is the UI currently visible
  --- @field tabs_dict table<string, TextareaUITab> Dictionary of tabs keyed by tab id for fast lookup
  --- @field tabs_id_array string[] Array to maintain the tabs order as provided by the user
  --- @field active_tab_id string Current active tab id
  --- @field has_multiple_tabs boolean Did the user define multiple tabs
  local state = {
    buf_id = nil,
    win_id = nil,
    is_visible = false,
    tabs_dict = {},
    tabs_id_array = {},
    active_tab_id = "default",
    has_multiple_tabs = false,
  }

  ---
  local function setup_tabs()
    local value = config.value

    -- reset all tab related state
    state.tabs_id_array = {}
    state.tabs_dict = {}
    state.active_tab_id = nil
    state.has_multiple_tabs = false

    -- Validate and initialize tabs state
    if type(value) == "table" then
      -- User provided multiple tabs
      for _, tab in ipairs(value) do
        state.tabs_dict[tab.id] = tab
        table.insert(state.tabs_id_array, tab.id)
        if not tab.filetype then tab.filetype = config.filetype end
      end
      state.active_tab_id = config.default_tab_id or state.tabs_id_array[1]
      state.has_multiple_tabs = #state.tabs_id_array > 1
    else
      -- User provided a single value, create a default tab
      state.tabs_dict = {
        default = {
          id = "default",
          value = value or "",
          _resolved_value = nil,
          filetype = config.filetype,
        },
      }
      table.insert(state.tabs_id_array, "default")
      state.active_tab_id = "default"
      state.has_multiple_tabs = false
    end
  end

  setup_tabs()

  -- Handle conflicts between tabs and meta.left
  if state.has_multiple_tabs and config.meta.left then
    Logger.warn(
      "Cannot use both tabbed 'value' and 'meta.left'. Left side of the meta bar is used to render the tab names, 'meta.left' will not render."
    )
    config.meta.left = nil
  end

  -- Validate `default_tab_id` if provided
  if config.default_tab_id and not state.tabs_dict[config.default_tab_id] then
    Logger.warn(
      "'default_tab_id' does not exist in 'value' table, using the first tab as default.",
      { default_tab_id = config.default_tab_id }
    )
    state.active_tab_id = state.tabs_id_array[1]
  end

  --- Build the meta bar for the textarea window.
  --- @return string meta_line The formatted meta line.
  --- @return integer meta_width The visible width of the meta bar.
  local function build_meta_bar()
    local meta_left = config.meta.left or ""
    local meta_right = config.meta.right or ""

    if state.has_multiple_tabs then
      -- Build tabs display
      local tab_names = {}
      for _, tab_id in ipairs(state.tabs_id_array) do
        local tab = state.tabs_dict[tab_id]
        local tab_label = tab.label or tab.id
        if tab.id == state.active_tab_id then
          tab_label = "[" .. tab_label .. "]"
        end
        table.insert(tab_names, tab_label)
      end
      meta_left = table.concat(tab_names, " | ")
    end

    return "%#deckr41Left# " .. meta_left .. " %=%#deckr41Right# " .. meta_right,
      vim.fn.strdisplaywidth(meta_left .. meta_right) + 3
  end

  --- Get the contents of a tab.
  --- If `value` is a function, execute it and cache the result.
  --- @param tab_id string Tab id
  --- @return string
  local function get_tab_text(tab_id)
    local tab = state.tabs_dict[tab_id]
    if tab._resolved_value then return tab._resolved_value end

    local value = tab.value
    if type(value) == "string" then
      tab._resolved_value = value
    elseif type(value) == "function" then
      tab._resolved_value = value()
    else
      tab._resolved_value = ""
    end

    return tab._resolved_value
  end

  --- Calculate width and height based on content
  --- @param lines string[]
  --- @return integer width
  --- @return integer height
  local function calculate_dimensions(lines)
    local max_line_width = StringUtils.max_line_length(lines)
    local width = math.max(1, math.min(config.max_width, max_line_width))

    if config.number then
      local number_bar_width = 2 + (math.max(2, #tostring(#lines)))
      width = width - number_bar_width
    end

    if config.win_opts.border ~= "none" then width = width + 2 end

    local height = TableUtils.reduce(lines, function(acc, line)
      local line_width = #line == 0 and 1 or #line
      return acc + math.ceil(line_width / width)
    end, 0)

    return width, height
  end

  --- Internal render function for reflecting state changes in the UI.
  local function render()
    if not state.is_visible then return end

    local text = get_tab_text(state.active_tab_id)
    local lines = vim.split(text, "\n")
    local width, height = calculate_dimensions(lines)

    -- Build the meta bar and adjust width and height
    if config.meta.left or config.meta.right or state.has_multiple_tabs then
      local meta_bar_content, meta_bar_size = build_meta_bar()

      NVimUtils.set_win_options(state.win_id, {
        winbar = meta_bar_content or "",
      })

      width = math.max(width, meta_bar_size)
      height = height + 1
    end

    -- Ensure window does not exceed screen size
    width = math.min(width, config.max_width, vim.o.columns - 10)
    height = math.min(height, vim.o.lines - 10)

    -- Update window configuration
    vim.api.nvim_win_set_config(
      state.win_id,
      vim.tbl_extend("force", config.win_opts, {
        width = width,
        height = height,
        title = config.title,
        title_pos = config.title and config.title_pos or nil,
      })
    )

    -- Set buffer content
    vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, lines)

    -- Set new filetype if changed
    local current_filetype =
      vim.api.nvim_get_option_value("syntax", { buf = state.buf_id })
    local next_filetype = state.tabs_dict[state.active_tab_id].filetype

    if next_filetype ~= current_filetype then
      NVimUtils.set_buf_options(state.buf_id, {
        filetype = state.tabs_dict[state.active_tab_id].filetype,
      })
    end

    if config.number then vim.wo[state.win_id].number = true end
  end

  --- @param new_config TextareaUIConfig
  function instance.update(new_config)
    config = vim.tbl_deep_extend("force", config, new_config)
    if new_config.value then setup_tabs() end
    if state.is_visible then render() end
  end

  --- Show the Textarea window.
  function instance.show()
    if state.is_visible then return end
    state.is_visible = true

    if not NVimUtils.is_buf_valid(state.buf_id) then
      state.buf_id = vim.api.nvim_create_buf(false, true)
    end
    if not NVimUtils.is_win_valid(state.win_id) then
      state.win_id = vim.api.nvim_open_win(
        state.buf_id,
        false,
        vim.tbl_deep_extend("force", config.win_opts or {}, {
          noautocmd = true,
        })
      )
    end

    render()
  end

  --- Close the textarea window and destroy vim resources.
  function instance.hide()
    if NVimUtils.is_win_valid(state.win_id) then
      vim.api.nvim_win_close(state.win_id, true)
    end
    if NVimUtils.is_buf_valid(state.buf_id) then
      vim.api.nvim_buf_delete(state.buf_id, { force = true })
    end

    state.win_id = nil
    state.buf_id = nil
    state.is_visible = false
  end

  --- Return the contents of a tab.
  --- If `tab_id` is not specified, the active one is used.
  --- @param tab_id string? Tab id
  --- @return string
  function instance.get_text(tab_id)
    tab_id = tab_id or state.active_tab_id
    if not state.tabs_dict[tab_id] then
      Logger.error("Tab not found", {
        tab_id = tab_id,
        available_tabs = vim.tbl_keys(state.tabs_dict),
      })
    end

    return get_tab_text(tab_id or state.active_tab_id)
  end

  --- Set the contents of a tab.
  --- If `tab_id` is not specified, the active one is used.
  --- @param text string New content for the tab
  --- @param tab_id string? Tab id
  function instance.set_text(text, tab_id)
    local tab = state.tabs_dict[tab_id or state.active_tab_id]
    if not tab then
      Logger.error("Tab not found", {
        tab_id = tab_id,
        available_tabs = vim.tbl_keys(state.tabs_dict),
      })
      return
    end

    tab._resolved_value = text
    if state.is_visible then
      render()
      -- Scroll to top
      vim.api.nvim_win_set_cursor(state.win_id, { 1, 0 })
    end
  end

  --- Append text to the contents of a tab.
  --- If `tab_id` is not specified, the active one is used.
  --- @param text string Text to append
  --- @param tab_id string? Tab id
  function instance.append_text(text, tab_id)
    local tab = state.tabs_dict[tab_id or state.active_tab_id]
    if not tab then
      Logger.error("Tab not found", {
        tab_id = tab_id,
        available_tabs = vim.tbl_keys(state.tabs_dict),
      })
      return
    end

    local current_value = get_tab_text(tab.id)
    tab._resolved_value = current_value .. text
    if state.is_visible then render() end
  end

  --- Switch to a different tab by id.
  --- @param tab_id string Tab id
  function instance.switch_tab(tab_id)
    if state.tabs_dict[tab_id] then
      state.active_tab_id = tab_id
    else
      Logger.error("Tab not found", {
        tab_id = tab_id,
        available_tabs = vim.tbl_keys(state.tabs_dict),
      })
      return
    end

    if state.is_visible then
      render()
      -- Scroll to top
      vim.api.nvim_win_set_cursor(state.win_id, { 1, 0 })
    end
  end

  --- Switch to the next tab
  function instance.switch_next_tab()
    local index = ArrayUtils.get_index(state.active_tab_id, state.tabs_id_array)
    if index == #state.tabs_id_array then index = 0 end
    instance.switch_tab(state.tabs_id_array[index + 1])
  end

  --- Switch to the previous tab
  function instance.switch_prev_tab()
    local index = ArrayUtils.get_index(state.active_tab_id, state.tabs_id_array)
    if index == 1 then index = #state.tabs_id_array + 1 end
    instance.switch_tab(state.tabs_id_array[index - 1])
  end

  --- Update the meta information displayed in the textarea.
  --- @param sides { left?: string, right?: string } Meta bar content
  function instance.set_meta(sides)
    config.meta = vim.tbl_deep_extend("force", config.meta, sides or {})
    if state.is_visible then render() end
  end

  --- Check if a tab is empty.
  --- If `tab_id` is not specified, the active one is used.
  --- @param tab_id string? Tab id
  function instance.is_empty(tab_id)
    local tab = state.tabs_dict[tab_id or state.active_tab_id]
    local value = get_tab_text(tab.id)
    return not value or value == ""
  end

  --- Check if the component is visible.
  --- @return boolean
  function instance.is_visible() return state.is_visible end

  --- Scroll to the top of the current tab.
  function instance.scroll_top()
    if not state.is_visible then return end
    vim.api.nvim_win_set_cursor(state.win_id, { 1, 0 })
  end

  --- Scroll to the bottom of the current tab.
  function instance.scroll_bottom()
    if not state.is_visible then return end
    local line_count = vim.api.nvim_buf_line_count(state.buf_id)
    vim.api.nvim_win_set_cursor(state.win_id, { line_count, 0 })
  end

  return instance
end

return M
