--- @class Logger
--- @field level "debug"|"info"|"warn"|"error"
--- @field namespace string
local M = {
  level = "info",
  namespace = "deckr41",
}

--- @param msg string
--- @param data any
--- @param hl_group string
local function log(msg, data, hl_group)
  local text = "[" .. M.namespace .. "] " .. msg
  if data then text = text .. " " .. vim.inspect(data) end

  vim.schedule(
    function() vim.api.nvim_echo({ { text, hl_group } }, true, {}) end
  )
end

--- @param msg string
--- @param data any
M.error = function(msg, data) log(msg, data, "ErrorMsg") end

--- @param msg string
--- @param data any
M.warn = function(msg, data) log(msg, data, "WarningMsg") end

--- @param msg string
--- @param data any
M.info = function(msg, data) log(msg, data, "Normal") end

--- @param msg string
--- @param data any
M.debug = function(msg, data)
  if M.level ~= "debug" then return end
  log(msg, data, "Normal")
end

--- @param level string
M.set_level = function(level) M.level = level end

return M
