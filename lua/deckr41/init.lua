--- Utilities imports
local Logger = require("deckr41.utils.logger") --- @type Logger
local StringUtils = require("deckr41.utils.string") --- @type StringUtils
local TableUtils = require("deckr41.utils.table") --- @type TableUtils
local TelescopeUtils = require("deckr41.utils.telescope") --- @type TelescopeUtils
local VimAPI = vim.api

--- Domain imports
local Backend = require("deckr41.backend") --- @type BackendModule
local Commands = require("deckr41.commands") --- @type CommandsModule
local Dashboard = require("deckr41.dashboard") --- @type Dashboard
local Keyboard = require("deckr41.keyboard") --- @type KeyboardModule
local Suggestion = require("deckr41.suggestion") --- @type SuggestionModule

--- @class Deckr41PluginState
--- @field running_command_job ?Job

--- @class Deckr41Plugin
--- @field state Deckr41PluginState
local M = {
  state = {
    -- Plenary Job of currently running command
    running_command_job = nil,
  },
}

---@param command_id string
local run_command = function(command_id)
  if M.state.running_command_job ~= nil then return end

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
    M.state.running_command_job = nil
    return
  end

  M.state.running_command_job = job
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

--- @class SetupOpts
--- @field backends ?BackendServices
--- @field active_backend ?BackendServiceName
--- @field active_model ?string
--- @field modes ?KeyboardModes
--- @field active_mode ?KeyboardModeName

--- Deckr41 plugin main entry point
--- @param opts ?SetupOpts
M.setup = function(opts)
  opts = opts or {}

  Backend.setup({
    backends = opts.backends,
    active_backend = opts.active_backend,
    active_model = opts.active_model,
  })

  -- Scan and load all .d41rc or .d41rc.json files
  Commands:load_all()

  -- Copy default commands into the user's cwd for convenient overwrites
  VimAPI.nvim_create_user_command(
    "D41Eject",
    function() Commands:eject() end,
    {}
  )

  Keyboard.setup({
    active_mode = opts.active_mode,
    modes = opts.modes or {},
    can_accept = function()
      return Suggestion:is_finished() and Suggestion.text ~= ""
    end,
    is_command_running = function() return M.state.running_command_job ~= nil end,
    on_command = run_command,
    on_accept = function() Suggestion:apply() end,
    on_refuse = function()
      if M.state.running_command_job then
        M.state.running_command_job:shutdown(41)
        M.state.running_command_job = nil
        Suggestion:reset_and_close()
      end
    end,
  })
end

return M
