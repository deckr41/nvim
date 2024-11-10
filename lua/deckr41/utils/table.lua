--- @class TableUtils Domain agnostic table related pure primitives
local M = {}

--- Sort an array
--- @generic T
--- @param array T[]
--- @param opts? { should_mutate?: boolean, comparator?: fun(a: T, b: T): boolean }
--- @return T[]
M.sort = function(array, opts)
  opts = opts or {}
  local comparator = opts.comparator
  local should_mutate = opts.should_mutate ~= false

  if not should_mutate then array = vim.deepcopy(array) end

  table.sort(array, comparator)
  return array
end

--- Extract the values from a dictionary (named table) or array (indexed table)
--- and return them as an array (indexed table)
--- @generic T
--- @param table T[]|table<any, T>
--- @return T[]
M.values = function(table)
  local result = {}
  for _, value in pairs(table) do
    result[#result + 1] = value
  end
  return result
end

--- Concatenate arrays (indexed tables) with a decider function
--- @generic T
--- @param array_a T[] First array
--- @param array_b T[] Second array
--- @param opts { should_deepcopy?: boolean, fn: fun(item_a: T, item_b: T): T|nil }
--- @return T[]: Array with concatenated items from both arrays
M.concat_with = function(array_a, array_b, opts)
  local result_array = {}
  -- Copying tbl_a items into a dictionary (named table) for easier lookups
  for _, item_a in ipairs(array_a) do
    result_array[item_a.id] = opts.should_deepcopy and vim.deepcopy(item_a)
      or item_a
  end

  for _, item_b in ipairs(array_b) do
    local existing_item = result_array[item_b.id]
    local new_item_b = opts.should_deepcopy and vim.deepcopy(item_b) or item_b

    if existing_item then
      local negociated_item = opts.fn(existing_item, new_item_b)
      if negociated_item then result_array[item_b.id] = negociated_item end
    else
      result_array[item_b.id] = new_item_b
    end
  end

  return M.values(result_array)
end

--- Get a property deep in a table without triggering an error
--- @param tbl table|nil
--- @return any|nil
M.deep_get = function(tbl, ...)
  if type(tbl) ~= "table" then return nil end

  local keys = { ... }
  if #keys == 0 then return nil end

  local result = tbl
  for _, value in ipairs(keys) do
    if result[value] == nil then return nil end
    result = result[value]
  end

  return result
end

--- Add an item at the beginning of an array (indexed table)
--- @generic T
--- @param array T[] The array to which the item will be prepended
--- @param item T The item to prepend to the array
--- @return T[]: The mutated array
M.prepend = function(array, item)
  table.insert(array, 1, item)
  return array
end

--- Pick a set of fields from a dictionary (named table)
--- @generic V
--- @param dict table<string, V>
--- @param fields string[] Array (indexed table) of fields/keys to pick from the dictionary
--- @return table<string, V>: The dictionary with only the specified fields picked
M.pick = function(dict, fields)
  local result_dict = {}
  for _, field in ipairs(fields) do
    result_dict[field] = dict[field]
  end
  return result_dict
end

--- Map over a dictionary (named table) and transform its values
--- @generic K, V, M
--- @param dict table<K, V>
--- @param fn fun(value: V, key: K): M
--- @return table<K, M>
M.map = function(dict, fn)
  local result_dict = {}
  for key, value in pairs(dict) do
    result_dict[key] = fn(value, key)
  end
  return result_dict
end

--- Map over an array (indexed table) and transform its items
--- @generic K, V, M
--- @param array table<K, V>
--- @param func fun(item: V, original_key: K): M
--- @return M[]
M.imap = function(array, func)
  local result_array = {}
  for original_key, item in pairs(array) do
    result_array[#result_array + 1] = func(item, original_key)
  end
  return result_array
end

--- Calculate the max value of an array (indexed table) after applying a
--- `to_value_fn` function.
--- If the array is `nil` or empty, returns `nil`.
--- Skip elements by returning `nil` in `to_value_fn`.
--- @generic T
--- @param table table<any, T>
--- @param to_value_fn fun(item: T): number|nil
--- @return integer|nil
M.max_with = function(table, to_value_fn)
  local max_value = nil
  for _, item in pairs(table) do
    local value = to_value_fn(item)
    if value ~= nil then
      if max_value == nil or value > max_value then max_value = value end
    end
  end
  return max_value
end

---@generic T
---@param array T[]
---@param predicate fun(item: T): boolean
---@return T[]
M.filter = function(array, predicate)
  local result_array = {}
  for _, value in ipairs(array) do
    if predicate(value) then result_array[#result_array + 1] = value end
  end
  return result_array
end

---@generic T
---@param table T[]|table<string, T>
---@param predicate fun(item: T): boolean
---@return T|nil
M.find = function(table, predicate)
  for _, value in pairs(table) do
    if predicate(value) then return value end
  end
  return nil
end

--- Concatenate multiple arrays and table into one, left to right
--- @generic T
--- @param ... T[]|table<string, T>
--- @return T[]
M.concat = function(...)
  local result = {}
  local result_index = 1

  for _, array in pairs({ ... }) do
    for _, value in pairs(array) do
      result[result_index] = value
      result_index = result_index + 1
    end
  end

  return result
end

--- Get the number of elements in a table
--- @generic T
--- @param table T[]|table<string, T>?
--- @return integer
M.size = function(table)
  local size = 0
  for _, _ in pairs(table or {}) do
    size = size + 1
  end
  return size
end

--- @generic T, K, V
--- @param table table<K, V>
--- @param reducer fun(acc: T, value: V, key: K): T
--- @param initial_acc T
--- @return T
M.reduce = function(table, reducer, initial_acc)
  local result = initial_acc
  for key, value in pairs(table) do
    result = reducer(result, value, key)
  end
  return result
end

--- Check if sub_table is found within another table (dictionaries only)
--- @param sub_dict table<string, any> Table to match
--- @param dict table<string, any> Table to check against
--- @return boolean: True if `sub_table` matches sub_table
M.is_match = function(sub_dict, dict)
  if type(sub_dict) ~= "table" or type(dict) ~= "table" then return false end
  for k, v in pairs(sub_dict) do
    if dict[k] ~= v then return false end
  end
  return true
end

--- Test if at least one element in `table` matches the `sub_dict`
--- @param sub_dict table<string, any> Table to match
--- @param table table<string, table>|table[] Source table to iterate over
--- @return boolean: True if at least one element passes, otherwise false
M.any_with = function(sub_dict, table)
  if type(table) ~= "table" then return false end
  for _, element in pairs(table) do
    if type(element) == "table" and M.is_match(sub_dict, element) then
      return true
    end
  end
  return false
end

return M
