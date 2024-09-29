--- Utilities imports
local Logger = require("deckr41.utils.logger") --- @type Logger
local StringUtils = require("deckr41.utils.string") --- @type StringUtils
local TelescopeUtils = require("deckr41.utils.telescope") --- @type TelescopeUtils
local VimAPI = vim.api

--- Domain imports
local Backend = require("deckr41.backend") --- @type BackendModule
local Commands = require("deckr41.commands") --- @type CommandsModule
local Keyboard = require("deckr41.keyboard") --- @type KeyboardModule
local Suggestion = require("deckr41.suggestion") --- @type SuggestionModule

--- @class ConfigModule
--- @field backends ?table<BackendServiceNames, BackendService>
--- @field active_backend ?BackendServiceNames
--- @field active_model ?string
--- @field modes ?KeyboardModes
--- @field active_mode ?KeyboardModeName

--- @class Deckr41PluginState
--- @field running_command_job ?Job

--- @class Deckr41Plugin
--- @field config ?ConfigModule
--- @field state Deckr41PluginState
local M = {
  config = {
    -- backends = nil,
    -- active_backend = "anthropic",
    -- active_model = nil,
  },
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

  M.state.running_command_job = Backend:ask(M.config.active_backend, {
    model = M.config.active_model,
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

--- Configure available backends
--- @param backend_configs ?table<string, BackendService>
local setup_backends = function(backend_configs)
  if not backend_configs then return end

  for backend_name, backend_config in pairs(backend_configs) do
    if not Backend:is_backend_supported(backend_name) then
      Logger.error(
        "Invalid backend, accepted values are 'openai' and 'anthropic'.",
        { name = backend_name }
      )
    else
      if not M.config.active_backend then
        M.config.active_backend = backend_name
      end
      Backend:set_config(backend_name, backend_config)
    end
  end
end

--- Main plugin entry point
--- @param opts ?ConfigModule
M.setup = function(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, {}, opts)

  setup_backends(M.config.backends)

  if not M.config.active_backend then
    -- Prioritize Anthropic
    if os.getenv("ANTHROPIC_API_KEY") then
      M.config.active_backend = "anthropic"
    elseif os.getenv("OPENAI_API_KEY") then
      M.config.active_backend = "openai"
    else
      Logger.error("No active backend specified and no API keys found.")
    end
  end

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
