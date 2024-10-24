--- @class NVimUtils
local M = {}

--- @class AddKeymapOpts: vim.api.keyset.keymap
--- @field modes table<string, fun(mode: string)|string>
--- @field buf_id? integer

--- Sets a global |mapping| for the given mode.
--- Wrapper over `vim.api.nvim_set_keymap` with the followind defautls:
---  `nowait` = false
---  `noremap` = true
---  `silent` = true
--- @param shortcut string
--- @param opts AddKeymapOpts
M.add_keymap = function(shortcut, opts)
  local modes = opts.modes
  local buf_id = opts.buf_id

  -- Remove `modes`, `buf_id` and `action` to prevent errors, as 'nvim_set_keymap'
  -- doesn't recognize them
  opts.modes = nil
  opts.buf_id = nil

  for mode, action in pairs(modes) do
    --- @type vim.api.keyset.keymap
    local keymap_opts = vim.tbl_extend("force", {
      nowait = false,
      noremap = true,
      silent = true,
      callback = type(action) == "function" and function() action(mode) end
        or nil,
    }, opts)

    if buf_id then
      vim.api.nvim_buf_set_keymap(
        buf_id,
        mode,
        shortcut,
        type(action) == "string" and action or "",
        keymap_opts
      )
    else
      vim.api.nvim_set_keymap(
        mode,
        shortcut,
        type(action) == "string" and action or "",
        keymap_opts
      )
    end
  end
end

--- @class AddKeymapsOpts: vim.api.keyset.keymap
--- @field modes table<"n"|"i"|"v", table<string, fun(mode: string)|string>>>
--- @field buf_id? integer

--- Set multiple global `mapping` for the given mode.
--- Wrapper over `vim.api.nvim_set_keymap`, or `nvim_buf_set_keymap`
--- if `opts.buf_id` is set, with followin defaults:
---  `nowait` = false
---  `noremap` = false
---  `silent` = true
--- @param opts AddKeymapsOpts
M.add_keymaps = function(opts)
  for mode, shortcuts in pairs(opts.modes) do
    for shortcut, action in pairs(shortcuts) do
      M.add_keymap(
        shortcut,
        vim.tbl_extend("force", opts or {}, {
          modes = { [mode] = action },
        })
      )
    end
  end
end

---@class AddCommandOpts: vim.api.keyset.user_command
---@field action function

--- Creates a global |user-commands| command.
--- Wrapper over `vim.api.nvim_create_user_command` with following defaults:
---  `nargs` = 0
---  `force` = false
---  `bang` = false
--- @param name string
--- @param opts AddCommandOpts
M.add_command = function(name, opts)
  local action = opts.action

  -- Remove `action` to prevent errors, as 'nvim_create_user_command'
  -- doesn't recognize it
  opts.action = nil

  vim.api.nvim_create_user_command(
    name,
    action,
    vim.tbl_deep_extend("force", opts or {}, {
      nargs = 0,
      force = false,
      bang = false,
    })
  )
end

-- Sets multiple buffer options. Passing `nil` as value deletes the option
-- (only works if there's a global fallback)
--- @param buf_id integer
--- @param options table<string, any>
M.set_buf_options = function(buf_id, options)
  for option, value in pairs(options) do
    vim.api.nvim_set_option_value(option, value, { buf = buf_id })
  end
end

-- Sets multiple window options. Passing `nil` as value deletes the option
-- (only works if there's a global fallback)
--- @param win_id integer
--- @param options table<string, any>
M.set_win_options = function(win_id, options)
  for option, value in pairs(options) do
    vim.api.nvim_set_option_value(option, value, { win = win_id })
  end
end

--- Checks if a buffer is valid.
--- Even if a buffer is valid it may have been unloaded. See |api-buffer|
--- for more info about unloaded buffers.
--- @param buf_id? integer Buffer handle, or 0 for current buffer
--- @return boolean
M.is_buf_valid = function(buf_id)
  return buf_id ~= nil and vim.api.nvim_buf_is_valid(buf_id)
end

--- Checks if a window is valid.
--- @param win_id? integer Window handle, or 0 for current buffer
--- @return boolean
M.is_win_valid = function(win_id)
  return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

--- Create a scratch, throwaway, buffer.
--- @param opts table
--- @return integer buf_id
M.create_scratch_buffer = function(opts)
  local buf_id = vim.api.nvim_create_buf(false, true)
  if opts then M.set_buf_options(buf_id, opts) end
  return buf_id
end

return M
