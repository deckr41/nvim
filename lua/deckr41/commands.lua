--- Utilities imports
local Logger = require("deckr41.utils.loggr")("Commands")
local StringUtils = require("deckr41.utils.string")
local WindowUtils = require("deckr41.utils.window")

--- Domain imports
local Backend = require("deckr41.backend")
local RCNodes = require("deckr41.rc-nodes")

--- @class Commands
local M = {}

M.setup = RCNodes.load_all

M.find = RCNodes.find_command

M.find_nodes = RCNodes.find_path

M.eject_defaults = RCNodes.eject_internal_rc

--- @class CommandsCompileOpts
--- @field win_id integer
--- @field cursor integer[]
--- @field range ?integer[]
--- @field extra_vars ?table<string, string>

--- @param data { prompt: string, system_prompt?: string }
--- @param opts CommandsCompileOpts
--- @return string|nil: Compiled command system_prompt
--- @return string: Compiled command prompt
M.compile = function(data, opts)
  local variable_names =
    StringUtils.find_variable_names(data.system_prompt .. data.prompt)
  local variables = WindowUtils.get_metadata(variable_names, {
    win_id = opts.win_id,
    cursor = opts.cursor,
    range = opts.range,
  })
  local context = vim.tbl_extend("force", variables, opts.extra_vars or {})

  local prompt = StringUtils.interpolate(data.prompt, context)
  local system_prompt = data.system_prompt
      and StringUtils.interpolate(data.system_prompt, context)
    or nil

  return system_prompt, prompt
end

--- @class CommandsRunOpts
--- @field win_id integer
--- @field cursor integer[]
--- @field range ?integer[]
--- @field on_start BackendOnStartCallback
--- @field on_data BackendOnDataCallback
--- @field on_done BackendOnDoneCallback
--- @field on_error BackendOnErrorCallback

--- @param command_id RCCommandID
--- @param opts CommandsRunOpts
--- @return Job
M.run = function(command_id, opts)
  local command = RCNodes.get_command(command_id)

  -- Ask user's input
  local parameters = {}
  if command.parameters then
    for param_name, param in pairs(command.parameters) do
      local value = param.default
      if param.type == "textarea" then
        value = vim.fn.input((param.label or param_name) .. ": ")
      end
      parameters["PARAMETERS." .. param_name] = value
    end
  end

  -- Extract and inject variable names from command prompts
  local variable_names =
    StringUtils.find_variable_names(command.system_prompt .. command.prompt)

  local variables = WindowUtils.get_metadata(variable_names, {
    win_id = opts.win_id,
    cursor = opts.cursor,
    range = opts.range,
  })

  local context = vim.tbl_extend("force", variables, parameters)
  local prompt = StringUtils.interpolate(command.prompt, context)
  local system_prompt = command.system_prompt
      and StringUtils.interpolate(command.system_prompt, context)
    or nil

  -- Send the compiled prompts to the currently selected backend
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
    on_start = opts.on_start,
    on_data = opts.on_data,
    on_done = opts.on_done,
    on_error = opts.on_error,
  })

  if not status then
    Logger.error(
      "Something went wrong trying to run command",
      { opts = command_id, error = job }
    )
  end

  return job
end

return M
