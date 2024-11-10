local Logger = require("deckr41.utils.loggr")("Backend")
local TableUtils = require("deckr41.utils.table")
local curl = require("plenary.curl")

--- @class BackendModule
local M = {}

--- @alias BackendServiceName "openai"|"anthropic"

--- @class BackendService
--- @field id BackendServiceName
--- @field url string
--- @field api_key? string
--- @field default_model string
--- @field available_models table<string, { max_output_tokens: integer }>
--- @field temperature number

--- @alias BackendServices table<BackendServiceName, BackendService>

--- Default backend configurations.
--- @type BackendServices
local config = {
  openai = {
    id = "openai",
    url = "https://api.openai.com/v1/chat/completions",
    api_key = os.getenv("OPENAI_API_KEY"),
    default_model = "gpt-4o",
    available_models = {
      ["gpt-4o"] = { max_output_tokens = 16384 },
      ["gpt-4o-mini"] = { max_output_tokens = 16384 },
      ["chatgpt-4o-latest"] = { max_output_tokens = 16384 },
      ["o1-mini"] = { max_output_tokens = 65536 },
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
      ["claude-3-5-haiku-latest"] = { max_output_tokens = 8192 },
    },
    temperature = 0.2,
  },
}

--- Internal state of the backend module.
--- @class BackendState
local state = {
  active_backend = nil, --- @type BackendServiceName?
  active_model = nil, --- @type string?
}

--- Detect the active backend based on environment variables.
--- Anthropic takes precedence.
--- @return BackendServiceName?
local function detect_active_backend()
  local env_backends = {
    { env_key = "ANTHROPIC_API_KEY", backend_name = "anthropic" },
    { env_key = "OPENAI_API_KEY", backend_name = "openai" },
  }
  for _, item in ipairs(env_backends) do
    if os.getenv(item.env_key) then return item.backend_name end
  end
  return nil
end

--- Backend setup options.
--- @class BackendSetupOpts
--- @field backends? BackendServices
--- @field active_backend? BackendServiceName
--- @field active_model? string

--- Initialize the backend module with user options.
--- @param opts BackendSetupOpts
function M.setup(opts)
  opts = opts or {}

  -- Merge user-defined backends into the default config.
  if opts.backends then
    for backend_name, backend_config in pairs(opts.backends) do
      if not config[backend_name] then
        Logger.error(
          "Invalid backend. Accepted values are 'openai' and 'anthropic'.",
          { name = backend_name }
        )
      end
      config[backend_name] =
        vim.tbl_deep_extend("force", config[backend_name], backend_config)
    end
  end

  -- Set active backend and model from user options.
  state.active_backend = opts.active_backend
  state.active_model = opts.active_model

  -- Validate the explicitly set active backend.
  if state.active_backend and not config[state.active_backend] then
    Logger.error("Backend is not supported.", {
      backend = state.active_backend,
      supported_backends = vim.tbl_keys(config),
    })
  end

  -- Auto-detect the active backend if not explicitly set.
  if not state.active_backend then
    state.active_backend = detect_active_backend()
    if not state.active_backend then
      Logger.error(
        "Could not autodetect backend. No API keys found for supported backends."
      )
    end
  end

  -- Ensure the API key is set for the active backend.
  if not config[state.active_backend].api_key then
    Logger.error(
      "API key not set for backend.",
      { backend = state.active_backend }
    )
  end

  -- Set the active model to the default if not explicitly set.
  if not state.active_model then
    state.active_model = config[state.active_backend].default_model
  end

  -- Validate the active model for the active backend.
  if not config[state.active_backend].available_models[state.active_model] then
    Logger.error("Model not supported by backend.", {
      backend = state.active_backend,
      model = state.active_model or "nil",
      supported_models = vim.tbl_keys(
        config[state.active_backend].available_models
      ),
    })
  end

  Logger.debug("Backend successfully initialized.", {
    active_backend = state.active_backend,
    active_model = state.active_model,
  })
end

--- Prepare the request payload for OpenAI.
--- @param backend BackendService
--- @param opts table
--- @return string url, table headers, table body
local function prepare_openai_request(backend, opts)
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

--- Prepare the request payload for Anthropic.
--- @param backend BackendService
--- @param opts table
--- @return string url, table headers, table body
local function prepare_anthropic_request(backend, opts)
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

--- Prepare the request based on the backend.
--- @param opts table
--- @return string url, table headers, table body
local function prepare_request(opts)
  local backend = opts.backend
  local model_info = backend.available_models[opts.model_name]
  local temperature = opts.temperature or backend.temperature
  local max_output_tokens =
    math.min(opts.max_output_tokens or math.huge, model_info.max_output_tokens)

  local request_opts = {
    model = opts.model_name,
    system_prompt = opts.system_prompt or "",
    messages = opts.messages,
    temperature = temperature,
    max_output_tokens = max_output_tokens,
  }

  if backend.id == "openai" then
    return prepare_openai_request(backend, request_opts)
  else
    return prepare_anthropic_request(backend, request_opts)
  end
end

--- Extract text from streamed data chunks.
--- @param backend_name BackendServiceName
--- @param data_chunk string
--- @return string
local function extract_text_from_stream_data(backend_name, data_chunk)
  local json_chunk = data_chunk:match("^data: (.+)$")
  if json_chunk == "[DONE]" or not json_chunk then return "" end

  -- It can happen that curl closes prematurely if the user moves the cursor
  -- before the command finishes gracefully. This might leave unterminated
  -- text chunk and thus invalid JSON.
  local success, json_data = pcall(vim.fn.json_decode, json_chunk)

  -- The 2nd check is for Anthropic
  if not success or (json_data and json_data.type == "message_stop") then
    return ""
  end

  if backend_name == "openai" then
    return TableUtils.deep_get(json_data, "choices", 1, "delta", "content")
      or ""
  elseif backend_name == "anthropic" then
    return TableUtils.deep_get(json_data, "delta", "text") or ""
  end

  return ""
end

--- @class BackendAskOpts
--- @field max_output_tokens? integer
--- @field temperature? number
--- @field system_prompt? string
--- @field messages table[]
--- @field on_start? fun(config: table): nil
--- @field on_data? fun(chunk: string): nil
--- @field on_done? fun(response: string, http_status: number): nil
--- @field on_error? fun(response: table): nil

--- Send a request to the active backend.
--- @param opts BackendAskOpts
--- @return Job
function M.ask(opts)
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

--- Set the active backend.
--- @param name BackendServiceName
function M.set_active_backend(name)
  if not config[name] then
    Logger.error("Invalid backend.", { name = name or "nil" })
  end
  state.active_backend = name
  state.active_model = config[name].default_model
end

--- Get the active backend.
--- @return BackendServiceName?
function M.get_active_backend() return state.active_backend end

--- Get all available backend names.
--- @return BackendServiceName[]
function M.get_backend_names() return vim.tbl_keys(config) end

--- Set the active model for the current backend.
--- @param name string
function M.set_active_model(name)
  local backend = config[state.active_backend]
  if not backend.available_models[name] then
    Logger.error("Invalid model for the active backend.", {
      backend = state.active_backend,
      model = name,
      available_models = vim.tbl_keys(backend.available_models),
    })
  end
  state.active_model = name
end

--- Get the active model.
--- @return string?
function M.get_active_model() return state.active_model end

--- Get available models for the active backend.
--- @return string[]
function M.get_available_models()
  local backend = config[state.active_backend]
  return vim.tbl_keys(backend.available_models)
end

return M
