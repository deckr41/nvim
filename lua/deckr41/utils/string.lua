--- @class StringUtils
local M = {}

--- @param input string
--- @param vars table<string, any>
--- @return string
M.interpolate = function(input, vars)
  local output = input
  for key, value in pairs(vars) do
    local serialized_value = value
    if type(value) ~= "string" then serialized_value = vim.inspect(value) end
    output = output:gsub("{{" .. key .. "}}", serialized_value)
  end
  return output
end

--- Extract all varible names from a string.
--- Variables are referenced using the {{ VAR_NAME }} syntax.
--- @param input string
--- @return string[]
M.find_variable_names = function(input)
  local names_array = {}
  for var_name in input:gmatch("{{%s*([%w_.]+)%s*}}") do
    if not vim.tbl_contains(names_array, var_name) then
      names_array[#names_array + 1] = var_name
    end
  end
  return names_array
end

--- @param input string
--- @return string
M.escape_for_gsub = function(input)
  local escaped_string = (input or ""):gsub(
    "([%-%^%$%(%)%%%.%[%]%*%+%-%?])",
    "%%%1"
  )
  return escaped_string
end

--- Predicate function checking if a string starts with another string
--- @param str string
--- @param prefix string
--- @return boolean
M.starts_with = function(str, prefix) return str:sub(1, #prefix) == prefix end

--- Get longest line in terms of visible characters
--- @param input string|string[]
--- @return integer
M.max_line_length = function(input)
  local length = 0
  local lines = input
  if type(lines) == "string" then lines = vim.split(lines, "\n") end

  for _, line in ipairs(lines) do
    local line_length = vim.fn.strdisplaywidth(line)
    if line_length > length then length = line_length end
  end
  return length
end

return M
