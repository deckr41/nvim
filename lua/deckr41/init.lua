--- Utilities imports
local Logger = require("deckr41.utils.logger") --- @type Logger
local NVimUtils = require("deckr41.utils.nvim") --- @type NVimUtils
local SelectUI = require("deckr41.ui.select") --- @type SelectUI
local StringUtils = require("deckr41.utils.string") --- @type StringUtils
local TableUtils = require("deckr41.utils.table") --- @type TableUtils
local TelescopeUtils = require("deckr41.utils.telescope") --- @type TelescopeUtils

--- Domain imports
local Backend = require("deckr41.backend") --- @type BackendModule
local Commands = require("deckr41.commands") --- @type CommandsModule
local Keyboard = require("deckr41.keyboard") --- @type KeyboardModule
local Suggestion = require("deckr41.suggestion") --- @type SuggestionModule

--- @class Deckr41Plugin
local M = {}

--- @class Deckr41PluginConfig
--- @field emoji_title string
local config = {
  emoji_title = "  + 󰚩",
}

--- @class Deckr41PluginState
--- @field running_command_job? Job
local state = {
  -- Plenary Job of currently running command
  running_command_job = nil,
}

---@param command_id string
local run_command = function(command_id)
  if state.running_command_job ~= nil then return end

  local command = Commands:get_command_by_id(command_id)
  if not command then
    Logger.error("Command not found", { id = command_id })
    return
  end

  local context = Commands:gather_context()
  local prompt = StringUtils.interpolate(command.prompt, context)
  local system_prompt = command.system_prompt
      and StringUtils.interpolate(command.system_prompt, context)
    or nil

  local status, job = pcall(Backend.ask, {
    system_prompt = system_prompt,
    max_tokens = command.max_tokens,
    temperature = command.temperature,
    messages = {
      {
        role = "user",
        content = prompt,
      },
    },
    on_start = function(config)
      Suggestion.meta.bar_right =
        string.format("%s / %s ", command_id, config.model or "?")
      Suggestion:start_loading()
      Suggestion:show()
    end,
    on_data = function(chunk)
      Suggestion.text = Suggestion.text .. chunk
      Suggestion:redraw()
    end,
    on_done = function(response, http_status)
      if http_status >= 400 then Suggestion.text = response end
      Suggestion:finish_loading()
      Suggestion:redraw()
    end,
    on_error = function(response)
      -- 41 is the shutdown code used when the cursor moves. We only want
      -- to fill and display the response if it's an OS or API error
      if response and response.exit ~= 41 then
        Suggestion.text = Suggestion.text .. response.message
      end
    end,
  })

  if not status then
    Logger.error(
      "Something went wrong trying to run command",
      { id = command_id, error = job }
    )
    state.running_command_job = nil
    return
  end

  state.running_command_job = job
end

-- Prompt the user to select an LLM command
--- @return nil
M.select_and_apply_command_or_accept_suggestion = function()
  if Suggestion.is_loading then return end

  if Suggestion.is_visible then
    Suggestion:apply()
  else
    TelescopeUtils.select({
      items = Commands:get_all_loaded_commands(),
      title = "Select a command:",
      onSelect = function(item) run_command(item.id) end,
    })
  end
end

--- @return SelectUIItemGroup[]
local build_main_menu_item_groups = function()
  local to_item = function(text) return { id = text, text = text } end

  return {
    {
      id = "keyboard",
      selected = Keyboard.get_active_mode(),
      items = TableUtils.imap(Keyboard.get_modes(), to_item),
    },
    {
      id = "backends",
      selected = Backend.get_active_backend(),
      items = TableUtils.imap(Backend.get_backend_names(), to_item),
    },
    {
      id = "models",
      selected = Backend.get_active_model(),
      items = TableUtils.imap(Backend.get_available_models(), to_item),
    },
  }
end

--- @class SetupOpts
--- @field backends? BackendServices
--- @field active_backend? BackendServiceName
--- @field active_model? string
--- @field modes? KeyboardModes
--- @field active_mode? KeyboardModeName

--- Deckr41 plugin main entry point
--- @param opts? SetupOpts
M.setup = function(opts)
  opts = opts or {}

  --
  -- Backends - Configure available backends and models
  --

  Backend.setup({
    backends = opts.backends,
    active_backend = opts.active_backend,
    active_model = opts.active_model,
  })

  --
  -- AI Commands - Scan and load commands from .d41rc or .d41rc.json files
  --

  Commands:load_all()

  NVimUtils.add_command("D41EjectDefaultCommands", {
    action = function() Commands:eject() end,
  })

  --
  -- Control Panel
  --

  local control_panel = SelectUI.build({
    title = config.emoji_title,
    items = build_main_menu_item_groups(),
    on_change = function(self, item)
      local backend = Backend.get_active_backend()
      local model = Backend.get_active_model()
      local keyboard_mode = Keyboard.get_active_mode()
      local somethig_changed = false

      if item.group_id == "backends" and backend ~= item.id then
        Backend.set_active_backend(item.id)
        somethig_changed = true
      elseif item.group_id == "models" and model ~= item.id then
        Backend.set_active_model(item.id)
        somethig_changed = true
      elseif item.group_id == "keyboard" and keyboard_mode ~= item.id then
        Keyboard.set_active_mode(item.id)
        somethig_changed = true
      end

      if somethig_changed == true then
        self.refresh(build_main_menu_item_groups())
      end
    end,
  })

  NVimUtils.add_command("D41OpenControlPanel", {
    action = control_panel.open,
    desc = config.emoji_title .. " | Open control panel",
  })

  NVimUtils.add_keymap("<leader>dp", {
    mode = "n",
    action = control_panel.open,
    desc = config.emoji_title .. " | Open control panel",
  })

  --
  -- Keyboard
  --

  Keyboard.setup({
    active_mode = opts.active_mode,
    modes = opts.modes or {},
    can_accept = function()
      return Suggestion:is_finished() and Suggestion.text ~= ""
    end,
    is_command_running = function() return state.running_command_job ~= nil end,
    on_command = run_command,
    on_accept = function() Suggestion:apply() end,
    on_refuse = function()
      if state.running_command_job then
        state.running_command_job:shutdown(41)
        state.running_command_job = nil
        Suggestion:reset_and_close()
      end
    end,
  })
end

return M
