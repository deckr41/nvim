--- @class FnUtils
local M = {}

--- Run a function only if the specified duration has passed since the last call.
--- @generic T: function
--- @param fn T
--- @param opts ?{ reset_duration?: integer, has_leading_call?: boolean }
--- @return T
M.debounce = function(fn, opts)
  opts = opts or {}
  local reset_duration = opts.reset_duration or 200
  local has_leading_call = opts.has_leading_call or false
  local last_call = nil
  local timer = vim.loop.new_timer()

  return function(...)
    local args = { ... }
    local call_original = vim.schedule_wrap(function()
      last_call = vim.loop.now()
      fn(unpack(args))
    end)

    if has_leading_call and last_call == nil then call_original() end

    timer:stop()
    timer:start(reset_duration, 0, call_original)
  end
end

return M
