# deckr41Nvim planning 

NeoVim plugin integrating LLMs as coding assistants with focus on prompt & context customization.

- Convention over configuration, infer, auto-detect
- "Tab coding" is "doom scrolling"
- Prioritize mnemonics and minimal keyboard shortcuts

- The files and project are the canvas, having a separate chat buffer seams a
  bit redundant. Maybe a scratch pad approach

## Milestone #2 - 

- [ ] Password manager integration for fetching API keys
- [ ] Support Ollama backend
- [ ] Implement auto (once in `insert` mode, default command is triggered) and on-demand () modes.
- [ ] Define and run commands in `visual` mode
    - [ ] Assign commands in `.d41rc` to specific modes (`insert`, `visual`)
    - [ ] Run commands over selected text
- [ ] Private commands in `$HOME/.deckr41/commands.json`
- [ ] Assign commands to 

## Milestone #1 - Auto completion (MVP)

- [ ] Support multiple backends: OpenAI, Anthorpic
- [ ] Provide config auto-detection and reasonable defaults while still
  allowing full backend customization
- [ ] Customize prompts and contexts via local `.d41rc.json` files
- [ ] Implement real-time suggestion box with backend streaming
- [ ] Implement `on-demand` and `auto` mode. Default is `on-demand`. 
- [ ] Define and run commands in `insert` mode
    - [ ] Allow default command (Shift + ArrowRight)
    - [ ] Allow backend switching

## Component #0 - Storage

- [ ] Postgres DB

## Component #1 - Backend

- [ ] **[mvp]** Support OpenAI and Anthorpic
- [ ] **[mvp]** Stream or wait for entire response
- [ ] **[mvp]** Cancel running job/command 
- [ ] Support Ollama 

-------------

### Feature #2 - [DB#2] Implement SQLite and data persistence in existing commands

**Start**: Thursday, 16th May 2024
**End**:

- [x] Create `sh41 init [-hc|--health-check]` subcommand to check/setup the user's environment
  - [x] Separate `lib/db/init` and `lib/config/init` scripts
    - `lib/db/init` initializes the database as described in `$SH41_DB`
    - `lib/config/init` prepares the user's environment, e.g.
      `~/.config/shell41/.sh41rc`, with default values
    - Both script have a `-hc|--health-check` which dont modify the system,
      just check if everything is in place
  - [x] Support only `sqlite` db, `postgres` just the scaffold with no actual
    implementation

- [ ] Create `settings` schema, a generic key-value store for system settings
  like: default provider, default provider temperature, model, etc.
- [ ] Create `conversations`, `messages`, `users` and `agents` schemas
- [ ] Conversations must be attached to a `user_id` and `agent_id`

#### Side Quests

- [x] Update `log` utility script to support `LOG_LEVEL` environment variable
- [x] Add `install.sh` and `load.sh` scripts
  - Meant to be curl'd and executed in the user's environment
  - Clone the repo into `~/.shell41` 
  - Run `sh41 init`
  - Detect user's shell and source the `load.sh` 
  - `load.sh` creates all the necesary environment variables and sources both
    `~/.config/shell41/.sh41rc` and `~/.config/shell41/.env` files
  - `.env` file is meant for sensitive information like passwords and ignored
    by a local `.gitignore` file
- [x] Add `sh41 update` subcommand to `git pull` the repo and run `sh41 init` 
- [x] Update `lib/conversations/build` with `--meta` functionality, allowing
  the user to add extra information to a conversation, e.g. `--meta commit-sha
  $(git rev-parse HEAD)`
- [x] Update `log` utility script to support `-v|--var <name> <value>`
  ```sh
  log error \
    -v "\$SH41_DB_CONNECTION" "$SH41_DB_CONNECTION" \
    "DB file does not exist"
  ```

-------------

### Feature #1 - [DB#1] Introduce the concept of databases

**Start**: Tuesday, 14th May 2024 
**End**: Thursday, 16th May 2024

- [x] Database #1 - introduce the concept of databases
  - [x] `sh41 db` subcommand, `db` home in `lib`
  - [x] `$SH41_DB` global var, `sqlite://file.db` or
    `postgres://user:pass@host/db`
  - [x] Add db health check in main `bin/sh41` entry if `$SH41_DB` is set

#### Side Quests

- [x] Refactor `bin/subcommands/*` to map 1:1 and serve as entry points for
  underlying `lib/*` 
  - [x] Deprecate `bin/subcommands/send` and move it to `lib/providers/send`
  - [x] Move 3rd party backend intergrations in `lib/providers/backend`
- [x] Add `--tag` functionality to `lib/conversations/build`, 
  e.g. `--tag app/name --tag mission/commit-msg`
