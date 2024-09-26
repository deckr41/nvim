local VimAPI = vim.api

--- Functional utilities imports
--- @type Logger
local Logger = require("deckr41.utils.logger")
--- @type TelescopeUtils
local TelescopeUtils = require("deckr41.utils.telescope")
--- @type StringUtils
local StringUtils = require("deckr41.utils.string")
--- @type WindowUtils
local WindowUtils = require("deckr41.utils.window")
--- @type TableUtils
local TableUtils = require("deckr41.utils.table")

--- Domain imports
--- @type CommandsModule
local Commands = require("deckr41.commands")
--- @type SuggestionModule
local Suggestion = require("deckr41.suggestion")
--- @type BackendModule
local Backend = require("deckr41.backend")

---

--- @class Deckr41PluginConfig
--- @field backends ?table<BackendServiceNames, BackendServiceConfig>
--- @field active_backend ?BackendServiceNames
--- @field active_model ?string
--- @field default_command string
--- @field default_double_command string

--- @class Deckr41PluginState
--- @field running_command_job ?Job
--- @field shift_arrow_right_count integer

--- Plugin config and global state
--- @class Deckr41Plugin
--- @field config ?Deckr41PluginConfig
--- @field state Deckr41PluginState
local M = {
  -- User config from plugin loading
  config = {
    backends = nil,
    active_backend = nil,
    active_model = nil,
    default_command = "finish-line",
    default_double_command = "finish-block",
  },
  -- Runtime state
  state = {
    -- Plenary Job of currently running command
    running_command_job = nil,
    -- RightArrow press counter since NeoVim cannot bind Shift + ArrowRight + ArrowRight
    shift_arrow_right_count = 0,
  },
}

---@param command_id string
local run_command = function(command_id)
  -- local window_id = VimAPI.nvim_get_current_win()
  local command = Commands:get_command_by_id(command_id)
  if not command then
    Logger.error("Default command '" .. command_id .. "' not found")
    return
  end

  local cursor_row, cursor_col = WindowUtils.get_cursor_position()
  local lines_before, current_line, lines_after =
    WindowUtils.get_lines_split_by_current()
  local interpolated_prompt = StringUtils.interpolate(command.prompt, {
    FILE_PATH = WindowUtils.get_path(),
    FILE_SYNTAX = WindowUtils.get_syntax(),
    LINES_BEFORE_CURRENT = table.concat(lines_before, "\n"),
    TEXT_BEFORE_CURSOR = string.sub(current_line, 1, cursor_col),
    LINES_AFTER_CURRENT = table.concat(lines_after, "\n"),
    CURSOR_ROW = cursor_row,
    CURSOR_COL = cursor_col,
  })

  local interpolated_system_prompt = command.system_prompt
  if interpolated_system_prompt then
    interpolated_system_prompt =
      StringUtils.interpolate(interpolated_system_prompt, {
        FILE_PATH = WindowUtils.get_path(),
        FILE_SYNTAX = WindowUtils.get_syntax(),
        LINES_BEFORE_CURRENT = table.concat(lines_before, "\n"),
        TEXT_BEFORE_CURSOR = string.sub(current_line, 1, cursor_col),
        LINES_AFTER_CURRENT = table.concat(lines_after, "\n"),
        CURSOR_ROW = cursor_row,
        CURSOR_COL = cursor_col,
      })
  end

  M.state.running_command_job = Backend:ask(M.config.active_backend, {
    model = M.config.active_model,
    system_prompt = interpolated_system_prompt,
    max_tokens = command.max_tokens,
    temperature = command.temperature,
    messages = {
      {
        role = "user",
        content = interpolated_prompt,
      },
    },
    on_start = function(config)
      Suggestion.meta.right = string.format(
        "%s / %s / %s / t: %s ",
        command_id,
        config.backend_name or "?",
        config.model or "?",
        config.temperature or "?"
      )
      Suggestion:start_loading()
      Suggestion:show()
    end,
    on_data = function(chunk)
      Suggestion.text = Suggestion.text .. chunk
      Suggestion:redraw()
    end,
    on_done = function(response, http_status)
      if http_status >= 400 then Suggestion.text = response end
      Suggestion:finish_loading()
      Suggestion:redraw()
    end,
    on_error = function(response)
      -- 41 is the shutdown code used when the cursor moves. We only want
      -- to fill and display the response if it's an OS or API error
      if response and response.exit ~= 41 then
        Suggestion.text = Suggestion.text .. response.message
      end
    end,
  })
end

-- Prompt the user to select an LLM command
--- @return nil
M.select_and_apply_command_or_accept_suggestion = function()
  if Suggestion.is_loading then return end

  if Suggestion.is_visible then
    Suggestion:apply()
  else
    TelescopeUtils.select({
      items = Commands:get_all_loaded_commands(),
      title = "Select a command:",
      onSelect = function(item) run_command(item.id) end,
    })
  end
end

---
local setup_keymaps = function()
  -- Trigger the LLM magic or apply (write to the current buffer the existing
  -- suggestion/response)

  VimAPI.nvim_set_keymap("i", "<S-Right>", "", {
    noremap = true,
    silent = true,
    callback = function()
      if Suggestion:is_finished() then
        Suggestion:apply()
      elseif not Suggestion.is_loading then
        M.state.shift_arrow_right_count = M.state.shift_arrow_right_count + 1

        vim.defer_fn(function()
          if M.state.shift_arrow_right_count == 1 then
            run_command(M.config.default_command)
          end
          if M.state.shift_arrow_right_count == 2 then
            run_command(M.config.default_double_command)
          end
          M.state.shift_arrow_right_count = 0
        end, 200)
      end
    end,
  })

  -- Keybindings that only work when the suggestion box is visible
  local keybinds = {
    ["<Tab>"] = function()
      if Suggestion:is_finished() and Suggestion.text ~= "" then
        Suggestion:apply()
      end
    end,
    ["<CR>"] = function()
      if Suggestion:is_finished() and Suggestion.text ~= "" then
        Suggestion:apply()
      end
    end,
    ["<Escape>"] = function() Suggestion:reset() end,
  }

  for key, callback in pairs(keybinds) do
    VimAPI.nvim_set_keymap("i", key, "", {
      noremap = true,
      silent = true,
      callback = function()
        if Suggestion.is_visible then
          callback()
        else
          -- Send the key as normal input
          VimAPI.nvim_feedkeys(
            VimAPI.nvim_replace_termcodes(key, true, false, true),
            "n",
            true
          )
        end
      end,
    })
  end
end

---
local setup_autocmds = function()
  -- Close the Suggestion box and stop the current command if running
  -- when moving the cursor
  local augroup =
    VimAPI.nvim_create_augroup("CursorMovedGroup", { clear = true })

  VimAPI.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function()
      if M.state.running_command_job then
        M.state.running_command_job:shutdown(41)
        M.state.running_command_job = nil
      end
      if Suggestion.is_visible then Suggestion:reset() end
    end,
  })
end

---
--- @param backend_configs table<string, BackendServiceConfig>
local setup_backends = function(backend_configs)
  if not backend_configs then return end

  for backend_name, backend_config in pairs(backend_configs) do
    if not Backend:is_backend_supported(backend_name) then
      Logger.error(
        "Invalid backend '"
          .. backend_name
          .. "'. Accepted values are 'openai' and 'anthropic'."
      )
    else
      if not M.config.active_backend then
        M.config.active_backend = backend_name
      end
      Backend:set_config(backend_name, backend_config)
    end
  end
end

--- Main plugin entry point
--- @param opts ?Deckr41PluginConfig
M.setup = function(opts)
  opts = opts or {}

  --
  -- Parse user configuration
  --

  TableUtils.deep_extend(M.config, {
    active_backend = opts.active_backend,
    active_model = opts.active_model,
    default_command = opts.default_command,
    default_double_command = opts.default_double_command,
  })

  setup_backends(opts.backends)

  --
  ---
  --

  if not M.config.active_backend then
    -- Prioritize Anthropic
    if os.getenv("ANTHROPIC_API_KEY") then
      M.config.active_backend = "anthropic"
    elseif os.getenv("OPENAI_API_KEY") then
      M.config.active_backend = "openai"
    else
      Logger.error("No active backend specified and no API keys found.")
    end
  end

  -- Scan and load all .d41rc or .d41rc.json files
  Commands:load_all()

  -- Copy default commands into the user's cwd for convenient overwrites
  VimAPI.nvim_create_user_command(
    "D41Eject",
    function() Commands:eject() end,
    {}
  )

  setup_keymaps()
  setup_autocmds()
end

return M
