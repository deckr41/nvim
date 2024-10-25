--- Utilities imports
local FnUtils = require("deckr41.utils.fn")
local Logger = require("deckr41.utils.loggr")("InsertModeHandler")
local NVimUtils = require("deckr41.utils.nvim")
local Pinpointer = require("deckr41.utils.pinpointr")
local SuggestionUI = require("deckr41.ui.suggestion")
local WindowUtils = require("deckr41.utils.window")

--- Domain imports
local Commands = require("deckr41.commands")

--- @class InsertModeHandler
local M = {}

--- @alias InsertModeName "easy-does-it"|"r-for-rocket"

--- @class InsertModeEasyDoesIt
--- @field command string
--- @field double_command string

--- @class InsertModeRForRocket
--- @field timeout integer
--- @field command string

--- @class InsertModes
--- @field ["easy-does-it"] InsertModeEasyDoesIt
--- @field ["r-for-rocket"] InsertModeRForRocket

--- @class InsertModeConfig
--- @field modes InsertModes
--- @field active_mode InsertModeName
local config = {
  modes = {
    ["easy-does-it"] = {
      command = "finish-line",
      double_command = "finish-block",
    },
    ["r-for-rocket"] = {
      command = "finish-block",
      timeout = 1000,
    },
  },
  active_mode = "easy-does-it",
}

--- @class InsertModeState
--- @field job Job? Plenary Job of currently running command
--- @field suggestion_ui SuggestionUIInstance?
--- @field shift_arrow_right_count integer RightArrow press counter since NeoVim cannot bind Shift + ArrowRight + ArrowRight
local state = {
  job = nil,
  suggestion_ui = nil,
  shift_arrow_right_count = 0,
}

--
-- Private methods
--

--- @return boolean
local function can_accept() return state.job ~= nil and state.job.is_shutdown end

--- @return boolean
local function is_command_running()
  return state.job ~= nil and not state.job.is_shutdown
end

local function apply()
  local pinpoint = Pinpointer.get()
  WindowUtils.insert_text_at(state.suggestion_ui.get_text(), {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    range = nil,
    clear_ahead = true,
  })

  state.suggestion_ui.hide()
  state.job = nil
end

local function refuse()
  if state.job then
    state.job:shutdown(41)
    state.job = nil
  end
  state.suggestion_ui.hide()
end

local function run_command(name)
  local pinpoint = Pinpointer.take_snapshot()

  state.suggestion_ui.update({
    status = "asking",
    filetype = pinpoint.filetype,
  })

  return Commands.run({ name = name }, {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    range = pinpoint.range,
    on_start = function(cmd_config)
      state.suggestion_ui.update({
        meta = string.format("%s / %s ", name, cmd_config.model),
      })
      state.suggestion_ui.show()
    end,
    on_data = function(chunk)
      if not chunk or chunk == "" then return end
      state.suggestion_ui.append_text(chunk)
    end,
    on_done = function(response, http_status)
      if http_status >= 400 then
        state.suggestion_ui.update({ value = response })
      end
      state.suggestion_ui.update({ status = "done" })
    end,
    on_error = function(response)
      -- 41 is the shutdown code used when the cursor moves. We only want
      -- to fill and display the response if it's an OS or API error
      if response and response.exit ~= 41 then
        state.suggestion_ui.append_text(response.message)
      end
      state.suggestion_ui.update({ status = "done" })
    end,
  })
end

--- Setup key mappings
local setup_keymaps = function()
  local mode = config.modes[config.active_mode]

  -- On first Shift+Right, no matter the mode, trigger the assigned command.
  -- On 2xShift+right, if mode is "easy-does-it", trigger the double command.
  local function handle_shift_right()
    if can_accept() then return apply() end
    if is_command_running() then return end

    state.shift_arrow_right_count = state.shift_arrow_right_count + 1
    vim.defer_fn(function()
      local count = state.shift_arrow_right_count
      if count == 1 then
        state.job = run_command(mode.command)
      elseif config.active_mode == "easy-does-it" and count == 2 then
        state.job = run_command(mode.double_command)
      end
      state.shift_arrow_right_count = 0
    end, 200)
  end

  NVimUtils.add_keymap("<S-Right>", {
    desc = "[deckr41] Trigger Shift+Right default commands",
    modes = { i = handle_shift_right },
  })

  NVimUtils.add_keymap("<Tab>", {
    desc = "[deckr41] Insert/accept suggestion if available",
    modes = {
      i = function()
        if can_accept() then
          apply()
        else
          -- Send the key as normal input
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Tab>", true, false, true),
            "n",
            false
          )
        end
      end,
    },
  })

  NVimUtils.add_keymap("<Escape>", {
    desc = "[deckr41] Cancel ongoing suggestion or exit insert mode",
    modes = {
      i = function()
        if state.job ~= nil then
          refuse()
        else
          -- Send the key as normal input
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Escape>", true, false, true),
            "n",
            true
          )
        end
      end,
    },
  })
end

--- Setup autocommands based on the mode
local setup_autocmds = function()
  local augroup =
    vim.api.nvim_create_augroup("D41KeymapInsertGroup", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function() refuse() end,
  })

  -- In 'r-for-rocket' mode, trigger suggestions on InsertEnter and TextChangedI
  local mode = config.modes[config.active_mode]
  local debounced_command, timer = FnUtils.debounce(function()
    if config.active_mode == "r-for-rocket" then
      state.job = run_command(mode.command)
    end
  end, { reset_duration = config.modes["r-for-rocket"].timeout })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    callback = function() debounced_command() end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function() debounced_command() end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function() timer:stop() end,
  })
end

--
-- Public methods
--

--- @class InsertModeOpts
--- @field active_mode ?InsertModeName
--- @field modes ?InsertModes

--- @param user_config InsertModeOpts
M.setup = function(user_config)
  config = vim.tbl_deep_extend("force", config, {
    active_mode = user_config.active_mode,
    modes = user_config.modes,
  })
  state.suggestion_ui = SuggestionUI.build({ win_opts = { border = "none" } })

  setup_keymaps()
  setup_autocmds()
end

--- @param mode InsertModeName
M.set_active_mode = function(mode)
  if not config.modes[mode] then
    Logger.error("Invalid mode", { mode = mode })
    return
  end
  config.active_mode = mode
end

--- @return InsertModeName[]
M.get_modes = function() return vim.tbl_keys(config.modes) end

--- @return InsertModeName
M.get_active_mode = function() return config.active_mode end

return M
