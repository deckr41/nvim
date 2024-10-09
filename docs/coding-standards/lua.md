# Lua Coding Standards

## Brevity and Clarity

Write code and comments that are concise yet informative. Use the minimum
number of words necessary to convey maximum meaning. 

Follow George Orwell's [rules for writing prose][george-orwell] to ensure
clarity.

[george-orwell]: https://en.wikipedia.org/wiki/George_Orwell#Influence_on_language_and_writing

**Bad**:

```lua
-- This function is used to calculate the sum of two numbers a and b by 
-- adding them together.
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

## Purity and Simplicity

- **Fat Utilities & Lean Domain**: Prioritize beefing up the utility layer with
  pure helper functions and keep domain logic small.
- **Need to know**: Expose only necessary functions as public methods; keep
  others private to enhance encapsulation.
- **Resist premature abstraction**: Delay abstraction until patterns emerge;
  premature abstraction can complicate code more than duplication.

## Naming Conventions

- Use descriptive names for functions, variables, and parameters.
- Use `snake_case` for variables, instances, and methods.
- Use `CamelCase` for modules.  

**Example**:

```lua
local MyModule = require("my_module")
local my_variable = MyModule.do_work()
```

## Comments and Type Annotations

- Use `---` for documentation comments and `--` for inline comments.
- Annotate functions with type annotations (e.g., `@generic`, `@param`, `@return`).

## Function Naming

- Functions should be verbs that begin with action words to clearly indicate
  their purpose (e.g., `get_item`, `set_value`, `update_state`, `create_buffer`,
  `delete_entry`, `build_list`, `ensure_exists`, `gather_data`).
- For functions with multiple optional parameters, pass options as a table.

### Use Guard Clauses

- **Prioritize Guard Clauses**: Handle edge cases or error conditions at the
  beginning of functions.
- **Early Returns**: Return early when conditions are not met to avoid deep
  nesting.
- **Improve Readability**: This practice keeps the main logic less indented and
  easier to follow.

**Bad:**

```lua
local process_data = function(data)
  if data then
    if data.is_valid then
      -- Main logic here.
    else
      error("Data is invalid")
    end
  else
    error("Data is required")
  end
end
```

**Good**:

```lua
local process_data = function(data)
  if not data then
    error("Data is required")
  end
  if not data.is_valid then
    error("Data is invalid")
  end
  -- Main logic here.
end
```

## Terminology

- **Dictionary (Table with Named Keys)**: A table with key-value pairs where
  keys are not necessarily consecutive integers.
- **Array (Indexed Table)**: A table with consecutive integer keys starting
  from 1.

## Performance Considerations

- Avoid `table.insert` in large or frequent loops; use direct assignment for
  better performance.

```lua
--- Extract values from a dictionary into an array.
--- @generic T
--- @param dict table<any, T>
--- @return T[]
M.values = function(dict)
  local result = {}
  for _, value in pairs(dict) do
    result[#result + 1] = value -- More efficient than table.insert
  end
  return result
end
```

- When in doubt between performance and immutability, provide an option:

```lua
--- Reverse the order of items in an array.
--- Set `mutate = true` to reverse in place; default is `false`.
--- @generic T
--- @param array T[]
--- @param opts? { mutate?: boolean }
--- @return T[]
M.reverse = function(array, opts)
  opts = opts or {}
  local size = #array

  if opts.mutate then
    for i = 1, math.floor(size / 2) do
      array[i], array[size - i + 1] = array[size - i + 1], array[i]
    end
    return array
  else
    local new_array = {}
    for i = 1, size do
      new_array[i] = array[size - i + 1]
    end
    return new_array
  end
end
```

## Code and Folder Structure

- `lua/your_module/utils/`: Pure helper functions (e.g., `fs.lua`,
  `string.lua`, `array.lua`, `nvim.lua`).
- `lua/your_module/ui/`: Neovim UI primitives (e.g., `select.lua`,
  `textarea.lua`, `tabs.lua`).
- `lua/your_module/`: Domain-specific logic (e.g., `backend.lua`,
  `keyboard.lua`, `commands/init.lua`, `commands/tree.lua`).

Aim for:

- **Fat Utility Layer**: Create as many reusable primitives as possible;
  they are easier to test and maintain.
- **Lean Domain Layer**: Compose utilities with minimal domain logic.

## Error Handling

- **Graceful Degradation**: Always handle potential errors gracefully to
  prevent crashes.
- **Protected Calls**: Use `pcall` and `xpcall` for functions that might throw
  errors.
- **Meaningful Errors**: Provide clear and informative error messages to aid in
  debugging.

```lua
local success, result = pcall(function()
  -- Code that might throw an error.
  return risky_operation()
end)
if not success then
  error("Error occurred: " .. result)
end
-- Main logic here.
```

## Modules

### Pure Functional Utilities (Stateless)

Use simple tables and functions with comments and type annotations.

```lua
--- @class ArrayUtils
local M = {}

--- Find the first element in an array that satisfies a predicate.
--- @generic T
--- @param array T[] The array to search.
--- @param predicate fun(item: T): boolean The predicate function.
--- @return T|nil The first matching element or `nil`.
M.find_first = function(array, predicate)
  for _, item in ipairs(array) do
    if predicate(item) then
      return item
    end
  end
  return nil
end

--- Get the first element in an array that satisfies a predicate.
--- Throws an error if no element is found.
--- @generic T
--- @param array T[] The array to search.
--- @param predicate fun(item: T): boolean The predicate function.
--- @return T The first matching element.
M.get_first = function(array, predicate)
  local item = M.find_first(array, predicate)
  if item then
    return item
  else
    error("Element not found")
  end
end

return M
```

### Domain Modules (Stateful)


Stateful modules maintain internal `state` and user `config` tables, similar to
singletons. When designing such modules:

- **Encapsulation**: Keep the `state` and `config` tables private to the
  module. Expose only necessary functions to the user.
- **Initialization**: Provide a `setup` function to initialize the module with
  user-defined configurations.
- **Avoid Global State**: Do not use global variables. Keep all module-related
  data within the module scope.
- **Pure Functions**: Whenever possible, write pure functions that do not rely
  on module state. This makes testing and maintenance easier.
- **Clear API**: Expose a clear and minimal public API. Document the public
  methods and their usage.

**Example**:

```lua
--- @class MyStatefulModule
local M = {}

--- @class MyStatefulModuleConfig
local config = {
  -- Default configuration options.
}

--- @class MyStatefulModuleState
local state = {
  -- Internal state variables.
}

--- Initialize the module with user options.
--- @param opts table
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  -- Additional initialization logic.
end

--- Public method that utilizes module state and config.
--- @param input any
--- @return any
M.do_something = function(input)
  -- Logic using `state` and `config`.
end

return M
```

### Instantiable Domain Modules

Instantiable modules create independent instances using functions and closures, avoiding inheritance and metatables. 

Factory functions generate objects, encapsulating `state` and `config` within closures for privacy. Methods are directly attached to the instance, ensuring isolated state management.

- **Factory Functions**: Use functions that return new instances to create
  multiple independent objects.
- **Closure for State**: Encapsulate instance-specific `state` and `config`
  within the closure to prevent external access.
- **No Inheritance or Metatables**: Simplify design by avoiding complex
  features; rely on plain tables and functions.
- **Instance Methods**: Attach methods directly to the instance table returned
  by the factory function.
- **Isolation**: Ensure each instance maintains its own state without affecting
  others.

**Example**:

```lua
--- @class MyInstantiableModule
local M = {}

--- Create a new instance.
--- @param opts table
--- @return MyModuleInstance
M.build = function(opts)
  --- @class MyModuleInstance
  local instance = {}

  --- @class MyModuleInstanceConfig
  local config = vim.tbl_extend("force", {
    -- Default instance configuration.
  }, opts or {})

  --- @class MyModuleInstanceState
  local state = {
    -- Instance-specific state variables.
  }

  --- Private method within the instance.
  local private_method = function()
    -- Internal logic specific to this instance.
  end

  --- Public method exposed by the instance.
  --- @param input any
  --- @return any
  instance.public_method = function(input)
    -- Use `state` and `config` for instance-specific logic.
    private_method()
    -- Return result based on processing.
  end

  return instance
end

return M
```
