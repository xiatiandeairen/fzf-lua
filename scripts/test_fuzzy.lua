--- Minimal interactive fuzzy search test — no rg/fd/bat/git needed.
--- All data comes from Lua tables, only requires Neovim + fzf.
---
--- Usage:
---   nvim -u scripts/test_fuzzy.lua
---
--- Keybindings:
---   <C-p>  file paths (mock file tree)
---   <C-g>  grep results (mock grep output)
---   <C-l>  live search (dynamic reload on each keystroke)
---   <C-t>  custom multi-select (actions demo)
---   <C-k>  builtin commands list
---   q      quit

vim.o.termguicolors = true
vim.o.number = true
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local fzf = require("fzf-lua")

fzf.setup({
  defaults = { git_icons = false, file_icons = false },
  winopts = { height = 0.7, width = 0.7 },
})

----------------------------------------------------------------------------
-- Mock datasets
----------------------------------------------------------------------------

local MOCK_FILES = {
  "lua/fzf-lua/init.lua",
  "lua/fzf-lua/core.lua",
  "lua/fzf-lua/fzf.lua",
  "lua/fzf-lua/path.lua",
  "lua/fzf-lua/utils.lua",
  "lua/fzf-lua/config.lua",
  "lua/fzf-lua/win.lua",
  "lua/fzf-lua/shell.lua",
  "lua/fzf-lua/libuv.lua",
  "lua/fzf-lua/devicons.lua",
  "lua/fzf-lua/class.lua",
  "lua/fzf-lua/cmd.lua",
  "lua/fzf-lua/make_entry.lua",
  "lua/fzf-lua/providers/files.lua",
  "lua/fzf-lua/providers/grep.lua",
  "lua/fzf-lua/providers/git.lua",
  "lua/fzf-lua/providers/lsp.lua",
  "lua/fzf-lua/providers/buffers.lua",
  "lua/fzf-lua/providers/tags.lua",
  "lua/fzf-lua/providers/diagnostics.lua",
  "lua/fzf-lua/providers/quickfix.lua",
  "lua/fzf-lua/providers/colorschemes.lua",
  "lua/fzf-lua/providers/manpages.lua",
  "lua/fzf-lua/previewer/builtin.lua",
  "lua/fzf-lua/previewer/fzf.lua",
  "lua/fzf-lua/previewer/codeaction.lua",
  "tests/path_spec.lua",
  "tests/init_spec.lua",
  "tests/utils_spec.lua",
  "tests/libuv_spec.lua",
  "tests/devicons_spec.lua",
  "tests/fuzzy_spec.lua",
  "scripts/init.lua",
  "scripts/mini.sh",
  "scripts/test_fuzzy.lua",
  "README.md",
  "Makefile",
  "LICENSE",
  ".editorconfig",
  ".gitignore",
  ".luarc.jsonc",
  ".stylua.toml",
}

local MOCK_GREP = {
  "lua/fzf-lua/core.lua:135:1:M.fzf_exec = function(contents, opts)",
  "lua/fzf-lua/core.lua:198:1:M.fzf_live = function(contents, opts)",
  "lua/fzf-lua/core.lua:223:1:M.fzf_wrap = function(opts, contents)",
  "lua/fzf-lua/init.lua:1:1:local M = {}",
  "lua/fzf-lua/init.lua:377:1:M.fzf_exec = require('fzf-lua.core').fzf_exec",
  "lua/fzf-lua/init.lua:378:1:M.fzf_live = require('fzf-lua.core').fzf_live",
  "lua/fzf-lua/init.lua:379:1:M.fzf_wrap = require('fzf-lua.core').fzf_wrap",
  "lua/fzf-lua/path.lua:10:1:local M = {}",
  "lua/fzf-lua/path.lua:50:1:function M.tail(s)",
  "lua/fzf-lua/path.lua:88:1:function M.extension(s)",
  "lua/fzf-lua/path.lua:120:1:function M.parent(s)",
  "lua/fzf-lua/path.lua:180:1:function M.normalize(s)",
  "lua/fzf-lua/utils.lua:11:1:local M = {}",
  "lua/fzf-lua/utils.lua:120:1:M.strsplit = function(inputstr, sep)",
  "lua/fzf-lua/utils.lua:200:1:M.tbl_count = function(t)",
  "lua/fzf-lua/utils.lua:350:1:M.ansi_codes = setmetatable({}, { ... })",
  "lua/fzf-lua/config.lua:1:1:local path = require('fzf-lua.path')",
  "lua/fzf-lua/config.lua:50:1:function M.normalize_opts(opts, defaults)",
  "lua/fzf-lua/fzf.lua:41:1:function M.raw_fzf(contents, fzf_cli_args, opts)",
  "lua/fzf-lua/win.lua:1:1:local utils = require('fzf-lua.utils')",
}

local MOCK_SYMBOLS = {
  "[function] fzf_exec      lua/fzf-lua/core.lua:135",
  "[function] fzf_live       lua/fzf-lua/core.lua:198",
  "[function] fzf_wrap       lua/fzf-lua/core.lua:223",
  "[function] raw_fzf        lua/fzf-lua/fzf.lua:41",
  "[function] tail           lua/fzf-lua/path.lua:50",
  "[function] extension      lua/fzf-lua/path.lua:88",
  "[function] parent         lua/fzf-lua/path.lua:120",
  "[function] normalize      lua/fzf-lua/path.lua:180",
  "[function] strsplit       lua/fzf-lua/utils.lua:120",
  "[function] tbl_count      lua/fzf-lua/utils.lua:200",
  "[function] normalize_opts lua/fzf-lua/config.lua:50",
  "[table]    M              lua/fzf-lua/init.lua:1",
  "[table]    ansi_codes     lua/fzf-lua/utils.lua:350",
  "[string]   nbsp           lua/fzf-lua/utils.lua:60",
  "[boolean]  __HAS_NVIM_010 lua/fzf-lua/utils.lua:17",
}

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function on_select(selected)
  if not selected or #selected == 0 then return end
  vim.notify("Selected: " .. selected[1], vim.log.levels.INFO)
end

local function on_multi_select(selected)
  if not selected or #selected == 0 then return end
  local msg = string.format("Selected %d items:\n%s",
    #selected, table.concat(selected, "\n"))
  vim.notify(msg, vim.log.levels.INFO)
end

----------------------------------------------------------------------------
-- Keybindings
----------------------------------------------------------------------------

-- <C-p>  Fuzzy file search (mock data, no fd/rg needed)
vim.keymap.set("n", "<C-p>", function()
  fzf.fzf_exec(MOCK_FILES, {
    prompt = "MockFiles❯ ",
    actions = { ["default"] = on_select },
  })
end)

-- <C-g>  Fuzzy grep search (mock data, no rg needed)
vim.keymap.set("n", "<C-g>", function()
  fzf.fzf_exec(MOCK_GREP, {
    prompt = "MockGrep❯ ",
    fzf_opts = { ["--delimiter"] = ":", ["--nth"] = "4.." },
    actions = { ["default"] = on_select },
  })
end)

-- <C-l>  Live reload search (simulates live_grep with Lua function)
vim.keymap.set("n", "<C-l>", function()
  fzf.fzf_live(function(query)
    if not query or #query == 0 then return MOCK_GREP end
    local filtered = {}
    local q = query:lower()
    for _, line in ipairs(MOCK_GREP) do
      if line:lower():find(q, 1, true) then
        table.insert(filtered, line)
      end
    end
    return filtered
  end, {
    prompt = "MockLiveGrep❯ ",
    exec_empty_query = true,
    actions = { ["default"] = on_select },
  })
end)

-- <C-t>  Multi-select symbols demo
vim.keymap.set("n", "<C-t>", function()
  fzf.fzf_exec(MOCK_SYMBOLS, {
    prompt = "MockSymbols❯ ",
    fzf_opts = { ["--multi"] = true },
    actions = {
      ["default"] = on_multi_select,
    },
  })
end)

-- <C-k>  fzf-lua built-in commands (real data, always available)
vim.keymap.set("n", "<C-k>", function()
  fzf.builtin()
end)

-- q  Quit
vim.keymap.set("n", "q", "<Cmd>qa!<CR>")

----------------------------------------------------------------------------
-- Welcome message
----------------------------------------------------------------------------

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local lines = {
      "╔══════════════════════════════════════════════════════════╗",
      "║         fzf-lua 模糊搜索本地测试 (无需三方工具)        ║",
      "╠══════════════════════════════════════════════════════════╣",
      "║  <C-p>  模拟文件搜索 (Mock files)                      ║",
      "║  <C-g>  模拟 Grep 搜索 (Mock grep output)              ║",
      "║  <C-l>  模拟 Live Grep (动态重载)                      ║",
      "║  <C-t>  模拟符号搜索 + 多选 (Mock symbols + Tab)       ║",
      "║  <C-k>  fzf-lua 内置命令列表 (Builtin)                 ║",
      "║  q      退出                                           ║",
      "╚══════════════════════════════════════════════════════════╝",
    }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  end,
})
