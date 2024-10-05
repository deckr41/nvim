# Lua Code Standards

## To the point

Write as if characters are oxygen and we're on a trip to Mars. Convey the
message in as few words possible while transmitting the most information. 

Use George Orwell's [rules for writing prose][george-orwell] to make your
comments clear and concise.

[george-orwell]: https://en.wikipedia.org/wiki/George_Orwell#Influence_on_language_and_writing

**Bad**:

```lua
-- This function is used to calculate the sum of two numbers a and b by adding
-- them together.
function add(a, b)
  return a + b
end
```

**Good**:

```lua
-- Calculate the sum of two numbers.
function add(a, b)
  return a + b
end
```

## Purism

- Prioritize a fat "utility" layer, with pure helper function, and skinny
  domain logic.
- Expose only necessary functions as public methods; keep other functions
  private to enhance encapsulation.
- Avoid creating unnecessary abstractions. Keep code simple and direct. 
- Give it some time before abstracting, a wrong or premature abstraction is
  harder to reason and/or revert that a simple duplication.

## Naming

- Use descriptive names for functions, variables, parameters etc. 
- Use `snake_case` for Variables, instances and methods, and `CamelCase` for
  modules (e.g. `local MyModule = require("my_module")`, `local my_variable =
  MyModule.do_work()`).

## Comments and Types

- Use `---` for documentation comments and `--` for inline comments. 
- Annotate functions with type annotations (e.g., `@generic`, `@param`,
  `@return`).

## Functions

- Functions are always verbs: Begin function names with action verbs to clearly
  indicate their purpose (e.g., `get_item`, `set_value`, `update_state`,
  `create_buffer`, `delete_entry`, `build_list`, `ensure_exists`,
  `gather_data`).
- Pass options as a table when there are multiple optional parameters instead
  of multiple parameters.

## Terminology

- **Dictionary or Object (Named Table)**: A table with key-value pairs, where keys are
  not necessarily consecutive integers.
- **Array (Indexed Table)**: A table with consecutive integer keys starting
  from 1.

## Performance

Avoid `table.insert` in big or frequent loops; use direct assignment for better
performance.

```lua
--- Extract the values from a dictionary (named table) and return them as
--- an array (indexed table)
--- @generic T
--- @param dict table<any, T>
--- @return T[]
M.values = function(dict)
  local result_array = {}
  for _, value in pairs(dict) do
    result_array[#result_array + 1] = value -- More efficient than table.insert in a loop
  end
  return result_array
end
```

## Module structure

### Pure functional utilities (stateless)

Use simple tables and functions, comments and type annotations.

```lua
--- @class ArrayUtils
local M = {}

--- Find the first element in an array (indexed table) that satisfies
--- the `is_the_one` predicate function.
--- @generic T
--- @param haystack_array T[] The array to iterate over.
--- @param is_the_one fun(needle: T): boolean A function that checks if an element is found.
--- @return T|nil: The first element found, otherwise `nil`.
M.find_first = function(haystack_array, is_the_one)
  for _, straw in ipairs(haystack_array) do
    if is_the_one(straw) then return straw end
  end
  return nil
end

--- Get the first element in an array (indexed table) that satisfies
--- the `is_the_one` predicate function.
---
--- Similar to `find_first`, but throws an error if no element found.
--- @generic T
--- @param haystack_array T[] The array to iterate over.
--- @param is_the_one fun(needle: T): boolean A function that checks if an element is found.
--- @return T: The first element found, otherwise throw.
M.get_first = function(haystack_array, is_the_one)
  for _, straw in ipairs(haystack_array) do
    if is_the_one(straw) then return straw end
  end
  error("Element not found")
end

return M
```

### Domain modules (statefull) 

```lua
--- @class SomeModule
local M = {}

--- @class SomeModuleConfig
local config = {
  -- fields that drive behaviour and can generaly be overwitten by the user
}

--- @class SomeModuleState
--- @field secret_souce string
local state = {
  -- internal state properties
  secret_souce = "it's not that easy"
}

--- @param opts ModuleSetupOpts
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- initialization here
}

--- @class PrivateMethodOpts
--- @field context string
--- @field question string

--- Do magic, but in private.
--- @field opts PrivateMethodOpts
--- @return string
local private_method = function(opts)
  -- Focus on not relying on `config` and `state`, keep these private functions
  -- pure, for better encapsulation and easier testing.
end

--- Do magic
--- @field input string
--- @return string
M.public_method = function(input)
  -- Use `state` and `config` globals to drive domain logic.
  --
  -- Externalize to private function where possible repeatable parts relevant
  -- to this module.
  --
  -- Externalize to Utility layer functions that are domain agnostic and can 
  -- be reused across other modules.
  return private_method({
    context = state.secret_souce,
    question = input
  })
end

return M
```
