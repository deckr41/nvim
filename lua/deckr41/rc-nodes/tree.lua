local Logger = require("deckr41.utils.loggr")("RCTree")
local StringUtils = require("deckr41.utils.string")
local TableUtils = require("deckr41.utils.table")

--- @class RCTreeFactory
local M = {}

--- @class RCProject
--- @field name string Unique project ID
--- @field icon? string

--- @class RCAgent
--- @field name string Unique agent ID
--- @field identity string
--- @field domain string
--- @field mission string

--- @class RCCommandParameterTextarea
--- @field type "textarea"
--- @field label string
--- @field default? string

--- @class RCCommandParameterSelect
--- @field type "select"
--- @field label string
--- @field options { value: string, value: string }[]
--- @field default? string[]

--- @class RCCommandParameterFilePicker
--- @field type "file-picker"
--- @field label string
--- @field default? string[]

--- @alias RCCommandParameter RCCommandParameterTextarea | RCCommandParameterSelect | RCCommandParameterFilePicker

--- @class RCCommand
--- @field name string Unique command ID
--- @field system_prompt? string
--- @field prompt string
--- @field source_json string
--- @field max_tokens? integer
--- @field temperature? number
--- @field response_syntax? string
--- @field parameters? table<string, RCCommandParameter>
--- @field on_accept? "insert"|"replace"

--- @class RCNodeData
--- @field project? RCProject
--- @field agent? RCAgent
--- @field commands table<string, RCCommand>

--- @class RCTreeNode
--- @field path string Unique node ID (file path)
--- @field parent? RCTreeNode
--- @field children RCTreeNode[]
--- @field data RCNodeData Underlying file JSON contents

--- Build a tree structure to hold the hierarchy of .d41rc/.d41rc.json files
--- present in the user's project folder.
--- @return RCTreeInstance
M.build = function()
  --- @class RCTreeInstance
  local instance = {}

  --- @class TreeInstanceState
  local state = {
    --- @type RCTreeNode
    root = nil,
    --- @type table<string, RCTreeNode>  -- Map from node.path to node
    nodes_dict = {},
  }

  --- Find parent node based on the directory hierarchy
  --- @param rc_path string
  --- @return RCTreeNode|nil
  local function find_parent_node(rc_path)
    local node_dir = vim.fn.fnamemodify(rc_path, ":h")
    local current_dir = node_dir

    while true do
      current_dir = vim.fn.fnamemodify(current_dir, ":h")
      if current_dir == node_dir or current_dir == "" or current_dir == "/" then
        -- Reached root or cannot go up further
        return nil
      end

      local possible_paths = {
        current_dir .. "/.d41rc",
        current_dir .. "/.d41rc.json",
      }

      for _, parent_path in ipairs(possible_paths) do
        local parent_node = state.nodes_dict[parent_path]
        if parent_node then return parent_node end
      end

      node_dir = current_dir
    end
  end

  --- Add a node to the tree. Automatically detect and assign the parent based on
  --- `node.path`.
  --- @param node RCTreeNode
  --- @return RCTreeNode|nil
  instance.add = function(node)
    state.nodes_dict[node.path] = node

    if not state.root then
      state.root = node
      state.root.children = {}
      return node
    end

    local parent_node = find_parent_node(node.path)
    node.parent = parent_node and parent_node or state.root
    node.children = node.children or {}
    node.parent.children[#node.parent.children + 1] = node

    return node
  end

  --- Find a node by path
  --- @param path string
  --- @return RCTreeNode|nil
  instance.find = function(path) return state.nodes_dict[path] end

  --- Update a node's `data` field
  --- @param path string
  --- @param data RCNodeData
  instance.update = function(path, data)
    local node = state.nodes_dict[path]
    if node then node.data = data end
  end

  --- Find a command by id and node path
  --- @param opts { name: string, node_id: string }
  --- @return RCCommand|nil
  instance.find_command = function(opts)
    local node = state.nodes_dict[opts.node_id]
    if node then return node.data.commands[opts.name] end
  end

  --- Return all the root nodes (nodes without a parent)
  --- @return RCTreeNode[]
  instance.get_root = function() return state.root end

  --- Find all nodes along the path to `file_path`, from closest to root
  --- @param file_path string
  --- @return RCTreeNode[]
  instance.find_path_to_file = function(file_path)
    --- Determine if the input `file_path` is a file in the node's folder path
    --- @param node RCTreeNode
    --- @return boolean
    local is_match = function(node)
      local folder_path = vim.fn.fnamemodify(node.path, ":h")
      return StringUtils.starts_with(file_path, folder_path)
    end

    local result_array = {} --- @type RCTreeNode[]
    local current = state.root --- @type RCTreeNode|nil

    while current ~= nil do
      current = TableUtils.find(current.children, is_match)
      if current then result_array[#result_array + 1] = current end
    end

    return result_array
  end

  --- Check if a node exists in the tree
  --- @param file_path any
  --- @return boolean
  instance.exists = function(file_path)
    return state.nodes_dict[file_path] ~= nil
  end

  --- @param file_path string
  --- @param data RCNodeData
  instance.update_data = function(file_path, data)
    local node = state.nodes_dict[file_path]
    if node then
      node.data = data
    else
      Logger.error("Failed to update node data", { path = file_path })
    end
  end

  return instance
end

return M
