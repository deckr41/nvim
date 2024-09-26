local uv = vim.loop

--- @class FSUtils
local M = {}

-- Predicate function for determining if file exists
---@param file_path string
---@return boolean
M.does_file_exist = function(file_path)
  return uv.fs_stat(file_path) and true or false
end

-- Find all files mathching a name up the directory tree
--- @param opts {start_dir: string, match_files: string[]}
--- @return table<number, string>
M.find_up_sync = function(opts)
  local match_files = opts.match_files
  local start_dir = opts.start_dir
  local files = {}

  -- Recursive function to scan up the tree
  --- @param dir string
  local function find_up(dir)
    for _, match_file in ipairs(match_files) do
      local file_path = dir .. "/" .. match_file
      if M.does_file_exist(file_path) then table.insert(files, file_path) end
    end

    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent and parent ~= dir then find_up(parent) end
  end

  find_up(start_dir)

  return files
end

-- Translate JSON file to a Lua table
--- @param file_path string Absolute path to the JSON file
--- @return table|nil
M.read_json_as_table = function(file_path)
  local file, err = io.open(file_path, "r")

  if not file then error("Failed to open file: " .. err) end

  --- @type string
  local content = file:read("*a")
  file:close()

  return vim.fn.json_decode(content)
end

--- Absolute path to where deckr41 plugin is installed
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

  uv.fs_copyfile(from, to)
end

return M
