--- Utilities imports
local ArrayUtils = require("deckr41.utils.array")
local Logger = require("deckr41.utils.loggr")("NormalModeHandler")
local NVimUtils = require("deckr41.utils.nvim")
local Pinpointer = require("deckr41.utils.pinpointr")
local SelectUI = require("deckr41.ui.select")
local SuggestionUI = require("deckr41.ui.suggestion")
local WindowUtils = require("deckr41.utils.window")

--- Domain imports
local Commands = require("deckr41.commands")

--- @class NormalModeHandler
local M = {}

--- @class NormalModeState
local state = {
  job = nil, --- @type Job? Plenary Job of currently running command
  suggestion_ui = nil, --- @type SuggestionUIInstance?
  select_ui = nil, --- @type SelectUIInstance?
}

--
-- Private methods
--

--- @return boolean
local function can_accept() return state.job ~= nil and state.job.is_shutdown end

--- Apply the suggestion by inserting at cursor position or replacing prev
--- selected range.
local function apply()
  local pinpoint = Pinpointer.get()
  WindowUtils.insert_text_at(state.suggestion_ui.get_text(), {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    range = pinpoint.range,
  })

  state.suggestion_ui.hide()
  state.job = nil
end

---
local function refuse()
  if state.job then
    state.job:shutdown(41)
    state.job = nil
  end
  state.suggestion_ui.hide()
end

--- Generate the preview value for a command
--- @param command RCCommand
--- @return string
local function get_command_preview(command)
  local pinpoint = Pinpointer.get()
  local system_prompt, prompt = Commands.compile({
    prompt = command.prompt,
    system_prompt = command.system_prompt,
  }, {
    win_id = pinpoint.win_id,
    cursor = pinpoint.cursor,
    range = pinpoint.range,
  })
  local preview = ""

  if system_prompt then
    preview = preview .. "# System Prompt\n\n" .. system_prompt .. "\n\n"
  end
  if prompt then preview = preview .. "# Prompt\n\n" .. prompt end

  return preview
end

--- @param rc_nodes RCTreeNode[]
--- @return SelectUIItemGroup[]
local build_commands_menu_item_groups = function(rc_nodes)
  local result_array = {} --- @type SelectUIItemGroup[]
  for _, rc_node in pairs(rc_nodes) do
    local commands_array = {} --- @type SelectUIItem[]
    for key, command in pairs(rc_node.data.commands) do
      local command_select_item = { --- @type SelectUIItem
        id = key,
        label = command.name,
        preview = {
          {
            id = "final",
            value = function() return get_command_preview(command) end,
            filetype = "markdown",
          },
          {
            id = "json",
            value = function() return command.source_json end,
            filetype = "json",
          },
        },
      }
      table.insert(commands_array, command_select_item)
    end
    table.sort(commands_array, function(a, b) return a.label < b.label end)
    result_array[#result_array + 1] = {
      id = rc_node.path,
      label = rc_node.data.project.icon .. " " .. rc_node.data.project.name,
      items = commands_array,
    }
  end
  return result_array
end

--- Setup commands
local setup_commands = function()
  NVimUtils.add_command("D41RunCommand", {
    desc = "[deckr41] Run command",
    range = 2,
    action = function(cmd_opts)
      Pinpointer.take_snapshot({
        with_range = cmd_opts.range == 2,
      })

      local file_path = vim.api.nvim_buf_get_name(0)
      local rc_nodes = Commands.find_nodes(file_path)

      -- Reversing to keep "closest" commands on top
      state.select_ui.update({
        groups = build_commands_menu_item_groups(ArrayUtils.reverse(rc_nodes)),
      })
      state.select_ui.show()
    end,
  })
end

--- Setup key mappings
local setup_keymaps = function()
  vim.api.nvim_set_keymap(
    "v",
    "<leader>dc",
    ":D41RunCommand<CR>",
    { desc = "[deckr41] Run command" }
  )

  vim.api.nvim_set_keymap(
    "n",
    "<leader>dc",
    ":D41RunCommand<CR>",
    { desc = "[deckr41] Run command" }
  )

  NVimUtils.add_keymap("<Tab>", {
    desc = "[deckr41] Insert/accept suggestion if available",
    modes = {
      n = function()
        if can_accept() then apply() end
      end,
    },
  })

  NVimUtils.add_keymap("<Escape>", {
    desc = "[deckr41] Cancel ongoing suggestion or exit insert mode",
    modes = {
      n = function()
        if state.job ~= nil then
          refuse()
        else
          -- Send the key as normal input
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Escape>", true, false, true),
            "n",
            true
          )
        end
      end,
    },
  })
end

--
-- Public methods
--

M.setup = function()
  state.suggestion_ui = SuggestionUI.build({ win_opts = { border = "none" } })
  state.select_ui = SelectUI.build({
    title = " 󰚩 Commands ",
    title_pos = "left",
    close_on_select = true,
    on_open = function()
      local pinpoint = Pinpointer.get()

      state.suggestion_ui.update({
        status = "asking",
        filetype = pinpoint.filetype,
      })
    end,
    on_select = function(_, item)
      local pinpoint = Pinpointer.get()

      state.job = Commands.run({
        name = item.id,
        node_id = item.group_id,
      }, {
        win_id = pinpoint.win_id,
        cursor = pinpoint.cursor,
        range = pinpoint.range,
        on_start = function(cmd_config)
          state.suggestion_ui.update({
            value = "",
            meta = string.format("%s / %s ", item.id, cmd_config.model),
          })
          state.suggestion_ui.show()
        end,
        on_data = function(chunk) state.suggestion_ui.append_text(chunk) end,
        on_done = function(response, http_status)
          if http_status >= 400 then
            state.suggestion_ui.update({ value = response })
          end
          state.suggestion_ui.update({ status = "done" })
        end,
        on_error = function(response)
          -- 41 is the shutdown code used when the cursor moves. We only want
          -- to fill and display the response if it's an OS or API error
          if response and response.exit ~= 41 then
            state.suggestion_ui.append_text(response.message)
          end
          state.suggestion_ui.update({ status = "done" })
        end,
      })
    end,
    preview_config = {
      number = true,
    },
  })

  setup_commands()
  setup_keymaps()
end

return M
