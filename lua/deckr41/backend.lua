local Logger = require("deckr41.utils.loggr")("Backend")
local TableUtils = require("deckr41.utils.table")
local curl = require("plenary.curl")

--- @class BackendModule
local M = {}

--- @alias BackendServiceName "openai"|"anthropic"

--- @class BackendService
--- @field id BackendServiceName
--- @field url string
--- @field api_key ?string
--- @field default_model string
--- @field available_models table<string, { max_output_tokens: integer }>
--- @field temperature number

--- @alias BackendServices table<BackendServiceName, BackendService>

--- @type BackendServices
local config = {
  openai = {
    id = "openai",
    url = "https://api.openai.com/v1/chat/completions",
    api_key = os.getenv("OPENAI_API_KEY"),
    default_model = "gpt-4o-2024-08-06",
    -- https://platform.openai.com/docs/models/gpt-4o
    available_models = {
      -- High-intelligence flagship model for complex, multi-step tasks.
      -- GPT-4o is cheaper and faster than GPT-4 Turbo.
      ["gpt-4o"] = { max_output_tokens = 4096 },
      -- Latest snapshot that supports Structured Outputs
      ["gpt-4o-2024-08-06"] = { max_output_tokens = 16384 },
      -- Affordable and intelligent small model for fast, lightweight tasks.
      -- GPT-4o mini is cheaper and more capable than GPT-3.5 Turbo.
      ["gpt-4o-mini"] = { max_output_tokens = 16384 },
    },
    temperature = 0.2,
  },
  anthropic = {
    id = "anthropic",
    url = "https://api.anthropic.com/v1/messages",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
    default_model = "claude-3-5-sonnet-latest",
    available_models = {
      ["claude-3-5-sonnet-latest"] = { max_output_tokens = 8192 },
      ["claude-3-haiku"] = { max_output_tokens = 4096 },
    },
    temperature = 0.2,
  },
}

--- @class BackendState
--- @field active_backend ?BackendServiceName
--- @field active_model ?string
local state = {
  active_backend = nil,
  active_model = nil,
}

--- @class BackendSetupOpts
--- @field backends ?BackendServices
--- @field active_backend ?BackendServiceName
--- @field active_model ?string

--- @param opts BackendSetupOpts
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts.backends or {})
  state.active_backend = opts.active_backend
  state.active_model = opts.active_model

  -- Deep merge user defined config for each backend
  for backend_name, backend_config in pairs(opts.backends or {}) do
    if not config[backend_name] then
      Logger.error(
        "Invalid backend, accepted values are 'openai' and 'anthropic'.",
        { name = backend_name }
      )
      return
    end

    if not state.active_backend then state.active_backend = backend_name end
    config[backend_name] =
      vim.tbl_deep_extend("force", config[backend_name], backend_config)
  end

  -- If user did not set the active backend, try to autodetect
  if not state.active_backend then
    local env_to_backend = {
      { env_key = "ANTHROPIC_API_KEY", backend_name = "anthropic" },
      { env_key = "OPENAI_API_KEY", backend_name = "openai" },
    }

    for _, item in ipairs(env_to_backend) do
      if not state.active_backend and os.getenv(item.env_key) then
        state.active_backend = item.backend_name
      end
    end

    if not state.active_backend then
      Logger.error(
        "Backend not set. Please configure a backend or provide API keys for OpenAI or Anthropic."
      )
      return
    end
  end

  -- Check if backend is usable by checing it's API key
  if not config[state.active_backend].api_key then
    Logger.error(
      "API key not set for backend. Please set the API key in your configuration or as an environment variable.",
      { backend = state.active_backend }
    )
    return
  end

  -- If user did not set the active model, use backend's default model
  if not state.active_model then
    state.active_model = config[state.active_backend].default_model
  end

  -- Check if model is supported by the active backend
  if not config[state.active_backend].available_models[state.active_model] then
    Logger.error(
      "Model not supported by backend. Please choose a valid model.",
      {
        backend = state.active_backend,
        model = state.active_model or "nil",
        supported_models = vim.tbl_keys(
          config[state.active_backend].available_models
        ),
      }
    )
    return
  end

  Logger.debug("Backend successfully initialized", {
    active_backend = state.active_backend,
    active_model = state.active_model,
  })
end

--- @class PrepareOpenAIOpts
--- @field model string
--- @field system_prompt string
--- @field messages { role: string, content: string }[]
--- @field temperature number
--- @field max_output_tokens integer

-- Prepare request payload OpenAI request
---@param backend BackendService
---@param opts PrepareOpenAIOpts
---@return string
---@return table
---@return table
local prepare_openai_request = function(backend, opts)
  local headers = {
    ["Authorization"] = "Bearer " .. backend.api_key,
    ["Content-Type"] = "application/json",
  }

  local body = {
    messages = TableUtils.prepend(
      opts.messages,
      { role = "system", content = opts.system_prompt }
    ),
    model = opts.model,
    temperature = opts.temperature,
    stream = true,
    max_tokens = opts.max_output_tokens,
  }

  return backend.url, headers, body
end

--- @class PrepareAnthropicOpts
--- @field model string
--- @field system_prompt string
--- @field messages { role: string, content: string }[]
--- @field temperature number
--- @field max_output_tokens integer

-- Prepare request payload Anthropic request
---@param backend BackendService
---@param opts PrepareAnthropicOpts
---@return string
---@return table
---@return table
local prepare_anthropic_request = function(backend, opts)
  local headers = {
    ["x-api-key"] = backend.api_key,
    ["anthropic-version"] = "2023-06-01",
    ["Content-Type"] = "application/json",
  }

  local body = {
    system = opts.system_prompt,
    messages = opts.messages,
    model = opts.model,
    temperature = opts.temperature,
    stream = true,
    max_tokens = opts.max_output_tokens,
  }

  return backend.url, headers, body
end

--- @class PrepareRequestOpts
--- @field backend BackendService
--- @field model_name string
--- @field max_output_tokens ?integer
--- @field temperature ?number
--- @field system_prompt ?string
--- @field messages { role: string, content: string }[]

--- @param opts PrepareRequestOpts
--- @return string url
--- @return table headers
--- @return table body
local prepare_request = function(opts)
  local backend = opts.backend
  local model = backend.available_models[opts.model_name]
  local temperature = opts.temperature or backend.temperature
  local max_output_tokens =
    math.min(opts.max_output_tokens or math.huge, model.max_output_tokens)

  if backend.id == "openai" then
    return prepare_openai_request(backend, {
      model = opts.model_name,
      system_prompt = opts.system_prompt or "",
      messages = opts.messages,
      temperature = temperature,
      max_output_tokens = max_output_tokens,
    })
  end

  return prepare_anthropic_request(backend, {
    model = opts.model_name,
    system_prompt = opts.system_prompt or "",
    messages = opts.messages,
    temperature = temperature,
    max_output_tokens = max_output_tokens,
  })
end

--- @param backend_name BackendServiceName
--- @param data_chunk string
--- @return string
local extract_text_from_stream_data = function(backend_name, data_chunk)
  local json_chunk = data_chunk:match("^data: (.+)$")
  if json_chunk == "[DONE]" or json_chunk == nil then return "" end

  -- It can happen that curl closes prematurely if the user moves the cursor
  -- before the command finishes gracefully. This might leave unterminated
  -- text chunk and thus invalid JSON.
  local success, json_data = pcall(vim.fn.json_decode, json_chunk)

  -- The 2nd check is for Anthropic
  if not success or (json_data and json_data.type == "message_stop") then
    return ""
  end

  local result
  if backend_name == "openai" then
    result = TableUtils.deep_get(json_data, "choices", 1, "delta", "content")
  end
  if backend_name == "anthropic" then
    result = TableUtils.deep_get(json_data, "delta", "text")
  end

  return result or ""
end

--- @alias BackendOnStartCallback fun(config: { backend_name: string, model: string, temperature: number }): nil
--- @alias BackendOnDataCallback fun(chunk: string): nil
--- @alias BackendOnDoneCallback fun(response: string, http_status: number): nil
--- @alias BackendOnErrorCallback fun(response: { message: string, stderr: string, exit?: number }): nil

--- @class BackendAskOpts
--- @field max_output_tokens ?integer
--- @field temperature ?number
--- @field system_prompt ?string
--- @field messages { role: string, content: string }[]
--- @field on_start ?BackendOnStartCallback
--- @field on_data ?BackendOnDataCallback
--- @field on_done ?BackendOnDoneCallback
--- @field on_error ?BackendOnErrorCallback

--- @param opts BackendAskOpts
--- @return Job
M.ask = function(opts)
  local url, headers, body = prepare_request({
    backend = config[state.active_backend],
    model_name = state.active_model,
    max_output_tokens = opts.max_output_tokens,
    temperature = opts.temperature,
    system_prompt = opts.system_prompt,
    messages = opts.messages,
  })

  if opts.on_start then
    vim.schedule(
      function()
        opts.on_start({
          backend_name = state.active_backend,
          model = state.active_model,
          temperature = body.temperature,
        })
      end
    )
  end

  return curl.request({
    method = "POST",
    url = url,
    headers = headers,
    body = vim.fn.json_encode(body),
    on_error = function(response)
      if opts.on_error then
        vim.schedule(function() opts.on_error(response) end)
      end
    end,
    callback = function(response)
      if opts.on_done then
        vim.schedule(
          function() opts.on_done(response.body, response.status) end
        )
      end
    end,
    stream = function(_, chunk)
      if opts.on_data and chunk and chunk ~= "" then
        vim.schedule(
          function()
            opts.on_data(
              extract_text_from_stream_data(state.active_backend, chunk)
            )
          end
        )
      end
    end,
  })
end

--- @param name BackendServiceName
M.set_active_backend = function(name)
  if not config[name] then
    Logger.error("Invalid backend", { name = name or "nil" })
    return
  end
  state.active_backend = name
  state.active_model = config[name].default_model
end

--- @return BackendServiceName
M.get_active_backend = function() return state.active_backend end

--- @return BackendServiceName[]
M.get_backend_names = function() return vim.tbl_keys(config) end

--- @param name string
M.set_active_model = function(name)
  if not config[state.active_backend].available_models[name] then
    Logger.error("Invalid model for the active backend", {
      backend = state.active_backend,
      model = name,
      available_models = vim.tbl_keys(
        config[state.active_backend].available_models
      ),
    })
    return
  end
  state.active_model = name
end

--- @return string
M.get_active_model = function() return state.active_model end

--- @return string[]
M.get_available_models = function()
  return vim.tbl_keys(config[state.active_backend].available_models)
end

return M
