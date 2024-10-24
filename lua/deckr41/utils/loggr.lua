--- @alias LoggerLevel "debug"|"info"|"warn"|"error"

--- Mapping log level to its priority.
--- @type table<LoggerLevel, integer>
local LEVEL_PRIORITY = { debug = 1, info = 2, warn = 3, error = 4 }

--- Factory function creating new instances of message loggers with different
--- levels and namespaces.
--- @param namespace string?
--- @return LoggerInstance
local M = function(namespace)
  --- @class LoggerInstance
  local instance = {}

  --- @class LoggerState
  --- @field level LoggerLevel
  --- @field namespace string
  local state = {
    level = "info",
    namespace = namespace and "D41:" .. namespace or "D41",
  }

  --- Determines if a message should be printed based on the current logging level.
  --- @param level LoggerLevel
  --- @return boolean
  local function should_log(level)
    return LEVEL_PRIORITY[level] >= LEVEL_PRIORITY[state.level]
  end

  --- Prepares a log message with the specified message and optional data.
  --- @param msg string
  --- @param data any
  --- @return string
  local function prepare_message(msg, data)
    local text = "[" .. state.namespace .. "] " .. msg
    if data then text = text .. " " .. vim.inspect(data) end
    return text
  end

  --- Logs an error message and stops execution.
  --- @param msg string
  --- @param data any
  function instance.error(msg, data)
    local text = prepare_message(msg, data)
    vim.api.nvim_echo({ { text, "ErrorMsg" } }, true, {})
    error(msg, 2)
  end

  --- Logs a warning message if the logging level allows it.
  --- @param msg string
  --- @param data any
  function instance.warn(msg, data)
    if not should_log("warn") then return end
    local text = prepare_message(msg, data)
    vim.api.nvim_echo({ { text, "WarningMsg" } }, true, {})
  end

  --- Logs an info message if the logging level allows it.
  --- @param msg string
  --- @param data any
  function instance.info(msg, data)
    if not should_log("info") then return end
    local text = prepare_message(msg, data)
    vim.api.nvim_echo({ { text, "Normal" } }, true, {})
  end

  --- Logs a debug message if the logging level allows it.
  --- @param msg string
  --- @param data any
  function instance.debug(msg, data)
    if not should_log("debug") then return end
    local text = prepare_message(msg, data)
    vim.api.nvim_echo({ { text, "Normal" } }, true, {})
  end

  --- Sets the logging level.
  --- @param level LoggerLevel
  function instance.set_level(level) state.level = level end

  return instance
end

return M
