local VimAPI = vim.api
local FnUtils = require("deckr41.utils.fn") --- @type FnUtils
local Logger = require("deckr41.utils.logger") --- @type Logger

--- @class KeyboardModule
local M = {}

--- @alias KeyboardModeName "easy-does-it"|"r-for-rocket"

--- @class ModeEasyDoesIt
--- @field command string
--- @field double_command string

--- @class ModeRForRocket
--- @field timeout integer
--- @field command string

--- @class KeyboardModes
--- @field ["easy-does-it"] ModeEasyDoesIt
--- @field ["r-for-rocket"] ModeRForRocket

--- @class KeyboardConfig
--- @field modes KeyboardModes
local default_config = {
  modes = {
    ["easy-does-it"] = {
      command = "finish-line",
      double_command = "finish-block",
    },
    ["r-for-rocket"] = {
      command = "finish-block",
      timeout = 1000,
    },
  },
}

--- @class KeyboardState
--- @field active_mode KeyboardModeName
--- @field shift_arrow_right_count integer
local state = {
  active_mode = "easy-does-it",
  -- RightArrow press counter since NeoVim cannot bind Shift + ArrowRight + ArrowRight
  shift_arrow_right_count = 0,
}

--- @class KeyboardSetupOpts
--- @field active_mode ?KeyboardModeName
--- @field modes ?KeyboardModes
--- @field is_command_running fun(): boolean
--- @field can_accept fun(): boolean
--- @field on_accept function
--- @field on_refuse function
--- @field on_command fun(command_id: string)

--- @param opts KeyboardSetupOpts
M.setup = function(opts)
  local config =
    vim.tbl_deep_extend("force", default_config, { modes = opts.modes })
  state.active_mode = opts.active_mode or "easy-does-it"

  M.setup_keymaps(opts, config)
  M.setup_autocmds(opts, config)
end

--- Setup key mappings
--- @param opts KeyboardSetupOpts
--- @param config KeyboardConfig
M.setup_keymaps = function(opts, config)
  local mode = config.modes[state.active_mode]

  -- On first Shift+Right, no matter the mode, trigger the assigned command.
  -- On 2xShift+right, if mode is "easy-does-it", trigger the double command.
  local function handle_shift_right()
    if opts.can_accept() then return opts.on_accept() end
    if opts.is_command_running() then return end

    state.shift_arrow_right_count = state.shift_arrow_right_count + 1
    vim.defer_fn(function()
      local count = state.shift_arrow_right_count
      if count == 1 then
        opts.on_command(mode.command)
      elseif state.active_mode == "easy-does-it" and count == 2 then
        opts.on_command(mode.double_command)
      end
      state.shift_arrow_right_count = 0
    end, 200)
  end

  -- Trigger suggestion command based on mode
  VimAPI.nvim_set_keymap("i", "<S-Right>", "", {
    noremap = true,
    silent = true,
    callback = handle_shift_right,
  })

  -- Accept suggestion if available
  VimAPI.nvim_set_keymap("i", "<Tab>", "", {
    noremap = true,
    silent = true,
    callback = function()
      if opts.can_accept() then
        opts.on_accept()
      else
        -- Send the key as normal input
        VimAPI.nvim_feedkeys(
          VimAPI.nvim_replace_termcodes("<Tab>", true, false, true),
          "n",
          true
        )
      end
    end,
  })

  -- Cancel any ongoing suggestion command
  VimAPI.nvim_set_keymap("i", "<Escape>", "", {
    noremap = true,
    silent = true,
    callback = function()
      if opts.is_command_running() then
        opts.on_refuse()
      else
        -- Send the key as normal input
        VimAPI.nvim_feedkeys(
          VimAPI.nvim_replace_termcodes("<Escape>", true, false, true),
          "n",
          true
        )
      end
    end,
  })
end

--- Setup autocommands based on the mode
--- @param opts KeyboardSetupOpts
--- @param config KeyboardConfig
M.setup_autocmds = function(opts, config)
  local augroup = VimAPI.nvim_create_augroup("D41KeymapGroup", { clear = true })

  VimAPI.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function() opts.on_refuse() end,
  })

  -- In 'r-for-rocket' mode, trigger suggestions on InsertEnter and TextChangedI
  if state.active_mode == "r-for-rocket" then
    local mode = config.modes[state.active_mode]
    local debounced_command, timer = FnUtils.debounce(
      function() opts.on_command(mode.command) end,
      { reset_duration = mode.timeout }
    )

    VimAPI.nvim_create_autocmd("InsertEnter", {
      group = augroup,
      callback = function() debounced_command() end,
    })

    VimAPI.nvim_create_autocmd("TextChangedI", {
      group = augroup,
      callback = function() debounced_command() end,
    })

    VimAPI.nvim_create_autocmd("InsertLeave", {
      group = augroup,
      callback = function() timer:stop() end,
    })
  end
end

--- @param mode KeyboardModeName
M.set_mode = function(mode)
  if not default_config.modes[mode] then
    Logger.error("Invalid mode", { mode = mode })
    return
  end
  state.active_mode = mode
end

--- @return KeyboardModeName
M.get_modes = function() return vim.tbl_keys(default_config.modes) end

return M
