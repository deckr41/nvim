--- @class StringUtils
local M = {}

---@param input string
---@param vars table<string, any>
---@return string
M.interpolate = function(input, vars)
  local output = input
  for key, value in pairs(vars) do
    local serialized_value = value
    if type(value) ~= "string" then serialized_value = vim.inspect(value) end
    output = output:gsub("{{" .. key .. "}}", serialized_value)
  end
  return output
end

return M
