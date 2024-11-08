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
      double_command = "finish-section",
    },
    ["r-for-rocket"] = {
      command = "finish-section",
      timeout = 1000,
    },
  },
  active_mode = "easy-does-it",
}

--- @class InsertModeState
--- @field job Job? Plenary Job of currently running command
--- @field suggestion_ui SuggestionUIInstance?
--- @field shift_right_count integer RightArrow press counter since NeoVim cannot bind Shift + ArrowRight + ArrowRight
--- @field is_applying_suggestion boolean Indicates if a suggestion is being applied
--- @field can_auto_trigger boolean Indicates whether a new suggestion can be triggered
local state = {
  job = nil,
  suggestion_ui = nil,
  shift_right_count = 0,
  is_applying_suggestion = false,
  can_auto_trigger = true,
}

--
-- Private methods
--

--- @return boolean
local function can_accept_suggestion()
  return state.job ~= nil and state.job.is_shutdown
end

--- @return boolean
local function is_job_running()
  return state.job ~= nil and not state.job.is_shutdown
end

local function apply_suggestion()
  state.can_auto_trigger = false
  state.is_applying_suggestion = true

  local pinpoint = Pinpointer.get()
  WindowUtils.insert_text_at(state.suggestion_ui.get_text(), {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    range = nil,
    clear_ahead = true,
  })

  state.suggestion_ui.hide()
  state.job = nil

  -- Reset the flag after a short delay.
  -- The suggestion insertion triggers TextChangedI, which we need to ignore,
  -- otherwise a new suggestion will be triggered right after one was applied.
  -- Due to asynchronous event firing, we use vim.defer_fn to reset the flag
  -- after we're "sure" the event finished.
  vim.defer_fn(function() state.is_applying_suggestion = false end, 10)
end

--- Cancel the current suggestion and reset state.
local function cancel_suggestion()
  -- Force the user to make a change before suggesting again.
  state.can_auto_trigger = false
  if state.job then
    state.job:shutdown(41)
    state.job = nil
  end
  state.suggestion_ui.hide()
end

--- Run a command and update the suggestion UI as the LLM reply comes back.
--- @param name string Command name to run
local function run_command(name)
  local pinpoint = Pinpointer.take_snapshot()

  state.suggestion_ui.update({
    status = "asking",
    filetype = pinpoint.filetype,
  })

  state.job = Commands.run({ name = name }, {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    on_start = function(cmd_config)
      state.suggestion_ui.update({
        meta = string.format("%s / %s ", name, cmd_config.model),
      })
      state.suggestion_ui.show()
    end,
    on_data = function(chunk) state.suggestion_ui.append_text(chunk) end,
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
  --- Debounced function to handle accumulated Shift+RightArrow presses.
  --- On first press, trigger the mode's `command`.
  --- On second press (in "easy-does-it" mode), trigger the `double_command`.
  local debounced_shift = FnUtils.debounce(function()
    local mode = config.modes[config.active_mode]
    if state.shift_right_count == 1 then
      run_command(mode.command)
    elseif state.shift_right_count >= 2 then
      run_command(mode.double_command)
    end

    state.shift_right_count = 0
  end, { reset_duration = 200 })

  --- Handler for Shift+RightArrow key press.
  --- Count the number of presses and evaluate what to do when stopping after
  --- 200ms.
  local function handle_shift_right_press()
    if can_accept_suggestion() then return apply_suggestion() end
    if is_job_running() then return end

    state.shift_right_count = state.shift_right_count + 1
    debounced_shift()
  end

  NVimUtils.add_keymap("<S-Right>", {
    desc = "[deckr41] Trigger Shift+Right default commands",
    modes = { i = handle_shift_right_press },
  })

  NVimUtils.add_keymap("<Tab>", {
    desc = "[deckr41] Insert/accept suggestion if available",
    modes = {
      i = function()
        if can_accept_suggestion() then
          apply_suggestion()
        else
          -- Send the key as normal input
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Tab>", true, false, true),
            "n",
            true
          )
        end
      end,
    },
  })

  NVimUtils.add_keymap("<Escape>", {
    desc = "[deckr41] Cancel ongoing suggestion or exit insert mode",
    modes = {
      i = function()
        if state.job ~= nil then cancel_suggestion() end

        -- Send the key as normal input to exit insert mode
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<Escape>", true, false, true),
          "n",
          true
        )
      end,
    },
  })
end

--- Setup autocommands based on the mode
--- In 'r-for-rocket' mode, trigger suggestions on InsertEnter and TextChangedI
local setup_autocmds = function()
  local mode = config.modes[config.active_mode]
  local augroup =
    vim.api.nvim_create_augroup("D41InsertModeGroup", { clear = true })

  local trigger_suggestion, suggestion_timer = FnUtils.debounce(function()
    if state.is_applying_suggestion then return end
    if not state.can_auto_trigger then return end

    run_command(mode.command)
  end, { reset_duration = mode.timeout or 1000 })

  -- This will cancel the suggestion in both modes, not only "r-for-rocket".
  vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
    group = augroup,
    -- TODO: When entering INSERT mode via "o" (new line + insert mode)
    -- and indentation is involved, moving the cursor will ALSO trigger a
    -- TextChangedI event which will trigger a new suggestion, counter to
    -- us not expecting it since we didnt change anything, we just
    -- moved the cursor.
    callback = function()
      -- Stop timer to cancel potential trailing call. This prevents the
      -- suggestion_ui from popping up after user exited INSERT mode and
      -- moved on to something else.
      suggestion_timer:stop()
      cancel_suggestion()
    end,
  })

  if config.active_mode == "r-for-rocket" then
    vim.api.nvim_create_autocmd({ "InsertEnter", "TextChangedI" }, {
      group = augroup,
      callback = function()
        state.can_auto_trigger = true
        trigger_suggestion()
      end,
    })
  end
end

--
-- Public methods
--

--- @class InsertModeOpts
--- @field active_mode? InsertModeName
--- @field modes? InsertModes

--- Initialize the module with user configuration.
--- @param user_config InsertModeOpts
function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, {
    active_mode = user_config.active_mode,
    modes = user_config.modes,
  })
  state.suggestion_ui = SuggestionUI.build({ win_opts = { border = "none" } })

  setup_keymaps()
  setup_autocmds()
end

--- Set the active insert mode.
--- @param mode InsertModeName
function M.set_active_mode(mode)
  if not config.modes[mode] then
    Logger.error("Invalid mode", { mode = mode })
  end
  config.active_mode = mode
  setup_autocmds()
end

--- Get the list of available insert modes.
--- @return InsertModeName[]
function M.get_modes() return vim.tbl_keys(config.modes) end

--- Get the current active insert mode.
--- @return InsertModeName
function M.get_active_mode() return config.active_mode end

return M
