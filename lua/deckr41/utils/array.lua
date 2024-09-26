--- @class ArrayUtils
local M = {}

--- @generic T
--- @param input T[]
--- @param predicate fun(item: T):boolean
--- @return T|nil
M.find_first = function(input, predicate)
  for _, value in ipairs(input) do
    if predicate(value) then return value end
  end
  return nil
end

--- @param list string|string[]
--- @param separator ?string
--- @return string
M.join = function(list, separator)
  separator = separator or "\n"
  if type(list) == "table" then return table.concat(list, separator) end
  return list
end

---
--- @generic T
--- @param a T[]
--- @param b T[]
--- @return T[]
M.concat = function(a, b)
  local result = {}
  for _, v in ipairs(a) do
    table.insert(result, v)
  end
  for _, v in ipairs(b) do
    table.insert(result, v)
  end
  return result
end

return M
