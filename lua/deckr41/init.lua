--- Utilities imports
local NVimUtils = require("deckr41.utils.nvim")
local SelectUI = require("deckr41.ui.select")
local TableUtils = require("deckr41.utils.table")

--- Domain imports
local Backend = require("deckr41.backend")
local Commands = require("deckr41.commands")
local InsertModeHandler = require("deckr41.insert-handler")
local NormalModeHandler = require("deckr41.normal-handler")

--- @class Deckr41Plugin
local M = {}

--- @class Deckr41PluginConfig
--- @field emoji_title string
local config = {
  emoji_title = "  + 󰚩",
}

--- @class Deckr41UserConfig
--- @field backends? BackendServices
--- @field active_backend? BackendServiceName
--- @field active_model? string
--- @field modes? InsertModes
--- @field active_mode? InsertModeName

--- Deckr41 plugin main entry point
--- @param user_config? Deckr41UserConfig
M.setup = function(user_config)
  user_config = user_config or {}

  --
  -- Configure available backends and models
  --
  Backend.setup({
    backends = user_config.backends,
    active_backend = user_config.active_backend,
    active_model = user_config.active_model,
  })

  --
  -- Scan and load commands from .d41rc or .d41rc.json files
  --
  Commands.setup()

  NVimUtils.add_command("D41EjectDefaultCommands", {
    desc = "[deckr41] Eject default commands",
    action = Commands.eject_defaults,
  })

  --
  -- Command running from NORMAL mode via UI select menu
  --
  NormalModeHandler.setup()

  --
  -- Command running from INSERT mode via keyboard shortcuts
  --
  InsertModeHandler.setup({
    active_mode = user_config.active_mode,
    modes = user_config.modes or {},
  })

  --
  -- Control Panel
  --

  --- @return SelectUIItemGroup[]
  local build_control_panel_item_groups = function()
    local to_item = function(text) return { id = text, text = text } end
    return {
      {
        id = "[keyboard]",
        selected = InsertModeHandler.get_active_mode(),
        items = TableUtils.imap(InsertModeHandler.get_modes(), to_item),
      },
      {
        id = "[backends]",
        selected = Backend.get_active_backend(),
        items = TableUtils.imap(Backend.get_backend_names(), to_item),
      },
      {
        id = "[models]",
        selected = Backend.get_active_model(),
        items = TableUtils.imap(Backend.get_available_models(), to_item),
      },
    }
  end

  local control_panel = SelectUI.build({
    title = config.emoji_title,
    groups = build_control_panel_item_groups(),
    on_select = function(self, item)
      local backend = Backend.get_active_backend()
      local model = Backend.get_active_model()
      local keyboard_mode = InsertModeHandler.get_active_mode()

      if item.group_id == "[backends]" and backend ~= item.id then
        Backend.set_active_backend(item.id)
      elseif item.group_id == "[models]" and model ~= item.id then
        Backend.set_active_model(item.id)
      elseif item.group_id == "[keyboard]" and keyboard_mode ~= item.id then
        InsertModeHandler.set_active_mode(item.id)
      end

      self.update({ groups = build_control_panel_item_groups() })
    end,
  })

  NVimUtils.add_command("D41ControlPanel", {
    desc = "[deckr41] Open control panel",
    action = control_panel.show,
  })

  NVimUtils.add_keymap("<leader>dp", {
    desc = "[deckr41] Open control panel",
    modes = { n = ":D41ControlPanel<CR>" },
  })
end

return M
