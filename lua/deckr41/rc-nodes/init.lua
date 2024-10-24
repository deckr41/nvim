--- Utilities imports
local ArrayUtils = require("deckr41.utils.array")
local FSUtils = require("deckr41.utils.fs")
local Logger = require("deckr41.utils.loggr")("RCNodes")
local TableUtils = require("deckr41.utils.table")

--- Domain imports
local RCNodesTree = require("deckr41.rc-nodes.tree")

--- @class RCFileProject
--- @field name string
--- @field icon? string

--- @class RCFileAgent
--- @field name string
--- @field identity string
--- @field domain string
--- @field mission string

--- @class RCFileCommand
--- @field name string
--- @field system_prompt? string|string[]
--- @field prompt string|string[]
--- @field source_json string
--- @field max_tokens? integer
--- @field temperature? number
--- @field response_syntax? string

--- @class RCFile
--- @field project? RCFileProject
--- @field agent? RCFileAgent
--- @field commands? RCFileCommand[]

--- @class CommandsConfig
local config = {
  default_rc_path = FSUtils.get_plugin_path() .. "/.d41rc",
  user_rc_path = os.getenv("XDG_CONFIG_HOME") .. "/deckr41/.d41rc",
  rc_schema_path = FSUtils.get_plugin_path() .. "/schemas/rc.json",
  templace_rc_path = FSUtils.get_plugin_path() .. "/examples/.d41rc",

  command_defaults = {
    response = {},
    context = {},
    temperature = 0.7,
  },
}

--- @class CommandsState
--- @field special_nodes table<string, RCTreeNode?>
--- @field tree RCTreeInstance
local state = {
  special_nodes = {},
  tree = RCNodesTree.build(),
}

--- @class CommandsModule
local M = {}

--- Read a single .d41rc file
--- @param file_path string
--- @return RCTreeNode|nil
local read_one_rc = function(file_path)
  -- This is an edgecase when working on the deckr41/nvim plugin itself
  -- where the node is loaded twice
  if state.special_nodes[file_path] then
    error("Skipping file, already loaded as special node")
  end

  --- @type RCFile
  local rc_data = FSUtils.read_json(file_path)

  -- Dont crash, just skip
  if not rc_data.commands then
    Logger.info("No commands found in .rc file", { path = file_path })
    return
  end

  --- @type table<string, RCFileCommand>
  local commands_dict = {}
  for _, rc_command in ipairs(rc_data.commands) do
    --- @type RCFileCommand
    local command = vim.tbl_extend("force", config.command_defaults, rc_command)

    command.prompt = ArrayUtils.join(rc_command.prompt)
    command.system_prompt = rc_command.system_prompt
        and ArrayUtils.join(rc_command.system_prompt or "")
      or nil
    command.source_json = vim.fn.json_encode(rc_command)

    commands_dict[command.name] = command
  end

  local folder_path = vim.fn.fnamemodify(file_path, ":h")

  return {
    path = file_path,
    data = vim.tbl_extend(
      "force",
      -- defaults
      {
        project = {
          icon = folder_path == vim.fn.getcwd() and "󱂵" or "󰉋",
          name = vim.fn.fnamemodify(folder_path, ":t"),
        },
      },
      -- file data
      rc_data,
      -- overwrites
      {
        commands = commands_dict,
      }
    ),
  }
end

-- Load internal `.d41rc` JSON files.
-- Default file shipped with the plugin and optional user level from
-- XDG_CONFIG_HOME.
local load_default = function()
  state.special_nodes[config.default_rc_path] =
    read_one_rc(config.default_rc_path)
  if FSUtils.does_file_exist(config.user_rc_path) then
    state.special_nodes[config.user_rc_path] =
      read_one_rc(config.default_rc_path)
  end
end

--- @param file_path string
--- @return boolean
local load_one = function(file_path)
  local success, node_data = pcall(function() return read_one_rc(file_path) end)
  if success and node_data then
    if state.tree.exists(file_path) then
      state.tree.update_data(file_path, node_data.data)
    else
      state.tree.add(node_data)
    end
    return true
  else
    Logger.warn(
      "Something went wrong loading rc_file",
      { path = file_path, error = node_data }
    )
    return false
  end
end

-- Load all `.d41rc` JSON files found in the user's current working directory.
M.load_all = function()
  load_default()

  local project_folder = vim.fn.getcwd()
  local rc_files = FSUtils.rg(project_folder, {
    match_file_names = { ".d41rc", ".d41rc.json" },
  })

  for _, rc_file in ipairs(rc_files) do
    load_one(rc_file)
    FSUtils.watch(rc_file, {
      debounce_timeout = 100,
      callback = function() load_one(rc_file) end,
    })
  end
end

M.print = function()
  --- Print the tree structure for debugging
  --- @param node RCTreeNode
  --- @param indent string
  local function print_tree(node, indent)
    indent = indent or ""
    local node_info = indent
      .. "- "
      .. (node.data.project and node.data.project.name or "Unnamed Project")

    print(
      node_info
        .. " ("
        .. tostring(TableUtils.size(node.data.commands))
        .. " commands)"
    )

    -- Recursively print children nodes
    if node.children then
      for _, child in ipairs(node.children) do
        print_tree(child, indent .. "  ")
      end
    end
  end

  local roots = TableUtils.concat(state.special_nodes, {
    state.tree.get_root(),
  })

  for _, root in ipairs(roots) do
    print_tree(root, "")
  end
end

--- Find the path down the tree, to the closest leaf responsible for `file_path`
--- @param file_path? string
--- @return RCTreeNode[]
M.find_path = function(file_path)
  local result_array = TableUtils.values(state.special_nodes)

  local tree_root = state.tree.get_root()
  if tree_root then result_array[#result_array + 1] = tree_root end

  if not file_path then return result_array end

  local found_nodes = state.tree.find_path_to_file(file_path)
  for _, node in ipairs(found_nodes) do
    result_array[#result_array + 1] = node
  end

  return result_array
end

--- @alias RCCommandID { name: string, node_id?: string }

--- Find a command by id and node path
--- @param opts RCCommandID
--- @return RCCommand|nil
M.find_command = function(opts)
  opts = vim.tbl_extend("force", {
    node_id = config.default_rc_path,
  }, opts)

  if opts.node_id and state.special_nodes[opts.node_id] then
    return state.special_nodes[opts.node_id].data.commands[opts.name]
  end

  return state.tree.find_command(opts)
end

--- Find a command by id and node path
--- @param opts RCCommandID
--- @return RCCommand
M.get_command = function(opts)
  local command = M.find_command(opts)
  if not command then Logger.error("Command not found", opts) end
  return command
end

--- Copy internal .d41rc into the user's current working dir
M.eject_internal_rc = function()
  local destination_path = vim.fn.getcwd() .. "/.d41rc"
  if FSUtils.does_file_exist(destination_path) then
    Logger.error(
      "File exists, aborting eject to prevent overwriting",
      { path = destination_path }
    )
    return
  end

  local source_file = io.open(config.default_rc_path, "r")
  if not source_file then
    Logger.error(
      "Failed to open internal commands file, this should not happen. Reinstall the plugin and try again."
    )
    return
  end

  --- @type string
  local source_content = source_file:read("*a")
  source_file:close()

  local destination_file = io.open(destination_path, "w")
  if not destination_file then
    Logger.error(
      "Failed to open destination file, please check the user running nvim is allowed to write",
      { path = destination_path }
    )
    return
  end

  -- Inject the real path to the schema file in the plugin install path
  local destination_content = source_content:gsub(
    '"%$schema"%s*:%s*".-"',
    '"$schema": "' .. config.rc_schema_path .. '"'
  )
  destination_file:write(destination_content)
  destination_file:close()

  FSUtils.copy_file({ from = config.default_rc_path, to = destination_path })
  Logger.info("Base commands ejected successfully", { path = destination_path })
end

return M
