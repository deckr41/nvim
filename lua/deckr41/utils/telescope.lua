local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.config").values.generic_sorter
local previewers = require("telescope.previewers")

--- @class TelescopeUtils
local M = {}

--- @class Item
--- @field id string
--- @field label string
--- @field description string

-- Select a item from a list using Telescope
--- @param opts { items: Item[], title: string, onSelect: fun(item: Item) }
--- @return nil
M.select = function(opts)
  local items = opts.items
  local title = opts.title
  local onSelect = opts.onSelect or function() end

  pickers
    .new({}, {
      prompt_title = title or "Select item:",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.label,
            ordinal = entry.label,
          }
        end,
      }),
      sorter = sorters({}),

      -- Show the description of the selected item/command in the preview pane
      previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          local long_text = entry.value.description
            or "No description available."
          vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            0,
            -1,
            false,
            vim.split(long_text, "\n")
          )
        end,
      }),

      -- Once selected, pass the item to onSelect callback and close the pane
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          onSelect(selection.value)
        end)
        return true
      end,
    })
    :find()
end

return M
