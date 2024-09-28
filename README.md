# deckr41/nvim

> A Neovim plugin that augments coding with 🤖 LLM capabilities, allowing
> per-project AI customization through 📂 collocated `.d41rc` files that serve
> as agents for your project folders—think monorepo packages.

![On demand, one-line autocompletion with Anthropic](docs/screenshot_finish-line.png)

:construction: **Prompt Engineering**  

- Customize AI behavior with `commands` in `.d41rc` files.
- Turn folders into AI agents, facilitating multi-agent workflows.

:gear: **Multiple gears**  

- **On-demand**: Unblock with `<Shift-RightArrow>`.  
  Use LLM suggestions when stuck, saving yourself a web search without breaking
  flow.  
  Run custom commands for exploration and learning.
- **Real-time**: Get as-you-type suggestions with a configurable timeout.  
  Tread carefully, *tab-coding* rhymes with *doom-scrolling*.

:hammer: **Tools** *(Work in Progress)*  

- Extend AI with custom tools for tasks like computations and API interactions.

:mag: **Semantic Search** *(Work in Progress)*  

- Link files or perform project-wide semantic searches to enhance AI context.

:books: **Retrieval-Augmented Generation (RAG) with
[DevDocs](https://github.com/freeCodeCamp/devdocs/tree/main)** *(Work in
Progress)*  
- Integrate with [devdocs.io](https://devdocs.io/) for accurate, context-rich
  AI responses.

## Table of contents

<!-- vim-markdown-toc GFM -->

* [Installation](#installation)
    * [Minimal Configuration](#minimal-configuration)
    * [Modes](#modes)
    * [Full Configuration Options](#full-configuration-options)
    * [Setting Up API Keys](#setting-up-api-keys)
* [Usage](#usage)
    * [Default Keybindings](#default-keybindings)
    * [Commands](#commands)
* [Understanding `.d41rc`](#understanding-d41rc)
    * [Structure and Commands](#structure-and-commands)
    * [Variable Interpolation](#variable-interpolation)
* [Development](#development)
    * [Code overview](#code-overview)
* [Credits](#credits)

<!-- vim-markdown-toc -->

## Installation

### Minimal Configuration

To get started, you just need `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`
environment variables set. If both are set, Anthropic is used.

**Example for `lazy.nvim`**:

```lua
{
  "deckr41/nvim",
  event = { "BufEnter" },
  opts = {}
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
}
```

### Modes

- **`easy-does-it`** - Suggestions on demand with `<S-Right>`:
    - Pressing once will run the [`finish-line`](.d41rc#L5) command
    - Twice will run [`finish-block`](.d41rc#L38)
- **`r-for-rocket`** - Real-time suggestions with 1000ms debounce in INSERT
  mode. 

See `modes` key in configuration for setup.

### Full Configuration Options

Below is the default configuration with all available settings:

```lua
opts = {
  --
  -- Mode configuration
  --
  modes = {
    ["easy-does-it"] = {
      -- Command triggered by pressing `<S-Right>` once.
      command = "finish-line",

      -- Command triggered by pressing `2x<S-Right>` quickly.
      double_command = "finish-block",
    },
    ["r-for-rocket"] = {
      -- Command triggered when entering or writing in INSERT mode
      command = "finish_block",

      -- Debounce timeout in milliseconds, relevant for `r-for-rocket` mode
      timeout = 1000,
    },
  },
  active_mode = "easy-does-it",

  --
  -- Backend configurations
  --
  backends = {
    openai = {
      url = "https://api.openai.com/v1/chat/completions",
      api_key = os.getenv("OPENAI_API_KEY"),
      default_model = "gpt-4o-mini",
      available_models = {
        ["gpt-4o"] = { max_tokens = 4096 },
        ["gpt-4o-2024-08-06"] = { max_tokens = 16384 },
        ["gpt-4o-mini"] = { max_tokens = 16384 },
      },
      temperature = 0.2,
    },
    anthropic = {
      url = "https://api.anthropic.com/v1/messages",
      api_key = os.getenv("ANTHROPIC_API_KEY"),
      default_model = "claude-3-5-sonnet-20240620",
      available_models = {
        ["claude-3-5-sonnet-20240620"] = { max_tokens = 1024 },
      },
      temperature = 0.2,
    },
  },

  -- If not specified, the auto-detect backed is used. 
  -- If both are active, Anthropic is used.
  active_backend = nil,

  -- If not specified, the backend's `default_model` is used.
  active_model = nil, 
}
```

### Setting Up API Keys

Add keys to your shell profile file (`.bashrc`, `.zshrc`, etc.):

```sh
export OPENAI_API_KEY="your-openai-api-key"
export ANTHROPIC_API_KEY="your-anthropic-api-key"
```

## Usage

### Default Keybindings

**INSERT** mode:

- `<S-Right>`: Trigger suggestions.
  - Press `<S-Right>` once will trigger the `finish-line` command.
  - Press `<S-Right>` twice quickly will trigger the `finish-block` command.
- `<Tab>`, `<S-Right>`: Accept suggestion.
- `<Escape>`: Dismiss suggestion.

**VISUAL** mode: *(Work in Progress)*

**NORMAL** mode: *(Work in Progress)*

### Commands

- **`:D41Eject`**: Ejects the default `.d41rc` file into your current working
  directory for customization.

## Understanding `.d41rc`

`.d41rc` files configure AI behavior and commands per project. Multiple files
can coexist, allowing flexible customization.

- Commands are loaded from `.d41rc` files up the directory tree, stopping at
  the first file with `"root": true`. *(Work in Progress)*
- Commands merge top-down, so closer `.d41rc` files can override those above,
  with deep merging for selective changes, for example allowing the addition of
  certain context files to an existing command. *(Work in Progress)*

### Structure and Commands

Each `.d41rc` is a JSON object containing commands:

```json
{
  "$schema": ".d41rc-schema.json",
  "commands": [
    {
      "id": "zen-one-shot",
      "system_prompt": [
        "You are a Zen master named Zero, the master of one-liners.",
        "You will respond similar to how a Zen master would, in koans, short and succinct riddles, analogies or metaphors.",
        "Now. Take a deep breath. Each word written unfolds the answer."
      ],
      "prompt": [
        "${FULL_TEXT}"
      ],
      "temperature": 0.7,
      "max_tokens": 100
    }
  ]
}
```

Refer to the schema definition [here](.d41rc-schema.json).

### Variable Interpolation

The `system_prompt` and `prompt` fields support dynamic variable interpolation:

- **`${FILE_PATH}`**: Current file path.
- **`${FILE_SYNTAX}`**: Current file's language.
- **`${FILE_CONTENT}`**: Entire document.
- **`${LINES_BEFORE_CURRENT}`**: Code before the line.
- **`${TEXT_BEFORE_CURSOR}`**: Text before cursor.
- **`${LINES_AFTER_CURRENT}`**: Code after the line.

## Development

### Code overview

The plugin's architecture is modular, with each component responsible for a
clear, isolated piece of domain.

![Plugin code overview diagram](docs/code-overview.png)

## Credits

- Inspired by [llm.nvim](https://github.com/melbaldove/llm.nvim) and
  [ell](https://github.com/MadcowD/ell).

