--- Utilities imports
local Logger = require("deckr41.utils.loggr")("Commands")
local StringUtils = require("deckr41.utils.string")
local WindowUtils = require("deckr41.utils.window")

--- Domain imports
local Backend = require("deckr41.backend")
local RCNodes = require("deckr41.rc-nodes")

--- @class Commands
local M = {}

--- Expose necessary functions from RCNodes
M.setup = RCNodes.load_all
M.find = RCNodes.find_command
M.find_nodes = RCNodes.find_path
M.eject_defaults = RCNodes.eject_internal_rc

--- @class CommandData
--- @field prompt string
--- @field system_prompt? string

--- @class CommandsCompileOpts
--- @field win_id integer
--- @field cursor integer[]
--- @field range? integer[]
--- @field extra_vars? table<string, string>

--- Compile the command's prompts by interpolating variables.
--- @param data CommandData Table containing 'prompt' and optional 'system_prompt'.
--- @param opts CommandsCompileOpts Options for compilation.
--- @return string|nil system_prompt The compiled system prompt (if any).
--- @return string prompt The compiled prompt.
function M.compile(data, opts)
  -- Detect and extract variables from the combined prompts
  local combined_prompts = (data.system_prompt or "") .. data.prompt
  local variable_names = StringUtils.find_variable_names(combined_prompts)
  local variables = WindowUtils.get_metadata(variable_names, {
    win_id = opts.win_id,
    cursor = opts.cursor,
    range = opts.range,
  })

  -- Inject context
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
--- @field range? integer[]
--- @field on_start? fun(config: table): nil
--- @field on_data? fun(chunk: string): nil
--- @field on_done? fun(response: string, http_status: number): nil
--- @field on_error? fun(response: table): nil

--- Run a command by compiling and sending it to the backend.
--- @param command_id RCCommandID The ID of the command to run.
--- @param opts CommandsRunOpts Options for running the command.
--- @return Job|nil The job running the command, or nil if an error occurred.
function M.run(command_id, opts)
  local command = RCNodes.get_command(command_id)
  if not command then
    Logger.error("Command not found.", { command_id = command_id })
  end

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

  local system_prompt, prompt = M.compile({
    prompt = command.prompt,
    system_prompt = command.system_prompt,
  }, {
    win_id = opts.win_id,
    cursor = opts.cursor,
    range = opts.range,
    extra_vars = parameters,
  })

  local success, job_or_error = pcall(Backend.ask, {
    system_prompt = system_prompt,
    max_tokens = command.max_tokens,
    temperature = command.temperature,
    messages = {
      { role = "user", content = prompt },
    },
    on_start = opts.on_start,
    on_data = function(chunk)
      if chunk and chunk ~= "" and opts.on_data then opts.on_data(chunk) end
    end,
    on_error = opts.on_error,
    on_done = opts.on_done,
  })

  if not success then
    Logger.error(
      "Failed to run command.",
      { command_id = command_id, error = job_or_error }
    )
    return nil
  end

  return job_or_error
end

return M
