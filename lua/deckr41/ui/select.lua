local Logger = require("deckr41.utils.logger")
local NVimUtils = require("deckr41.utils.nvim")
local TableUtils = require("deckr41.utils.table")

--- Custom highlight style
--- Define your highlight group using already defined theme color
local string_hl_group =
  vim.api.nvim_get_hl(0, { name = "String", link = false })

vim.api.nvim_set_hl(0, "D41SelectUISelected", {
  fg = string_hl_group.fg or "#00FF00",
})

--- @class SelectUIItem
--- @field id string
--- @field group_id? string
--- @field text string
--- @field is_separator? boolean
--- @field is_selected? boolean

--- @class SelectUIItemGroup
--- @field id string
--- @field text string
--- @field items SelectUIItem[]
--- @field selected string

--- @class SelectUI
local SelectUI = {}

--- Calculate the width of the window based on the longest item
--- @param items SelectUIItem[]
--- @return number
local max_line_width = function(items)
  return TableUtils.max_with(
    items,
    function(item) return vim.fn.strdisplaywidth(item.text) end
  ) or 0
end

--- Render the items in the buffer
--- @param config SelectUIConfig
--- @param state SelectUIState
local render = function(config, state)
  if not NVimUtils.is_buf_valid(state.buf_id) then
    Logger.error("Buffer ID is invalid", { buf_id = state.buf_id })
    return
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf_id })
  vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, {})

  for idx, item in ipairs(state.items) do
    local line = item.text
    local line_index = idx - 1

    vim.api.nvim_buf_set_lines(
      state.buf_id,
      line_index,
      line_index,
      false,
      { line }
    )

    -- Apply separator highlight
    local line_heighlight = nil

    if item.is_separator then line_heighlight = config.highlights.separator end

    if item.is_selected then line_heighlight = config.highlights.selected end

    if line_heighlight then
      vim.api.nvim_buf_add_highlight(
        state.buf_id,
        -1,
        line_heighlight,
        line_index,
        0,
        -1
      )
    end
  end

  -- Refresh dimensions in case items changed
  local width = max_line_width(state.items) + 1 -- right padding
  local height = math.min(#state.items, config.max_height)

  vim.api.nvim_win_set_config(state.win_id, {
    width = width,
    height = height,
  })

  -- Freeze it back after updating the content
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf_id })

  -- Set cursor to the current item position
  vim.api.nvim_win_set_cursor(state.win_id, { state.cursor_pos, 0 })

  -- Ensure the window's view starts from the first line
  vim.api.nvim_win_call(state.win_id, function()
    local view = vim.fn.winsaveview()
    view.topline = 1 -- Set the top visible line to the first line
    vim.fn.winrestview(view)
  end)
end

--- Build render-ready items from groups
--- @param groups SelectUIItemGroup[]
--- @return SelectUIItem[]
local build_items_from_groups = function(groups)
  local result_array = {}
  local index = 1

  for _, group in ipairs(groups) do
    result_array[index] = {
      id = group.id,
      text = "[" .. (group.text or group.id) .. "]",
      is_separator = true,
    }
    index = index + 1

    for _, item in ipairs(group.items) do
      local is_selected = group.selected == item.id
      local marker = is_selected and " " or "  "
      result_array[index] = {
        id = item.id,
        group_id = group.id,
        text = marker .. item.text,
        is_selected = is_selected,
      }
      index = index + 1
    end
  end

  return result_array
end

--- Move the cursor up or down
--- @param delta integer
--- @param opts { items: SelectUIItem[], cursor_pos: integer, should_cycle?: boolean }
--- @return integer: The new cursor position
local move_cursor = function(delta, opts)
  opts = opts or {}
  local should_cycle = opts.should_cycle or false
  local new_pos = opts.cursor_pos + delta

  if new_pos < 1 then
    new_pos = should_cycle and #opts.items or 1
  elseif new_pos > #opts.items then
    new_pos = should_cycle and 1 or #opts.items
  end

  -- Skip separators
  while opts.items[new_pos] and opts.items[new_pos].is_separator do
    new_pos = new_pos + delta
    if new_pos < 1 then
      new_pos = should_cycle and #opts.items or 2
    elseif new_pos > #opts.items then
      new_pos = should_cycle and 1 or #opts.items
    end
  end

  return new_pos
end

--- @class SelectUIBuildOpts
--- @field items SelectUIItemGroup[]
--- @field max_height? number
--- @field max_width? number
--- @field title? string
--- @field title_pos? "left"|"center"|"right"
--- @field highlights? { normal?: string, cursorline?: string, separator?: string, title?: string }
--- @field should_close_on_change? boolean
--- @field on_change? fun(self: SelectUIInstance, item: SelectUIItem)

--- Build a new select UI instance
--- @param opts SelectUIBuildOpts
--- @return SelectUIInstance|nil
SelectUI.build = function(opts)
  if not opts.items or type(opts.items) ~= "table" then
    Logger.error(
      "Cannot create instance with invalid items parameter",
      { items = opts.items }
    )
    return
  end

  --- @class SelectUIInstance
  local instance = {}

  --- @class SelectUIConfig
  local config = {
    max_height = opts.max_height or 50,
    max_width = opts.max_width or 20,
    title = opts.title,
    title_pos = opts.title_pos or "center",
    highlights = vim.tbl_deep_extend("force", {
      normal = "Normal",
      cursorline = "CursorLine",
      separator = "Comment",
      selected = "D41SelectUISelected",
      title = "Normal",
    }, opts.highlights or {}),
    should_close_on_change = opts.should_close_on_change or false,
    --- @type fun(self: SelectUIInstance, item: SelectUIItem)
    on_change = opts.on_change,
  }

  --- @class SelectUIState
  local state = {
    win_id = nil,
    buf_id = nil,
    --- @type SelectUIItem[]
    items = build_items_from_groups(opts.items or {}),
    cursor_pos = 0,
  }

  --- @param direction "up"|"down"
  local move = function(direction)
    state.cursor_pos = move_cursor(direction == "up" and -1 or 1, {
      items = state.items,
      cursor_pos = state.cursor_pos,
      should_cycle = false,
    })
    if NVimUtils.is_win_valid(state.win_id) then
      vim.api.nvim_win_set_cursor(state.win_id, { state.cursor_pos, 0 })
    end
  end

  -- Ensure cursor starts at the correct item position, considering separators
  move("down")

  --- Open the select UI
  instance.open = vim.schedule_wrap(function()
    if NVimUtils.is_win_valid(state.win_id) then
      Logger.warn("SelectUI already open", { win_id = state.win_id })
      return
    end
    if #state.items == 0 then
      Logger.warn(
        "SelectUI cannot be opened with no items",
        { items = state.items }
      )
      return
    end

    -- Create a new buffer
    state.buf_id = NVimUtils.create_scratch_buffer({
      buftype = "nofile",
      bufhidden = "wipe",
      buflisted = false,
      swapfile = false,
      modifiable = false,
      filetype = "d41_ui_select",
    })

    -- Calculate window size and position
    local width = max_line_width(state.items) + 1 -- right padding
    local height = math.min(#state.items, config.max_height)

    -- Create a floating window at the cursor position
    state.win_id = vim.api.nvim_open_win(state.buf_id, true, {
      relative = "cursor",
      row = -1,
      col = 0,
      title = config.title,
      title_pos = config.title_pos,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      noautocmd = true,
    })

    NVimUtils.set_win_options(state.win_id, {
      cursorline = true,
      scrolloff = 0,
      winhl = table.concat({
        "Normal:" .. config.highlights.normal,
        "FloatBorder:Normal",
        "CursorLine:" .. config.highlights.cursorline,
        "FloatTitle:" .. config.highlights.title,
      }, ","),
    })

    --- Set keymaps for navigation and selection
    NVimUtils.add_keymaps({
      ["<CR>"] = instance.select_item,
      ["<Esc>"] = instance.hide,
      ["j"] = function() move("down") end,
      ["<Down>"] = function() move("down") end,
      ["k"] = function() move("up") end,
      ["<Up>"] = function() move("up") end,
    }, {
      mode = "n",
      buf_id = state.buf_id,
    })

    -- Close when loosing focus
    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = state.buf_id,
      callback = function() instance.hide() end,
    })

    render(config, state)
  end)

  --- Hide the select UI
  instance.hide = vim.schedule_wrap(function()
    if NVimUtils.is_win_valid(state.win_id) then
      vim.api.nvim_win_close(state.win_id, true)
      state.win_id = nil
      state.buf_id = nil
    end
  end)

  --- Refresh the select UI with new items
  --- @param groups SelectUIItemGroup[]
  instance.refresh = vim.schedule_wrap(function(groups)
    state.items = groups and build_items_from_groups(groups) or state.items
    render(config, state)
  end)

  --- Handle item selection
  instance.select_item = function()
    local item = state.items[state.cursor_pos]
    if not item or item.is_separator then return end

    if config.on_change then
      vim.schedule(function() config.on_change(instance, item) end)
    end
    if config.should_close_on_change then instance.hide() end
  end

  return instance
end

return SelectUI
