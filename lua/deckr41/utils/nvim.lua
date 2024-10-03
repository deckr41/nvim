--- @class NVimUtils
local M = {}

--- @class AddKeymapOpts
--- @field mode string
--- @field action function
--- @field nowait? boolean
--- @field noremap? boolean
--- @field silent? boolean

--- Sets a global |mapping| for the given mode.
--- Wrapper over `vim.api.nvim_set_keymap` with the followind defautls:
---  `nowait` = false
---  `noremap` = true
---  `silent` = true
--- @param opts AddKeymapOpts
M.add_keymap = function(shortcut, opts)
  local action = opts.action
  local mode = opts.mode

  -- `nvim_set_keymap` does not recognize them and throws
  opts.mode = nil
  opts.action = nil

  vim.api.nvim_set_keymap(
    mode,
    shortcut,
    "",
    vim.tbl_deep_extend("force", {
      nowait = false,
      noremap = true,
      silent = true,
      callback = action,
    }, opts)
  )
end

--- @class AddKeymapsOpts
--- @field buf_id? integer
--- @field mode? string
--- @field nowait? boolean
--- @field noremap? boolean
--- @field silent? boolean

--- Add multiple keymaps
--- @param mappings table<string, function>
--- @param opts? AddKeymapsOpts
M.add_keymaps = function(mappings, opts)
  opts = opts or {}
  for shortcut, action in pairs(mappings) do
    if opts.buf_id then
      vim.api.nvim_buf_set_keymap(opts.buf_id, opts.mode or "", shortcut, "", {
        nowait = opts.nowait or false,
        noremap = opts.noremap or true,
        silent = opts.silent or true,
        callback = action,
      })
    else
      vim.api.nvim_set_keymap(opts.mode or "n", shortcut, "", {
        nowait = opts.nowait or false,
        noremap = opts.noremap or true,
        silent = opts.silent or true,
        callback = action,
      })
    end
  end
end

--- @class AddCommandOpts
--- @field action function
--- @field nargs? number
--- @field complete? function
--- @field desc? string
--- @field force? boolean
--- @field bang? boolean

--- Creates a global |user-commands| command.
--- Wrapper over `vim.api.nvim_create_user_command` with
---  `nargs` = 0
---  `force` = false
---  `bang` = false
--- @param opts AddCommandOpts
M.add_command = function(name, opts)
  local action = opts.action
  -- `nvim_create_user_command` does not recognize and throws
  opts.action = nil

  vim.api.nvim_create_user_command(
    name,
    action,
    vim.tbl_deep_extend("force", opts, {
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
    vim.api.nvim_buf_set_option(buf_id, option, value)
  end
end

-- Sets multiple window options. Passing `nil` as value deletes the option
-- (only works if there's a global fallback)
--- @param win_id integer
--- @param options table<string, any>
M.set_win_options = function(win_id, options)
  for option, value in pairs(options) do
    vim.api.nvim_win_set_option(win_id, option, value)
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

--- Create and set up a buffer
--- @param opts table
--- @return integer buf_id
M.create_scratch_buffer = function(opts)
  local buf_id = vim.api.nvim_create_buf(false, true)
  if opts then M.set_buf_options(buf_id, opts) end
  return buf_id
end

return M
