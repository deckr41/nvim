-- width
-- width
local Logger = require("deckr41.utils.loggr")("SelectUI")
local NVimUtils = require("deckr41.utils.nvim")
local TableUtils = require("deckr41.utils.table")
local TextareaUI = require("deckr41.ui.textarea")

--- Custom highlight style
local string_hl_group =
  vim.api.nvim_get_hl(0, { name = "String", link = false })
vim.api.nvim_set_hl(0, "D41SelectUISelected", {
  fg = string_hl_group.fg or "#00FF00",
})

--- @class SelectUIItem
--- @field id string
--- @field group_id? string
--- @field label? string
--- @field is_separator? boolean
--- @field is_selected? boolean
--- @field preview? string|(fun():string)|TextareaUITab[]

--- @class SelectUIItemGroup
--- @field id string
--- @field label? string
--- @field items SelectUIItem[]
--- @field selected? string

--- @class SelectUI
local M = {}

--- Build render-ready items from groups
--- @param groups SelectUIItemGroup[]
--- @return SelectUIItem[]
local build_items_from_groups = function(groups)
  local result_array = {}
  local index = 1

  for _, group in ipairs(groups) do
    result_array[index] = {
      id = group.id,
      label = group.label or group.id,
      is_separator = true,
    }
    index = index + 1

    for _, item in ipairs(group.items) do
      local is_selected = group.selected == item.id
      local marker = is_selected and " " or "  "
      result_array[index] = {
        id = item.id,
        group_id = group.id,
        label = marker .. (item.label or item.id),
        is_selected = is_selected,
        preview = item.preview,
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

--- @class SelectUIHighlights
--- @field normal string?
--- @field cursorline string?
--- @field separator string?
--- @field title string?
--- @field selected string?

--- @class SelectUIConfig
--- @field groups SelectUIItemGroup[]?
--- @field max_width? integer
--- @field max_height? integer
--- @field title? string
--- @field title_pos? "left"|"right"|"center"
--- @field highlights SelectUIHighlights?
--- @field win_opts vim.api.keyset.win_config? Window options
--- @field close_on_select boolean?
--- @field on_open function?
--- @field on_close  function?
--- @field on_select fun(self: SelectUIInstance, item: SelectUIItem)?
--- @field preview_config TextareaUIConfig?

--- Build a new SelectUI instance.
--- @param user_config SelectUIConfig
--- @return SelectUIInstance
M.build = function(user_config)
  --- @class SelectUIInstance
  local instance = {}

  --- @type SelectUIConfig
  local config = {
    groups = {},
    max_width = 20,
    max_height = 50,
    title = nil,
    title_pos = "center",
    highlights = {
      normal = "Normal",
      cursorline = "CursorLine",
      separator = "Comment",
      selected = "D41SelectUISelected",
      title = "Normal",
    },
    win_opts = {
      relative = "cursor",
      width = 20,
      height = 50,
      row = -1,
      col = 0,
      style = "minimal",
      border = "rounded",
      noautocmd = true,
    },
    close_on_select = false,
    on_open = nil,
    on_close = nil,
    on_select = nil,
    preview_config = {
      title = " Preview ",
      win_opts = {
        relative = "win",
        anchor = "NW",
        focusable = true, -- For scrolling to work
      },
    },
  }

  -- Merge user options into the default config
  config = vim.tbl_deep_extend("force", config, user_config)

  --- @class SelectUIState
  local state = {
    buf_id = nil, --- @type integer? Buffer id
    win_id = nil, --- @type integer? Window id
    is_visible = false, --- @type boolean Is the UI currently visible
    items = build_items_from_groups(config.groups or {}),
    cursor_pos = 0, --- @type integer
    preview_ui = nil, --- @type TextareaUIInstance?
  }

  --- Update the preview window based on the selected item
  local function render_preview()
    if not state.is_visible then return end

    local item = state.items[state.cursor_pos]
    if not item or item.is_separator or not item.preview then
      -- New selected hovered item does not have a preview, close current pane
      if state.preview_ui then
        state.preview_ui.hide()
        state.preview_ui = nil
      end
      return
    end

    if not state.preview_ui then
      state.preview_ui = TextareaUI.build(
        vim.tbl_deep_extend("force", config.preview_config or {}, {
          value = item.preview,
          win_opts = {
            win = state.win_id,
            row = -1,
            col = vim.api.nvim_win_get_width(state.win_id) + 1,
          },
        })
      )
    else
      state.preview_ui.update({ value = item.preview })
    end

    state.preview_ui.show()
  end

  --- Move the cursor up or down
  --- @param direction "up"|"down"
  local function move(direction)
    local new_position = move_cursor(direction == "up" and -1 or 1, {
      items = state.items,
      cursor_pos = state.cursor_pos,
      should_cycle = false,
    })

    if new_position == state.cursor_pos then return end

    state.cursor_pos = new_position
    if state.is_visible then
      vim.api.nvim_win_set_cursor(state.win_id, { state.cursor_pos, 0 })
      render_preview()
    end
  end

  --- Handle keymaps for the select UI
  local function setup_keymaps()
    NVimUtils.add_keymaps({
      buf_id = state.buf_id,
      modes = {
        n = {
          ["<CR>"] = instance.select_item,
          ["<Esc>"] = instance.hide,
          ["j"] = function() move("down") end,
          ["<Down>"] = function() move("down") end,
          ["k"] = function() move("up") end,
          ["<Up>"] = function() move("up") end,
          ["<Tab>"] = function()
            if state.preview_ui then state.preview_ui.switch_next_tab() end
          end,
          ["<S-Tab>"] = function()
            if state.preview_ui then state.preview_ui.switch_prev_tab() end
          end,
        },
      },
    })
  end

  ---@return integer width
  ---@return integer height
  local function calculate_dimensions()
    local max_label_length = TableUtils.max_with(
      state.items,
      function(item) return vim.fn.strdisplaywidth(item.label or "") end
    ) or 0
    local item_count = #state.items

    return
      -- width
      math.max(max_label_length + 1, vim.fn.strdisplaywidth(config.title)),
      -- height
      math.min(item_count ~= 0 and item_count or 2, config.max_height)
  end

  --- Render the items in the buffer
  local render = function()
    if not state.is_visible then return end

    vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf_id })
    vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, {})

    for index, item in ipairs(state.items) do
      local line = item.label
      local line_index = index - 1

      vim.api.nvim_buf_set_lines(
        state.buf_id,
        line_index,
        line_index,
        false,
        { line }
      )

      -- Apply separator highlight
      local line_highlight = nil
      if item.is_separator then line_highlight = config.highlights.separator end
      if item.is_selected then line_highlight = config.highlights.selected end

      if line_highlight then
        vim.api.nvim_buf_add_highlight(
          state.buf_id,
          -1,
          line_highlight,
          line_index,
          0,
          -1
        )
      end
    end

    local width, height = calculate_dimensions()
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

  --- Show the Select window.
  function instance.show()
    if state.is_visible then return end
    if #state.items == 0 then
      Logger.warn("Cannot render menu without any items.")
      return
    end
    state.is_visible = true

    if config.on_open then config.on_open() end

    if not NVimUtils.is_buf_valid(state.buf_id) then
      state.buf_id = NVimUtils.create_scratch_buffer({
        buftype = "nofile",
        bufhidden = "wipe",
        buflisted = false,
        swapfile = false,
        modifiable = false,
        filetype = "d41_ui_select",
      })

      setup_keymaps()
    end

    if not NVimUtils.is_win_valid(state.win_id) then
      state.win_id = vim.api.nvim_open_win(
        state.buf_id,
        true,
        vim.tbl_deep_extend("force", config.win_opts or {}, {
          noautocmd = true,
          title = config.title,
          title_pos = config.title_pos,
        })
      )

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
    end

    -- Force initial position calculation
    if state.cursor_pos == 0 then
      state.cursor_pos = 1
      if state.items[1].is_separator and #state.items > 1 then
        state.cursor_pos = 2
      end
    end

    render()
    render_preview()
  end

  --- Close the select window and destroy vim resources.
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

    if config.on_close then vim.schedule(function() config.on_close() end) end

    if state.preview_ui then
      state.preview_ui.hide()
      state.preview_ui = nil
    end
  end

  --- @param new_config SelectUIConfig
  function instance.update(new_config)
    config = vim.tbl_deep_extend("force", config, new_config)
    if new_config.groups then
      state.items = build_items_from_groups(new_config.groups)
    end
    if state.is_visible then
      render()
      render_preview()
    end
  end

  --- Handle item selection
  function instance.select_item()
    local item = state.items[state.cursor_pos]
    if not item or item.is_separator or item.is_selected then return end

    if config.on_select then
      vim.schedule(function() config.on_select(instance, item) end)
    end
    if config.close_on_select then instance.hide() end
  end

  return instance
end

return M
