#!/usr/bin/env bash
# ============================================================================
# fzf-lua 模糊搜索能力测试 — 纯命令行运行，不进入 Neovim
#
# 用法:
#   bash scripts/test_fuzzy.sh          # 运行全部测试
#   bash scripts/test_fuzzy.sh --fzf    # 只跑 fzf 匹配测试（不需要 nvim）
#   bash scripts/test_fuzzy.sh --lua    # 只跑 fzf-lua Lua 管道测试（需要 nvim）
#   bash scripts/test_fuzzy.sh --perf   # 只跑性能基准测试
#
# 依赖: fzf (必须), nvim (--lua 测试需要)
# ============================================================================
set -uo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- 工具函数 ----------
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    期望: ${CYAN}${expected}${RESET}"
    echo -e "    实际: ${RED}${actual}${RESET}"
    ((FAIL++))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    输出中未找到: ${CYAN}${needle}${RESET}"
    ((FAIL++))
  fi
}

assert_not_empty() {
  local desc="$1" value="$2"
  if [[ -n "$value" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc (结果为空)"
    ((FAIL++))
  fi
}

assert_empty() {
  local desc="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    期望为空，实际: ${RED}${value}${RESET}"
    ((FAIL++))
  fi
}

assert_line_count() {
  local desc="$1" expected="$2" actual_output="$3"
  local count
  if [[ -z "$actual_output" ]]; then
    count=0
  else
    count=$(echo "$actual_output" | wc -l | tr -d ' ')
  fi
  if [[ "$count" -eq "$expected" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc (${count} 行)"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    期望 ${CYAN}${expected}${RESET} 行, 实际 ${RED}${count}${RESET} 行"
    ((FAIL++))
  fi
}

assert_first_line() {
  local desc="$1" expected="$2" actual_output="$3"
  local first
  first=$(echo "$actual_output" | head -1)
  if [[ "$first" == "$expected" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    期望首行: ${CYAN}${expected}${RESET}"
    echo -e "    实际首行: ${RED}${first}${RESET}"
    ((FAIL++))
  fi
}

assert_ge() {
  local desc="$1" actual="$2" threshold="$3"
  if [[ "$actual" -ge "$threshold" ]]; then
    echo -e "  ${GREEN}✓${RESET} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${RESET} $desc"
    echo -e "    期望 >= ${CYAN}${threshold}${RESET}, 实际 ${RED}${actual}${RESET}"
    ((FAIL++))
  fi
}

# ---------- 模拟数据 ----------
MOCK_FILES="lua/fzf-lua/init.lua
lua/fzf-lua/core.lua
lua/fzf-lua/fzf.lua
lua/fzf-lua/path.lua
lua/fzf-lua/utils.lua
lua/fzf-lua/config.lua
lua/fzf-lua/win.lua
lua/fzf-lua/shell.lua
lua/fzf-lua/libuv.lua
lua/fzf-lua/devicons.lua
lua/fzf-lua/class.lua
lua/fzf-lua/make_entry.lua
lua/fzf-lua/providers/files.lua
lua/fzf-lua/providers/grep.lua
lua/fzf-lua/providers/git.lua
lua/fzf-lua/providers/lsp.lua
lua/fzf-lua/providers/buffers.lua
lua/fzf-lua/providers/tags.lua
lua/fzf-lua/providers/diagnostics.lua
lua/fzf-lua/providers/quickfix.lua
lua/fzf-lua/providers/colorschemes.lua
lua/fzf-lua/providers/manpages.lua
lua/fzf-lua/previewer/builtin.lua
lua/fzf-lua/previewer/fzf.lua
lua/fzf-lua/previewer/codeaction.lua
tests/path_spec.lua
tests/init_spec.lua
tests/utils_spec.lua
tests/libuv_spec.lua
tests/fuzzy_spec.lua
scripts/init.lua
scripts/mini.sh
scripts/test_fuzzy.sh
README.md
Makefile
LICENSE"

MOCK_GREP="lua/fzf-lua/core.lua:135:M.fzf_exec = function(contents, opts)
lua/fzf-lua/core.lua:198:M.fzf_live = function(contents, opts)
lua/fzf-lua/core.lua:223:M.fzf_wrap = function(opts, contents)
lua/fzf-lua/init.lua:1:local M = {}
lua/fzf-lua/init.lua:377:M.fzf_exec = require('fzf-lua.core').fzf_exec
lua/fzf-lua/path.lua:10:local M = {}
lua/fzf-lua/path.lua:50:function M.tail(s)
lua/fzf-lua/path.lua:88:function M.extension(s)
lua/fzf-lua/utils.lua:120:M.strsplit = function(inputstr, sep)
lua/fzf-lua/utils.lua:200:M.tbl_count = function(t)"

# ============================================================================
# 第一部分: fzf 模糊匹配测试 (纯 shell，不需要 nvim)
# ============================================================================
run_fzf_tests() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD} 第一部分: fzf --filter 模糊匹配测试 (纯 shell)${RESET}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"

  # --- 1. 精确匹配 ---
  echo ""
  echo -e "${YELLOW}[1] 精确匹配${RESET}"
  local result
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="Makefile")
  assert_first_line "首条结果是 Makefile" "Makefile" "$result"

  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="LICENSE")
  assert_first_line "首条结果是 LICENSE" "LICENSE" "$result"

  # --- 2. 模糊部分匹配 ---
  echo ""
  echo -e "${YELLOW}[2] 模糊部分匹配${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="init")
  assert_contains "匹配 lua/fzf-lua/init.lua" "$result" "lua/fzf-lua/init.lua"
  assert_contains "匹配 tests/init_spec.lua" "$result" "tests/init_spec.lua"
  assert_contains "匹配 scripts/init.lua" "$result" "scripts/init.lua"

  # --- 3. 空查询返回全部 ---
  echo ""
  echo -e "${YELLOW}[3] 空查询返回全部${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="")
  local total
  total=$(echo "$MOCK_FILES" | wc -l | tr -d ' ')
  assert_line_count "空查询返回全部 ${total} 行" "$total" "$result"

  # --- 4. 无匹配返回空 ---
  echo ""
  echo -e "${YELLOW}[4] 无匹配返回空${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="zzzzxxxxxnonexistent" || true)
  assert_empty "不存在的查询返回空" "$result"

  # --- 5. 大小写不敏感 ---
  echo ""
  echo -e "${YELLOW}[5] 大小写不敏感匹配 (fzf 默认 smart-case)${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="readme")
  assert_contains "小写 readme 匹配 README.md" "$result" "README.md"

  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="makefile")
  assert_contains "小写 makefile 匹配 Makefile" "$result" "Makefile"

  # --- 6. 多词模糊匹配 ---
  echo ""
  echo -e "${YELLOW}[6] 多词模糊匹配${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="prov grep")
  assert_first_line "prov grep → providers/grep.lua" \
    "lua/fzf-lua/providers/grep.lua" "$result"

  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="prev built")
  assert_first_line "prev built → previewer/builtin.lua" \
    "lua/fzf-lua/previewer/builtin.lua" "$result"

  # --- 7. 路径分隔符匹配 ---
  echo ""
  echo -e "${YELLOW}[7] 路径分隔符匹配${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="previewer/fzf")
  assert_first_line "previewer/fzf → previewer/fzf.lua" \
    "lua/fzf-lua/previewer/fzf.lua" "$result"

  # --- 8. grep 格式输出匹配 ---
  echo ""
  echo -e "${YELLOW}[8] grep 格式输出匹配${RESET}"
  result=$(printf '%s' "$MOCK_GREP" | fzf --filter="fzf_exec")
  assert_contains "匹配 core.lua 中的 fzf_exec" "$result" "core.lua:135:M.fzf_exec"
  assert_contains "匹配 init.lua 中的 fzf_exec" "$result" "init.lua:377:M.fzf_exec"

  result=$(printf '%s' "$MOCK_GREP" | fzf --filter="tail")
  assert_contains "匹配 path.lua 中的 tail" "$result" "path.lua:50:function M.tail"

  # --- 9. --nth 限定列匹配 ---
  echo ""
  echo -e "${YELLOW}[9] --nth 限定列匹配 (只匹配代码内容，不匹配文件名)${RESET}"
  result=$(printf '%s' "$MOCK_GREP" | fzf --filter="strsplit" --delimiter=":" --nth="3..")
  assert_contains "--nth 过滤: 匹配 strsplit" "$result" "M.strsplit"

  result=$(printf '%s' "$MOCK_GREP" | fzf --filter="function" --delimiter=":" --nth="3..")
  local count
  count=$(echo "$result" | wc -l | tr -d ' ')
  assert_ge "--nth 过滤: function 至少匹配 3 行" "$count" 3

  # --- 10. 精确模式 (单引号前缀) ---
  echo ""
  echo -e "${YELLOW}[10] 精确模式 ('query 前缀强制精确子串匹配)${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="'providers/grep.lua")
  assert_first_line "精确匹配 providers/grep.lua" \
    "lua/fzf-lua/providers/grep.lua" "$result"

  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="'zzznomatch" || true)
  assert_empty "精确匹配不存在的子串返回空" "$result"

  # --- 11. 排除模式 (!query) ---
  echo ""
  echo -e "${YELLOW}[11] 排除模式 (!query 排除包含关键词的行)${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter="lua !providers !previewer !tests !scripts")
  assert_contains "排除后仍包含 init.lua" "$result" "lua/fzf-lua/init.lua"
  # providers/ 目录的文件不应出现
  if echo "$result" | grep -qF "providers/"; then
    echo -e "  ${RED}✗${RESET} 排除 providers 失败"
    ((FAIL++))
  else
    echo -e "  ${GREEN}✓${RESET} providers 目录的文件已排除"
    ((PASS++))
  fi

  # --- 12. 后缀匹配 ($query) ---
  echo ""
  echo -e "${YELLOW}[12] 后缀匹配 (query\$ 匹配行尾)${RESET}"
  result=$(printf '%s' "$MOCK_FILES" | fzf --filter=".sh$")
  assert_contains "后缀 .sh 匹配 mini.sh" "$result" "scripts/mini.sh"
  assert_contains "后缀 .sh 匹配 test_fuzzy.sh" "$result" "scripts/test_fuzzy.sh"
}

# ============================================================================
# 第二部分: fzf-lua Lua 管道测试 (通过 nvim --headless)
# ============================================================================
run_lua_tests() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD} 第二部分: fzf-lua Lua 管道测试 (nvim --headless)${RESET}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"

  if ! command -v nvim &>/dev/null; then
    echo -e "  ${RED}✗${RESET} nvim 未安装，跳过 Lua 测试"
    ((FAIL++))
    return
  fi

  local nvim_lua
  nvim_lua() {
    nvim --headless --noplugin --cmd "set rtp+=${PROJECT_DIR}" \
      -c "lua $1" -c "qa!" 2>&1
  }

  echo ""
  echo -e "${YELLOW}[13] fzf-lua 模块加载${RESET}"
  local out
  out=$(nvim_lua "
    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then
      print('LOAD_OK')
    else
      print('LOAD_FAIL: ' .. tostring(fzf))
    end
  ")
  assert_contains "require('fzf-lua') 成功" "$out" "LOAD_OK"

  echo ""
  echo -e "${YELLOW}[14] fzf-lua.setup() 初始化${RESET}"
  out=$(nvim_lua "
    local fzf = require('fzf-lua')
    local ok, err = pcall(fzf.setup, {})
    print(ok and 'SETUP_OK' or ('SETUP_FAIL: ' .. tostring(err)))
  ")
  assert_contains "fzf-lua.setup({}) 无报错" "$out" "SETUP_OK"

  echo ""
  echo -e "${YELLOW}[15] path.tail 提取文件名${RESET}"
  out=$(nvim_lua "
    local path = require('fzf-lua').path
    print(path.tail('lua/fzf-lua/init.lua'))
    print(path.tail('tests/path_spec.lua'))
    print(path.tail('README.md'))
    print(path.tail('Makefile'))
  ")
  assert_contains "tail(lua/fzf-lua/init.lua) = init.lua" "$out" "init.lua"
  assert_contains "tail(tests/path_spec.lua) = path_spec.lua" "$out" "path_spec.lua"
  assert_contains "tail(README.md) = README.md" "$out" "README.md"
  assert_contains "tail(Makefile) = Makefile" "$out" "Makefile"

  echo ""
  echo -e "${YELLOW}[16] path.extension 提取扩展名${RESET}"
  out=$(nvim_lua "
    local path = require('fzf-lua').path
    print('ext_lua=' .. tostring(path.extension('init.lua')))
    print('ext_md=' .. tostring(path.extension('README.md')))
    local ext = path.extension('Makefile')
    print('ext_mk=' .. (ext == nil and 'NO_EXT' or ext))
  ")
  assert_contains "extension(init.lua) = lua" "$out" "ext_lua=lua"
  assert_contains "extension(README.md) = md" "$out" "ext_md=md"
  assert_contains "extension(Makefile) = 无扩展名" "$out" "ext_mk=NO_EXT"

  echo ""
  echo -e "${YELLOW}[17] path.parent 提取目录${RESET}"
  out=$(nvim_lua "
    local path = require('fzf-lua').path
    print('p1=' .. tostring(path.parent('lua/fzf-lua/init.lua')))
    print('p2=' .. tostring(path.parent('tests/path_spec.lua')))
  ")
  assert_contains "parent → lua/fzf-lua/" "$out" "p1=lua/fzf-lua/"
  assert_contains "parent → tests/" "$out" "p2=tests/"

  echo ""
  echo -e "${YELLOW}[18] utils.strsplit 字符串分割${RESET}"
  out=$(nvim_lua "
    local utils = require('fzf-lua').utils
    local parts = utils.strsplit('lua/fzf-lua/core.lua:135:M.fzf_exec', ':')
    print('s1=' .. parts[1])
    print('s2=' .. parts[2])
    print('s3=' .. parts[3])
  ")
  assert_contains "split[1] = lua/fzf-lua/core.lua" "$out" "s1=lua/fzf-lua/core.lua"
  assert_contains "split[2] = 135" "$out" "s2=135"
  assert_contains "split[3] = M.fzf_exec" "$out" "s3=M.fzf_exec"

  echo ""
  echo -e "${YELLOW}[19] fzf-lua API 函数完整性${RESET}"
  out=$(nvim_lua "
    local fzf = require('fzf-lua')
    fzf.setup({})
    local funcs = {'fzf_exec','fzf_live','fzf_wrap','files','grep','live_grep',
                   'buffers','git_files','lsp_references','builtin','setup'}
    for _, name in ipairs(funcs) do
      local t = type(fzf[name])
      print(name .. '=' .. t)
    end
  ")
  for fn in fzf_exec fzf_live fzf_wrap files grep live_grep buffers builtin setup; do
    assert_contains "fzf.${fn} 是 function" "$out" "${fn}=function"
  done
}

# ============================================================================
# 第三部分: 性能基准测试
# ============================================================================
run_perf_tests() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD} 第三部分: 性能基准测试${RESET}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"

  echo ""
  echo -e "${YELLOW}[20] 大数据集模糊匹配性能${RESET}"

  local tmpfile
  tmpfile=$(mktemp)
  # 生成 10000 行模拟文件路径
  for i in $(seq 1 10000); do
    echo "src/module_${i}/component_$((i % 100))/file_$((i % 50)).lua"
  done > "$tmpfile"
  local total
  total=$(wc -l < "$tmpfile" | tr -d ' ')
  echo -e "  数据集: ${CYAN}${total}${RESET} 行"

  # 测试 fzf --filter 性能
  local start_time end_time elapsed result_count
  start_time=$(date +%s%N)
  result_count=$(fzf --filter="module_50 component_25" < "$tmpfile" | wc -l | tr -d ' ')
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  echo -e "  查询: ${CYAN}module_50 component_25${RESET}"
  echo -e "  结果: ${CYAN}${result_count}${RESET} 条匹配, 耗时 ${CYAN}${elapsed}ms${RESET}"
  assert_not_empty "10000 行数据有匹配结果" "$result_count"

  # 测试空查询性能
  start_time=$(date +%s%N)
  result_count=$(fzf --filter="" < "$tmpfile" | wc -l | tr -d ' ')
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  echo -e "  空查询返回: ${CYAN}${result_count}${RESET} 条, 耗时 ${CYAN}${elapsed}ms${RESET}"
  assert_eq "空查询返回全部 ${total} 条" "$total" "$result_count"

  # 测试精确匹配性能
  start_time=$(date +%s%N)
  result_count=$(fzf --filter="'file_49.lua" < "$tmpfile" | wc -l | tr -d ' ')
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  echo -e "  精确匹配 'file_49.lua': ${CYAN}${result_count}${RESET} 条, 耗时 ${CYAN}${elapsed}ms${RESET}"
  assert_not_empty "精确匹配有结果" "$result_count"

  rm -f "$tmpfile"
}

# ============================================================================
# 主入口
# ============================================================================
main() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║    fzf-lua 模糊搜索能力测试 — 命令行直接运行           ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"

  # 前置检查
  if ! command -v fzf &>/dev/null; then
    echo -e "${RED}错误: fzf 未安装${RESET}" >&2
    exit 1
  fi
  echo -e "fzf 版本: ${CYAN}$(fzf --version)${RESET}"
  if command -v nvim &>/dev/null; then
    echo -e "nvim 版本: ${CYAN}$(nvim --version | head -1)${RESET}"
  fi

  local mode="${1:-all}"
  case "$mode" in
    --fzf)  run_fzf_tests ;;
    --lua)  run_lua_tests ;;
    --perf) run_perf_tests ;;
    *)
      run_fzf_tests
      run_lua_tests
      run_perf_tests
      ;;
  esac

  # 汇总
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
  local total=$((PASS + FAIL))
  if [[ $FAIL -eq 0 ]]; then
    echo -e "${BOLD} 结果: ${GREEN}全部通过${RESET} ${GREEN}${PASS}/${total}${RESET}"
  else
    echo -e "${BOLD} 结果: ${RED}${FAIL} 个失败${RESET}, ${GREEN}${PASS} 个通过${RESET}, 共 ${total} 个"
  fi
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"

  [[ $FAIL -eq 0 ]]
}

main "$@"
