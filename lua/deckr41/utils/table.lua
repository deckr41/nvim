local Logger = require("deckr41.utils.logger") --- @class Logger

--- @class TableUtils
local M = {}

--- Extract the values from a dictionary (named table) and return them as
--- an array (indexed table)
--- @generic T
--- @param dict table<any, T>
--- @return T[]
M.values = function(dict)
  local result_array = {}
  for _, value in pairs(dict) do
    result_array[#result_array + 1] = value -- More efficient than table.insert in a loop
  end
  return result_array
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
--- @param func fun(item: V, index: K): M
--- @return M[]
M.imap = function(array, func)
  local result_array = {}
  for index, item in ipairs(array) do
    result_array[index] = func(item, index)
  end
  return result_array
end

--- Calculate the max value of an array (indexed table) after applying a function.
--- If the array is nil or empty, returns `nil`
--- @generic T
--- @param array T[]
--- @param fn fun(item: T): number
--- @return integer|nil
M.max_with = function(array, fn)
  if not array or #array == 0 then return nil end
  array = M.imap(array, fn)

  return math.max(unpack(array))
end

return M
