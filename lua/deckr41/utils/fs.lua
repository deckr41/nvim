local FnUtils = require("deckr41.utils.fn")
local Logger = require("deckr41.utils.loggr")("FSUtils")

--- @class FSUtils
local M = {}

--- Extract the folder from a file path
--- @param file_path string
--- @return string
M.get_folder_path = function(file_path)
  return vim.fn.fnamemodify(file_path, ":h")
end

--- @class FSWatchOpts
--- @field callback function
--- @field debounce_timeout integer?

--- Watch and react to file changes
--- @param file_path string
--- @param opts FSWatchOpts
M.watch = function(file_path, opts)
  local watch = vim.uv.new_fs_event()

  if not watch then
    Logger.error("Failed to create file system watcher", { path = file_path })
    return
  end

  local callback = nil
  if opts.debounce_timeout then
    callback = FnUtils.debounce(function() opts.callback(file_path) end)
  else
    callback = vim.schedule_wrap(function() opts.callback(file_path) end)
  end

  watch:start(file_path, {}, callback)
end

--- Predicate function for determining if file exists
---@param file_path string
---@return boolean
M.does_file_exist = function(file_path)
  return vim.uv.fs_stat(file_path) and true or false
end

--- Find all files mathching a name up the directory tree
--- @param opts {start_dir: string, match_files: string[]}
--- @return string[]
M.find_up_sync = function(opts)
  local match_files = opts.match_files
  local start_dir = opts.start_dir
  local files = {}

  --- Recursive function to scan up the tree
  --- @param dir string
  local function find_up(dir)
    for _, match_file in ipairs(match_files) do
      local file_path = dir .. "/" .. match_file
      if M.does_file_exist(file_path) then files[#files + 1] = file_path end
    end

    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent and parent ~= dir then find_up(parent) end
  end

  find_up(start_dir)

  return files
end

--- Read JSON file as a Lua table
--- @param file_path string
--- @return table
M.read_json = function(file_path)
  local file, err = io.open(file_path, "r")
  if not file then Logger.error("Failed to open file", { path = file_path }) end

  --- @type string
  local content = file:read("*a")
  file:close()

  return vim.fn.json_decode(content)
end

--- Absolute path where deckr41 plugin is installed
--- @return string
M.get_plugin_path = function()
  local init_path = vim.api.nvim_get_runtime_file("lua/deckr41/init.lua", false)

  return (init_path[1]:gsub("/lua/deckr41/init.lua$", ""))
end

--- Copy a file from one place to another
--- @param opts { from: string, to: string, should_overwrite?: boolean}
M.copy_file = function(opts)
  local from = opts.from
  local to = opts.to
  local should_overwrite = opts.should_overwrite or false

  if not should_overwrite and M.does_file_exist(to) then return end

  vim.uv.fs_copyfile(from, to)
end

--- Recursively search for files using `rg`
--- @param start_dir string
--- @param opts { match_file_names: string[] }
--- @return string[]
M.rg = function(start_dir, opts)
  local pattern = table.concat(opts.match_file_names, ",")
  local cmd = string.format("rg --files --glob '{%s}' %s", pattern, start_dir)

  local handle, error_msg = io.popen(cmd)
  if not handle then
    Logger.error("Something went wrong running `rg`", { rg = error_msg })
  end

  --- @type string
  local result = handle:read("*a")
  handle:close()

  local files = {}
  for file in result:gmatch("[^\r\n]+") do
    files[#files + 1] = file
  end
  return files
end

return M
