--- @class ArrayUtils
local M = {}

--- Find the first element in an array (indexed table) that satisfies
--- the `is_the_one` predicate function.
--- @generic T
--- @param haystack_array T[] The array to iterate over.
--- @param is_the_one fun(needle: T): boolean A function that checks if an element is found.
--- @return T|nil: The first element found, otherwise `nil`.
M.find_first = function(haystack_array, is_the_one)
  for _, straw in ipairs(haystack_array) do
    if is_the_one(straw) then return straw end
  end
  return nil
end

--- Get the first element in an array (indexed table) that satisfies
--- the `is_the_one` predicate function.
---
--- Similar to `find_first`, but throws an error if no element found.
--- @generic T
--- @param haystack_array T[] The array to iterate over.
--- @param is_the_one fun(needle: T): boolean A function that checks if an element is found.
--- @return T: The first element found, otherwise throw.
M.get_first = function(haystack_array, is_the_one)
  for _, straw in ipairs(haystack_array) do
    if is_the_one(straw) then return straw end
  end
  error("Element not found")
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

--- Reverse the order of items in an array (indexed table).
--- @generic T
--- @param array T[]
--- @param opts? { should_mutate?: boolean }
--- @return T[]
M.reverse = function(array, opts)
  opts = opts or {}
  local size = #array

  if opts.should_mutate then
    for i = 1, math.floor(size / 2) do
      array[i], array[size - i + 1] = array[size - i + 1], array[i]
    end
    return array
  else
    local new_array = {}
    for i = 1, size, 1 do
      new_array[i] = array[size - i + 1]
    end
    return new_array
  end
end

--- Reverse the order of items in an array (indexed table).
--- @generic T
--- @param array T[]
--- @return integer|nil
M.get_index = function(item, array)
  for index, value in ipairs(array) do
    if value == item then return index end
  end
  return nil
end

return M
