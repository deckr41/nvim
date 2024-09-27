local TableUtils = require("deckr41.utils.table") --- @class TableUtils
local curl = require("plenary.curl")

--- @alias BackendServiceNames "openai"|"anthropic"

--- @class BackendService
--- @field name string
--- @field url string
--- @field api_key ?string
--- @field default_model string
--- @field available_models table<string, { max_tokens: integer }>
--- @field temperature number

--- @class BackendModule
--- @field openai BackendService
--- @field anthropic BackendService
local M = {
  openai = {
    name = "OpenAI",
    url = "https://api.openai.com/v1/chat/completions",
    api_key = os.getenv("OPENAI_API_KEY"),
    default_model = "gpt-4o-mini",
    -- https://platform.openai.com/docs/models/gpt-4o
    available_models = {
      -- High-intelligence flagship model for complex, multi-step tasks.
      -- GPT-4o is cheaper and faster than GPT-4 Turbo.
      ["gpt-4o"] = { max_tokens = 4096 },
      -- Latest snapshot that supports Structured Outputs
      ["gpt-4o-2024-08-06"] = { max_tokens = 16384 },
      -- Affordable and intelligent small model for fast, lightweight tasks.
      -- GPT-4o mini is cheaper and more capable than GPT-3.5 Turbo.
      ["gpt-4o-mini"] = { max_tokens = 16384 },
    },
    temperature = 0.2,
  },
  anthropic = {
    name = "Anthropic",
    url = "https://api.anthropic.com/v1/messages",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
    default_model = "claude-3-5-sonnet-20240620",
    available_models = {
      ["claude-3-5-sonnet-20240620"] = { max_tokens = 1024 },
    },
    temperature = 0.2,
  },
}

-- Prepare request payload OpenAI request
---@param backend BackendService
---@param opts BackendAskOpts
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
    max_tokens = opts.max_tokens,
  }

  return backend.url, headers, body
end

-- Prepare request payload Anthropic request
---@param backend BackendService
---@param opts BackendAskOpts
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
    max_tokens = opts.max_tokens,
  }

  return backend.url, headers, body
end

--- @class BackendAskOpts
--- @field max_tokens ?integer
--- @field temperature ?number
--- @field system_prompt ?string
--- @field model string
--- @field messages { role: string, content: string }[]
--- @field on_start ?fun(config: { backend_name: string, model: string, temperature: number }): nil
--- @field on_data ?fun(chunk: string): nil
--- @field on_done ?fun(response: string, http_status: number): nil
--- @field on_error ?fun(response: { message: string, stderr: string, exit?: number}): nil

--- @param self BackendModule
--- @param name BackendServiceNames
--- @param opts BackendAskOpts
--- @return string url
--- @return table headers
--- @return table body
local prepare_request = function(self, name, opts)
  local backend = self[name]
  local model_name = opts.model or backend.default_model
  local model = backend.available_models[model_name]
  local temperature = opts.temperature or backend.temperature
  local max_tokens = math.min(opts.max_tokens or math.huge, model.max_tokens)

  if name == "openai" then
    return prepare_openai_request(backend, {
      system_prompt = opts.system_prompt or "",
      messages = opts.messages,
      model = model_name,
      temperature = temperature,
      max_tokens = max_tokens,
    })
  elseif name == "anthropic" then
    return prepare_anthropic_request(backend, {
      system_prompt = opts.system_prompt or "",
      messages = opts.messages,
      model = model_name,
      temperature = temperature,
      max_tokens = max_tokens,
    })
  else
    error("Unsupported backend: " .. name)
  end
end

--- @param backend_name BackendServiceNames
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

--- @param name BackendServiceNames
--- @param opts BackendAskOpts
--- @return Job
function M:ask(name, opts)
  local url, headers, body = prepare_request(self, name, opts)

  if opts.on_start then
    vim.schedule(
      function()
        opts.on_start({
          backend_name = name,
          model = body.model,
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
          function() opts.on_data(extract_text_from_stream_data(name, chunk)) end
        )
      end
    end,
  })
end

--- Update internal configs for a specific backend
--- @param name BackendServiceNames
--- @param config table
function M:set_config(name, config)
  self[name] = vim.tbl_deep_extend("force", self[name], config)
end

--- Predicate checking if a backend service is defined
--- @param name string
--- @return boolean
function M:is_backend_supported(name) return self[name] ~= nil end

--- Predicate checking if a model is supported by a backend
--- @param opts { backend: BackendServiceNames, model: string }
--- @return boolean
function M:is_model_supported(opts)
  if not opts.model then return false end
  if not opts.backend then return false end
  if not self[opts.backend] then return false end
  return self[opts.backend].available_models[opts.model] ~= nil
end

--- Predicate checking if a backend service is active/usable
--- @param name string
--- @return boolean
function M:is_backend_usable(name)
  return self[name] ~= nil and self[name].api_key ~= nil
end

return M
