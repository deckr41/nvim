local ArrayUtils = require("deckr41.utils.array") --- @class ArrayUtils
local FSUtils = require("deckr41.utils.fs") --- @class FSUtils
local FnUtils = require("deckr41.utils.fn") --- @class FnUtils
local Logger = require("deckr41.utils.logger") --- @class Logger
local WindowUtils = require("deckr41.utils.window") --- @class WindowUtils

--- @class RCFileCommand
--- @field id string
--- @field system_prompt ?string|string[]
--- @field prompt string|string[]
--- @field max_tokens ?integer
--- @field temperature ?number

--- @class Command
--- @field id string
--- @field system_prompt ?string
--- @field prompt string
--- @field max_tokens ?integer
--- @field temperature ?number

--- @class RCFileData
--- @field commands ?RCFileCommand[]

--- Runtime state
--- @class CommandsState
--- @field commands Command[]
local state = {
  commands = {},
}

--- @class CommandsModule
--- @field default_rc_path string
--- @field rc_schema_path string
--- @field templace_rc_path string
local M = {
  default_rc_path = FSUtils.get_plugin_path() .. "/.d41rc",
  rc_schema_path = FSUtils.get_plugin_path() .. "/.d41rc-schema.json",
  templace_rc_path = FSUtils.get_plugin_path() .. "/.d41rc-template.json",
}

--- Load commands from a single .d41rc file
--- @param file_path string
local load_one = function(file_path)
  local success, rc_data = pcall(function()
    --- @type RCFileData
    return FSUtils.read_json_as_table(file_path)
  end)
  if not success or not rc_data then
    Logger.error(
      "Failed to load .rc file",
      { path = file_path, error = rc_data }
    )
    return
  end

  if not rc_data.commands then
    Logger.warn("No commands found in .rc file", { path = file_path })
    return
  end

  for _, command in ipairs(rc_data.commands) do
    if state.commands[command.id] then
      Logger.debug(
        "Command already defined and will be overwriten",
        { id = command.id, path = file_path }
      )
    end

    state.commands[command.id] = {
      id = command.id,
      system_prompt = command.system_prompt and ArrayUtils.join(
        command.system_prompt or ""
      ) or nil,
      prompt = ArrayUtils.join(command.prompt),
      max_tokens = command.max_tokens,
      temperature = command.temperature,
    }
  end
end

--- Watch a .d41rc file for changes and reload commands when it does
--- @param file_path string
local function watch_and_reload_one(file_path)
  local watch = vim.loop.new_fs_event()

  if not watch then
    Logger.error("Failed to create file system watcher", { path = file_path })
    return
  end

  local handle_on_change = FnUtils.debounce(function()
    Logger.debug(
      ".rc file changed, reloading commands ...",
      { path = file_path }
    )
    load_one(file_path)
  end)

  watch:start(file_path, {}, handle_on_change)
end

-- Load all commands from internal .d41rc.json file and all found up the dir tree
-- starting from the user's current working directory
function M:load_all()
  --- @type string[]
  local rc_files = ArrayUtils.concat(
    { M.default_rc_path },
    FSUtils.find_up_sync({
      start_dir = vim.fn.expand("%:p:h"),
      match_files = { ".d41rc", ".d41rc.json" },
    })
  )

  for _, rc_file in ipairs(rc_files) do
    load_one(rc_file)
    watch_and_reload_one(rc_file)
  end
end

--- Return all the variables supported by command prompt interpolation
--- @return table
function M:gather_context()
  local cursor_row, cursor_col = vim.api.nvim_win_get_cursor(0)
  local lines_before, current_line, lines_after =
    WindowUtils.get_lines_split_by_current()

  return {
    FILE_PATH = WindowUtils.get_path(),
    FILE_SYNTAX = WindowUtils.get_syntax(),
    FILE_CONTENT = WindowUtils.get_file_content(),
    LINES_BEFORE_CURRENT = table.concat(lines_before, "\n"),
    TEXT_BEFORE_CURSOR = string.sub(current_line, 1, cursor_col),
    LINES_AFTER_CURRENT = table.concat(lines_after, "\n"),
    CURSOR_ROW = cursor_row,
    CURSOR_COL = cursor_col,
  }
end

---
--- @return Command[]
function M:get_all_loaded_commands() return state.commands end

---
--- @param id string
--- @return Command|nil
function M:get_command_by_id(id) return state.commands[id] end

--- Copy internal .d41rc into the user's current working dir
function M:eject()
  local destination_path = vim.fn.getcwd() .. "/.d41rc"
  if FSUtils.does_file_exist(destination_path) then
    Logger.error(
      "File exists, aborting eject to prevent overwriting",
      { path = destination_path }
    )
    return
  end

  local source_file = io.open(self.default_rc_path, "r")
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

  ---
  local destination_content = source_content:gsub(
    '"%$schema"%s*:%s*".-"',
    '"$schema": "' .. self.rc_schema_path .. '"'
  )
  destination_file:write(destination_content)
  destination_file:close()

  FSUtils.copy_file({ from = self.default_rc_path, to = destination_path })
  Logger.info("Base commands ejected successfully", { path = destination_path })
end

return M
