# Poorman JIRA

- Convention over configuration, infer, auto-detect
- "Tab coding" is "doom scrolling"
- Prioritize mnemonics and minimal keyboard shortcuts
- The files and project are the canvas, having a separate chat buffer seams
  a bit redundant. Maybe a scratch pad approach.

---

## Milestone #1

- Tree based `.d41rc` loading
- INSERT/VISUAL/NORMAL modes command running
- Backend/model runtime switching

---

## Component #0 - Core

- [ ] Switch `active_backend` and `active_model` at runtime - `Shift+Down` + select boxes
- [ ] Switch `mode` at runtime - `Shift+Left`
- [ ] Run commands in VISUAL/NORMAL mode
    - VISUAL uses the selected text in `FULL_TEXT` var
    - NORMAL uses the entire buffer text in `FULL_TEXT` var
    - [ ] Select command drop-down menu next to cursor
- [x] On-demand mode, `easy-does-it`, keybindings trigger loading
    - [x] Run `default_command` - `Shift + ArrowRight`
    - [x] Run `default_double_command` - `Shift + 2xArrowRight`
- [x] Real-time mode, `r-for-rocket`, automatic in insert mode as you're typing
    - [ ] Customize default command in `mode` config
    - [x] Run default command
- [x] Cancel running job/command when moving cursor

## Component #1 - Backend

- [ ] Dynamic model fetching and caching
- [ ] Ollama support 
- [x] Anthorpic support
- [x] OpenAI support

## Component #2 - Commands

- [ ] Tree based `.d41rc` command loading and arbitration
    - [ ] Scan and load `.d41rc` files up the directory tree, populate internal
      tree structure on the fly as commands are ran in files. This is to avoid
      scanning the entire dir structure recursively at startup.
    - [ ] Recognize a file with `"root": true` to stop further scanning
    - [ ] Implement error handling for missing or malformed `.d41rc` files
    - [ ] Implement top-down deep merging of commands from `.d41rc` files
    - [ ] Validate `.d41rc` files against the schema during loading
- [x] Watch for changes of already registered `.d41rc` files and reload
- [x] Customize prompts and contexts via internal `.d41rc`

## Component #3 - Suggestion

- [ ] Move meta bar to a separate window with `toml` syntax 
- [x] Implement real-time suggestion box

