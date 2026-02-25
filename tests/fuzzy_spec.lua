---@brief Headless fuzzy search pipeline tests.
-- Only requires Neovim + fzf binary, no rg/fd/bat/git needed.
-- Uses `fzf --filter` for non-interactive headless matching.
-- Run: make FILE=tests/fuzzy_spec.lua test-file

local fzf_lua = require("fzf-lua")
local path = fzf_lua.path
local utils = fzf_lua.utils

-- Simulated file tree for testing (no filesystem access needed)
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
  "lua/fzf-lua/make_entry.lua",
  "lua/fzf-lua/providers/files.lua",
  "lua/fzf-lua/providers/grep.lua",
  "lua/fzf-lua/providers/git.lua",
  "lua/fzf-lua/providers/lsp.lua",
  "lua/fzf-lua/providers/buffers.lua",
  "lua/fzf-lua/previewer/builtin.lua",
  "lua/fzf-lua/previewer/fzf.lua",
  "tests/path_spec.lua",
  "tests/init_spec.lua",
  "tests/utils_spec.lua",
  "tests/fuzzy_spec.lua",
  "scripts/init.lua",
  "README.md",
  "Makefile",
  "LICENSE",
}

-- Simulated grep output lines
local MOCK_GREP = {
  "lua/fzf-lua/core.lua:135:M.fzf_exec = function(contents, opts)",
  "lua/fzf-lua/core.lua:198:M.fzf_live = function(contents, opts)",
  "lua/fzf-lua/core.lua:223:M.fzf_wrap = function(opts, contents)",
  "lua/fzf-lua/init.lua:1:local M = {}",
  "lua/fzf-lua/init.lua:377:M.fzf_exec = require('fzf-lua.core').fzf_exec",
  "lua/fzf-lua/path.lua:10:local M = {}",
  "lua/fzf-lua/path.lua:50:function M.tail(s)",
  "lua/fzf-lua/path.lua:88:function M.extension(s)",
  "lua/fzf-lua/utils.lua:120:M.strsplit = function(inputstr, sep)",
  "lua/fzf-lua/utils.lua:200:M.tbl_count = function(t)",
}

--- Run fzf --filter in headless mode, returns matched lines
---@param items string[] input lines
---@param query string fuzzy query
---@return string[] matched lines (ordered by fzf ranking)
local function fzf_filter(items, query)
  local input = table.concat(items, "\n")
  local cmd = string.format("printf '%%s' %s | fzf --filter=%s",
    vim.fn.shellescape(input),
    vim.fn.shellescape(query))
  local result = vim.fn.systemlist(cmd)
  -- Remove trailing empty strings
  while #result > 0 and result[#result] == "" do
    table.remove(result)
  end
  return result
end

describe("Fuzzy search pipeline", function()
  describe("fzf --filter basic matching", function()
    it("exact filename match", function()
      local results = fzf_filter(MOCK_FILES, "Makefile")
      assert.is.True(#results >= 1)
      assert.are.equal("Makefile", results[1])
    end)

    it("fuzzy partial match", function()
      local results = fzf_filter(MOCK_FILES, "init")
      assert.is.True(#results >= 2)
      local found_init = false
      local found_init_spec = false
      for _, r in ipairs(results) do
        if r == "lua/fzf-lua/init.lua" then found_init = true end
        if r == "tests/init_spec.lua" then found_init_spec = true end
      end
      assert.is.True(found_init, "should match lua/fzf-lua/init.lua")
      assert.is.True(found_init_spec, "should match tests/init_spec.lua")
    end)

    it("empty query returns all items", function()
      local results = fzf_filter(MOCK_FILES, "")
      assert.are.equal(#MOCK_FILES, #results)
    end)

    it("no match returns empty", function()
      local results = fzf_filter(MOCK_FILES, "zzzzxxxxxnonexistent")
      assert.are.equal(0, #results)
    end)

    it("case-insensitive matching (fzf default)", function()
      local results = fzf_filter(MOCK_FILES, "readme")
      assert.is.True(#results >= 1)
      local found = false
      for _, r in ipairs(results) do
        if r == "README.md" then found = true end
      end
      assert.is.True(found, "should match README.md case-insensitively")
    end)

    it("multi-word fuzzy matching", function()
      local results = fzf_filter(MOCK_FILES, "prov grep")
      assert.is.True(#results >= 1)
      assert.are.equal("lua/fzf-lua/providers/grep.lua", results[1])
    end)

    it("path separator matching", function()
      local results = fzf_filter(MOCK_FILES, "previewer/builtin")
      assert.is.True(#results >= 1)
      assert.are.equal("lua/fzf-lua/previewer/builtin.lua", results[1])
    end)
  end)

  describe("fzf --filter on grep-style output", function()
    it("match by function name", function()
      local results = fzf_filter(MOCK_GREP, "fzf_exec")
      assert.is.True(#results >= 2)
      local has_core = false
      for _, r in ipairs(results) do
        if r:match("core%.lua.*fzf_exec") then has_core = true end
      end
      assert.is.True(has_core, "should match fzf_exec in core.lua")
    end)

    it("match by line number pattern", function()
      local results = fzf_filter(MOCK_GREP, "path tail")
      assert.is.True(#results >= 1)
      assert.is.truthy(results[1]:match("path%.lua.*tail"))
    end)
  end)

  describe("fzf-lua data pipeline helpers", function()
    it("path.tail extracts filename correctly", function()
      for _, f in ipairs(MOCK_FILES) do
        local tail = path.tail(f)
        assert.is.truthy(tail and #tail > 0, "tail should not be empty for: " .. f)
        assert.is_nil(tail:find("/"), "tail should not contain /: " .. tail)
      end
    end)

    it("path.extension works on mock files", function()
      assert.are.equal("lua", path.extension("init.lua"))
      assert.are.equal("md", path.extension("README.md"))
      assert.is_nil(path.extension("Makefile"))
      assert.is_nil(path.extension("LICENSE"))
    end)

    it("path.parent extracts directory", function()
      assert.are.equal("lua/fzf-lua/", path.parent("lua/fzf-lua/init.lua"))
      assert.are.equal("tests/", path.parent("tests/path_spec.lua"))
    end)

    it("utils.strsplit parses grep output", function()
      local line = "lua/fzf-lua/core.lua:135:M.fzf_exec = function(contents, opts)"
      local parts = utils.strsplit(line, ":")
      assert.are.equal("lua/fzf-lua/core.lua", parts[1])
      assert.are.equal("135", parts[2])
    end)

    it("fzf-lua.setup loads without error", function()
      assert.has_no.errors(function()
        fzf_lua.setup({})
      end)
    end)

    it("fzf-lua get_info callable after setup", function()
      assert.is.truthy(type(fzf_lua.get_info) == "function")
    end)
  end)
end)
