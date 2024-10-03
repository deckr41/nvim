--- @class ArrayUtils
local M = {}

--- Find the first element in an array (indexed table) that satisfies
--- the predicate function.
--- @generic T
--- @param array T[]
--- @param predicate fun(item: T): boolean
--- @return T|nil
M.find_first = function(array, predicate)
  for _, value in ipairs(array) do
    if predicate(value) then return value end
  end
  return nil
end

--- Join the elements of an array (indexed table) into a single string,
--- using the specified separator.
--- @param array string|string[]
--- @param separator ?string
--- @return string
M.join = function(array, separator)
  separator = separator or "\n"
  if type(array) == "table" then return table.concat(array, separator) end
  return array
end

--- Combine multiple arrays (indexed tables) into a single array.
--- @generic T
--- @param array_a T[]
--- @param array_b T[]
--- @return T[]
M.concat = function(array_a, array_b)
  local result_array = {}

  for _, v in ipairs(array_a) do
    result_array[#result_array + 1] = v
  end
  for _, v in ipairs(array_b) do
    result_array[#result_array + 1] = v
  end

  return result_array
end

return M
