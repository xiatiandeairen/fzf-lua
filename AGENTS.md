# AGENTS.md

## Cursor Cloud specific instructions

This is **fzf-lua**, a Neovim plugin written in Lua that provides fuzzy finder functionality powered by fzf. It runs inside Neovim, not as a standalone application.

### Key services and how to run them

| Task | Command | Notes |
|------|---------|-------|
| Run all tests | `make test` | Requires plenary.nvim at `../plenary.nvim` relative to workspace |
| Run single test | `make FILE=tests/path_spec.lua test-file` | Replace path with desired test file |
| Lint (format check) | `stylua --check lua/` | Uses `.stylua.toml` config; exit code 1 = formatting diffs exist |
| Load plugin in Neovim | `nvim -u NONE -c "set rtp+=." -c "lua require('fzf-lua').setup()"` | Run from workspace root |
| Quick interactive demo | `sh scripts/mini.sh` | Launches sandboxed Neovim with fzf-lua + devicons |

### Non-obvious caveats

- **plenary.nvim location**: The Makefile and `tests/minimal_init.lua` expect plenary.nvim at `../plenary.nvim` relative to the workspace. Since `/workspace` is the repo root and its parent is `/`, plenary must be cloned to `/plenary.nvim`. Use `sudo git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git /plenary.nvim`.
- **fzf-lua symlink**: `tests/minimal_init.lua` also adds `../fzf-lua` to runtimepath. A symlink `sudo ln -sf /workspace /fzf-lua` is needed so the tests find the plugin.
- **nvim-web-devicons for devicons tests**: `tests/devicons_spec.lua` requires nvim-web-devicons at the lazy.nvim data path (`~/.local/share/nvim/lazy/nvim-web-devicons`). Clone and symlink if you need those tests. The devicons tests have known failures with Neovim 0.10+ related to `termguicolors` defaults.
- **fd / bat naming**: On Ubuntu, `fd` is `fdfind` and `bat` is `batcat`. Symlinks to `/usr/local/bin/fd` and `/usr/local/bin/bat` are needed.
- **No build step**: This is a pure Lua plugin with no compilation or build step required.
- **StyLua formatting**: The existing codebase has formatting diffs reported by `stylua --check lua/` (47 files). This is pre-existing and not a setup issue.
