--- @class Logger
local Logger = require("deckr41.utils.logger")

--- @class TableUtils
local M = {}

-- Function to concatenate arrays with a predicate callback
--- @param a table First array
--- @param b table Second array
--- @param predicate_callback function Predicate function that takes an item and seen_ids table
--- @return table Concatenated array
M.concat_with = function(a, b, predicate_callback)
  local result = vim.deepcopy(a)
  local seen_ids = {}

  for _, item in ipairs(a) do
    seen_ids[item.id] = true
  end

  for _, item in ipairs(b) do
    if predicate_callback(item, seen_ids) then
      result[item.id] = item
      seen_ids[item.id] = true
    else
      table.insert(result, item)
    end
  end

  return result
end

-- Merge two tables
--- @param a table First table
--- @param b table Second table
--- @return table Merged table
M.merge = function(a, b)
  local result = vim.deepcopy(a)
  for k, v in pairs(b) do
    result[k] = v
  end
  return result
end

--- Extend a table with another
--- @param a table First table
--- @param b table Second table
M.deep_extend = function(a, b)
  local result = a
  for k, v in pairs(b) do
    if type(v) == "table" and type(result[k] or false) == "table" then
      result[k] = M.deep_extend(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

--- Get a property deep in a table without triggering an error.
--- @param input table|nil
--- @return any|nil
M.deep_get = function(input, ...)
  if type(input) ~= "table" then return nil end

  local keys = { ... }
  if #keys == 0 then return nil end

  local result = input
  for _, value in ipairs(keys) do
    if result[value] == nil then return nil end
    result = result[value]
  end

  return result
end

--- Extract the values from a named table and return them as an indexed table
--- @generic T
--- @param input table<any, T>
--- @return T[]
M.values = function(input)
  local result = {}
  for _, v in pairs(input) do
    table.insert(result, v)
  end
  return result
end

--- Add an item at the beginning of a table
--- @generic T
--- @param list T[]: The list to which the item will be prepended
--- @param item T: The item to prepend to the list
--- @return T[]: The modified/mutated list
M.prepend = function(list, item)
  table.insert(list, 1, item)
  return list
end

--- Pick a set of fields from a given table
--- @generic T: table
--- @param list T
--- @param fields string[]
--- @return T
M.pick = function(list, fields)
  local result = {}
  for _, field in ipairs(fields) do
    result[field] = list[field]
  end
  return result
end

return M
