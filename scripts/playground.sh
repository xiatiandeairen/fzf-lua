#!/usr/bin/env bash
# ============================================================================
#  fzf-lua Fuzzy Search Playground
#  ─────────────────────────────────
#  Interactive terminal demo platform for testing fzf fuzzy search capabilities.
#  No Neovim required — runs entirely in your shell with the fzf binary.
#
#  Usage:
#    bash scripts/playground.sh              # Launch main menu
#    bash scripts/playground.sh --hierarchical            # Run single mode directly
#    bash scripts/playground.sh --insight    # Print last session insight report
#    bash scripts/playground.sh --logs       # Tail debug/trace logs
#    bash scripts/playground.sh --clean      # Remove all log/session data
#
#  Requirements: fzf (required), bat (optional, for preview highlighting)
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Paths ──────────────────────────────────────────────────────────────────
LOG_DIR="${PROJECT_DIR}/.playground"
TRACE_LOG="${LOG_DIR}/trace.log"
DEBUG_LOG="${LOG_DIR}/debug.log"
INSIGHT_FILE="${LOG_DIR}/insight.md"
SESSION_FILE="${LOG_DIR}/session.json"

mkdir -p "$LOG_DIR"

# ── Colors ─────────────────────────────────────────────────────────────────
R='\033[0m' B='\033[1m' DIM='\033[2m'
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m'

# ── Session state ──────────────────────────────────────────────────────────
SESSION_START=$(date +%s)
declare -A SESSION_COUNTS
SESSION_COUNTS=([queries]=0 [selections]=0 [modes]=0 [errors]=0)
SESSION_QUERIES=()

# ── Logging ────────────────────────────────────────────────────────────────
_ts() { date '+%H:%M:%S.%3N'; }

trace() {
  echo "[$(_ts)] [TRACE] $*" >> "$TRACE_LOG"
}

debug() {
  echo "[$(_ts)] [DEBUG] $*" >> "$DEBUG_LOG"
}

info_log() {
  echo "[$(_ts)] [INFO]  $*" >> "$DEBUG_LOG"
  echo "[$(_ts)] [INFO]  $*" >> "$TRACE_LOG"
}

error_log() {
  echo "[$(_ts)] [ERROR] $*" >> "$DEBUG_LOG"
  echo "[$(_ts)] [ERROR] $*" >> "$TRACE_LOG"
  SESSION_COUNTS[errors]=$(( ${SESSION_COUNTS[errors]} + 1 ))
}

record_query() {
  SESSION_COUNTS[queries]=$(( ${SESSION_COUNTS[queries]} + 1 ))
  SESSION_QUERIES+=("$1")
  trace "query recorded: '$1'"
}

record_selection() {
  SESSION_COUNTS[selections]=$(( ${SESSION_COUNTS[selections]} + 1 ))
  trace "selection: $1"
}

# ── Pre-flight check ──────────────────────────────────────────────────────
preflight() {
  if ! command -v fzf &>/dev/null; then
    echo -e "${RED}Error: fzf is not installed.${R}" >&2
    exit 1
  fi
  info_log "session start — fzf $(fzf --version 2>/dev/null | head -1), pwd=$PROJECT_DIR"
  trace "preflight ok"
}

# ── fzf theme ──────────────────────────────────────────────────────────────
FZF_THEME="--color=fg:#c0caf5,bg:#1a1b26,hl:#bb9af7 \
--color=fg+:#c0caf5,bg+:#292e42,hl+:#7dcfff \
--color=info:#7aa2f7,prompt:#7dcfff,pointer:#ff007c \
--color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a \
--color=border:#565f89,separator:#565f89,scrollbar:#565f89"

FZF_COMMON="--height=90% --layout=reverse --border=rounded \
--margin=1,2 --padding=1 --scrollbar=▌ \
--cycle $FZF_THEME"

# ── Mock data generators ──────────────────────────────────────────────────
generate_file_tree() {
  trace "generating file tree dataset"
  find "$PROJECT_DIR" -type f \
    -not -path '*/.git/*' \
    -not -path '*/.playground/*' \
    -not -path '*/node_modules/*' | \
    sed "s|^${PROJECT_DIR}/||" | sort
}

generate_mock_grep() {
  trace "generating mock grep dataset"
  cat <<'GREP_DATA'
lua/fzf-lua/core.lua:135:1: M.fzf_exec = function(contents, opts)
lua/fzf-lua/core.lua:198:1: M.fzf_live = function(contents, opts)
lua/fzf-lua/core.lua:223:1: M.fzf_wrap = function(opts, contents)
lua/fzf-lua/core.lua:300:1: M.setup_fzf_interactive_native = function(cmd, opts)
lua/fzf-lua/core.lua:450:1: M.mt_cmd_wrapper = function(opts)
lua/fzf-lua/init.lua:1:1:   local M = {}
lua/fzf-lua/init.lua:100:1: M.setup = function(opts)
lua/fzf-lua/init.lua:377:1: M.fzf_exec = require("fzf-lua.core").fzf_exec
lua/fzf-lua/init.lua:378:1: M.fzf_live = require("fzf-lua.core").fzf_live
lua/fzf-lua/path.lua:10:1:  local M = {}
lua/fzf-lua/path.lua:50:1:  function M.tail(s)
lua/fzf-lua/path.lua:88:1:  function M.extension(s)
lua/fzf-lua/path.lua:120:1: function M.parent(s)
lua/fzf-lua/path.lua:180:1: function M.normalize(s)
lua/fzf-lua/path.lua:250:1: function M.shorten(s, opts)
lua/fzf-lua/utils.lua:11:1:  local M = {}
lua/fzf-lua/utils.lua:60:1:  M.nbsp = "\xc2\xa0"
lua/fzf-lua/utils.lua:120:1: M.strsplit = function(inputstr, sep)
lua/fzf-lua/utils.lua:200:1: M.tbl_count = function(t)
lua/fzf-lua/utils.lua:350:1: M.ansi_codes = setmetatable({}, { ... })
lua/fzf-lua/config.lua:1:1:   local path = require("fzf-lua.path")
lua/fzf-lua/config.lua:50:1:  function M.normalize_opts(opts, defaults)
lua/fzf-lua/fzf.lua:41:1:   function M.raw_fzf(contents, fzf_cli_args, opts)
lua/fzf-lua/win.lua:1:1:     local utils = require("fzf-lua.utils")
lua/fzf-lua/shell.lua:1:1:   local M = {}
lua/fzf-lua/libuv.lua:1:1:   local M = {}
lua/fzf-lua/make_entry.lua:1:1: local M = {}
GREP_DATA
}

generate_symbols() {
  trace "generating symbols dataset"
  cat <<'SYM_DATA'
[function]  fzf_exec                  lua/fzf-lua/core.lua:135
[function]  fzf_live                  lua/fzf-lua/core.lua:198
[function]  fzf_wrap                  lua/fzf-lua/core.lua:223
[function]  setup_fzf_interactive     lua/fzf-lua/core.lua:300
[function]  mt_cmd_wrapper            lua/fzf-lua/core.lua:450
[function]  raw_fzf                   lua/fzf-lua/fzf.lua:41
[function]  setup                     lua/fzf-lua/init.lua:100
[function]  tail                      lua/fzf-lua/path.lua:50
[function]  extension                 lua/fzf-lua/path.lua:88
[function]  parent                    lua/fzf-lua/path.lua:120
[function]  normalize                 lua/fzf-lua/path.lua:180
[function]  shorten                   lua/fzf-lua/path.lua:250
[function]  strsplit                  lua/fzf-lua/utils.lua:120
[function]  tbl_count                 lua/fzf-lua/utils.lua:200
[function]  normalize_opts            lua/fzf-lua/config.lua:50
[table]     M                         lua/fzf-lua/init.lua:1
[table]     ansi_codes                lua/fzf-lua/utils.lua:350
[string]    nbsp                      lua/fzf-lua/utils.lua:60
[boolean]   __HAS_NVIM_010            lua/fzf-lua/utils.lua:17
[number]    tbl_length                lua/fzf-lua/utils.lua:210
SYM_DATA
}

generate_large_dataset() {
  local n="${1:-10000}"
  trace "generating large dataset: ${n} entries"
  local langs=("lua" "py" "rs" "go" "ts" "js" "c" "cpp" "java" "rb")
  local modules=("core" "utils" "config" "api" "auth" "db" "cache" "queue" "worker" "ui")
  local components=("init" "main" "helper" "handler" "service" "model" "view" "test" "spec" "bench")
  for i in $(seq 1 "$n"); do
    local l=${langs[$(( i % ${#langs[@]} ))]}
    local m=${modules[$(( (i / 10) % ${#modules[@]} ))]}
    local c=${components[$(( (i / 100) % ${#components[@]} ))]}
    echo "src/${m}/${c}_$(printf '%04d' $i).${l}"
  done
}

# ── Preview helpers ────────────────────────────────────────────────────────
preview_file() {
  local file="${PROJECT_DIR}/$1"
  if [[ -f "$file" ]]; then
    if command -v bat &>/dev/null; then
      bat --color=always --style=numbers,header --line-range=:80 "$file" 2>/dev/null
    else
      head -80 "$file" 2>/dev/null
    fi
  else
    echo "(preview not available for: $1)"
  fi
}
export -f preview_file
export PROJECT_DIR

# ── Playground Modes ──────────────────────────────────────────────────────

mode_file_search() {
  info_log "mode: file_search"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local data
  data=$(generate_file_tree)
  local total
  total=$(echo "$data" | wc -l | tr -d ' ')
  trace "file_search: ${total} files loaded"

  local result
  result=$(echo "$data" | fzf \
    $FZF_COMMON \
    --prompt="📁 Files❯ " \
    --header="$(printf '  🔍 Fuzzy file search  │  %s files  │  Enter=select  Esc=back' "$total")" \
    --header-first \
    --border-label=" 📂 File Search " \
    --preview="bash -c 'preview_file {}'" \
    --preview-window="right:55%:border-left:wrap" \
    --bind="ctrl-p:toggle-preview" \
    --print-query 2>/dev/null)

  local query selected
  query=$(echo "$result" | head -1)
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "file:$query"
  [[ -n "$selected" ]] && record_selection "file:$selected"
  debug "file_search result: query='$query' selected='$selected'"
}

mode_grep_search() {
  info_log "mode: grep_search"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local data
  data=$(generate_mock_grep)

  local result
  result=$(echo "$data" | fzf \
    $FZF_COMMON \
    --prompt="🔎 Grep❯ " \
    --header="$(printf '  Search code by content  │  --nth=4.. only matches code  │  --delimiter=:')" \
    --header-first \
    --border-label=" 🔎 Grep Search " \
    --delimiter=":" \
    --nth="4.." \
    --ansi \
    --preview="echo -e '  \033[1;36mFile:\033[0m {1}\n  \033[1;33mLine:\033[0m {2}\n  \033[1;32mCode:\033[0m {4..}'" \
    --preview-window="bottom:4:border-top:nowrap" \
    --bind="ctrl-p:toggle-preview" \
    --print-query 2>/dev/null)

  local query selected
  query=$(echo "$result" | head -1)
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "grep:$query"
  [[ -n "$selected" ]] && record_selection "grep:$selected"
  debug "grep_search result: query='$query' selected='$selected'"
}

mode_live_reload() {
  info_log "mode: live_reload"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local datafile
  datafile=$(mktemp)
  generate_mock_grep > "$datafile"

  local result
  result=$(fzf \
    $FZF_COMMON \
    --prompt="⚡ Live❯ " \
    --header="  Live reload — results refresh on every keystroke (change:reload)" \
    --header-first \
    --border-label=" ⚡ Live Reload Search " \
    --disabled \
    --ansi \
    --delimiter=":" \
    --preview="echo -e '  \033[1;36mFile:\033[0m {1}\n  \033[1;33mLine:\033[0m {2}\n  \033[1;32mCode:\033[0m {4..}'" \
    --preview-window="bottom:4:border-top:nowrap" \
    --bind="start:reload:cat $datafile" \
    --bind="change:reload:grep -i {q} $datafile || true" \
    --bind="ctrl-p:toggle-preview" \
    --print-query 2>/dev/null)

  local query selected
  query=$(echo "$result" | head -1)
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "live:$query"
  [[ -n "$selected" ]] && record_selection "live:$selected"
  debug "live_reload result: query='$query' selected='$selected'"
  rm -f "$datafile"
}

mode_multi_select() {
  info_log "mode: multi_select"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local data
  data=$(generate_symbols)

  local result
  result=$(echo "$data" | fzf \
    $FZF_COMMON \
    --prompt="🏷️  Symbols❯ " \
    --header="  Tab=toggle  Ctrl-A=all  Ctrl-D=deselect  Enter=confirm" \
    --header-first \
    --border-label=" 🏷️  Multi-Select Symbols " \
    --multi \
    --marker="✓ " \
    --bind="ctrl-a:select-all" \
    --bind="ctrl-d:deselect-all" \
    --bind="ctrl-p:toggle-preview" \
    --preview="echo -e '  \033[1mSymbol detail:\033[0m\n  {1} \033[36m{2}\033[0m\n  📍 {3}'" \
    --preview-window="bottom:4:border-top:nowrap" \
    --print-query 2>/dev/null)

  local query
  query=$(echo "$result" | head -1)
  local selected
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "symbol:$query"
  local count=0
  while IFS= read -r line; do
    [[ -n "$line" ]] && { record_selection "symbol:$line"; ((count++)); }
  done <<< "$selected"
  debug "multi_select result: query='$query' selected_count=${count}"
}

mode_scoring_compare() {
  info_log "mode: scoring_compare"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local data
  data=$(generate_file_tree)

  local prompt_text="Compare scoring: Ctrl-S toggle scheme  Ctrl-T toggle tiebreak"
  local scheme="default"
  local tiebreak="length"

  local result
  result=$(echo "$data" | fzf \
    $FZF_COMMON \
    --prompt="📊 Scoring❯ " \
    --header="  $prompt_text  │  scheme=${scheme}  tiebreak=${tiebreak}" \
    --header-first \
    --border-label=" 📊 Scoring & Ranking " \
    --scheme="$scheme" \
    --tiebreak="$tiebreak" \
    --preview="bash -c 'preview_file {}'" \
    --preview-window="right:50%:border-left:wrap" \
    --bind="ctrl-p:toggle-preview" \
    --print-query 2>/dev/null)

  local query selected
  query=$(echo "$result" | head -1)
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "scoring:$query"
  [[ -n "$selected" ]] && record_selection "scoring:$selected"
  debug "scoring_compare result: query='$query' selected='$selected' scheme=$scheme tiebreak=$tiebreak"
}

mode_hierarchical() {
  info_log "mode: hierarchical"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))
  local data
  data=$(generate_file_tree)

  # Extract directories
  local dirs
  dirs=$(echo "$data" | sed 's|/[^/]*$||' | sort -u)

  local dir_choice
  dir_choice=$(echo "$dirs" | fzf \
    $FZF_COMMON \
    --prompt="📁 Directory❯ " \
    --header="  Step 1/2: Pick a directory, then search files inside" \
    --header-first \
    --border-label=" 📁 Hierarchical Search " \
    --preview="echo '$data' | grep '^{}/' | head -30" \
    --preview-window="right:50%:border-left:wrap" \
    2>/dev/null)

  if [[ -z "$dir_choice" ]]; then
    trace "hierarchical: no dir selected, returning"
    return
  fi
  trace "hierarchical: dir=$dir_choice"

  local files_in_dir
  files_in_dir=$(echo "$data" | grep "^${dir_choice}/")

  local result
  result=$(echo "$files_in_dir" | fzf \
    $FZF_COMMON \
    --prompt="📄 ${dir_choice}/❯ " \
    --header="  Step 2/2: Search files in ${dir_choice}/" \
    --header-first \
    --border-label=" 📄 Files in ${dir_choice}/ " \
    --preview="bash -c 'preview_file {}'" \
    --preview-window="right:55%:border-left:wrap" \
    --print-query 2>/dev/null)

  local query selected
  query=$(echo "$result" | head -1)
  selected=$(echo "$result" | tail -n +2)
  [[ -n "$query" ]] && record_query "hier:${dir_choice}/${query}"
  [[ -n "$selected" ]] && record_selection "hier:$selected"
  debug "hierarchical result: dir='$dir_choice' query='$query' selected='$selected'"
}

mode_perf_bench() {
  info_log "mode: perf_bench"
  SESSION_COUNTS[modes]=$(( ${SESSION_COUNTS[modes]} + 1 ))

  local sizes=(1000 5000 10000 50000)
  local size_labels=("1K" "5K" "10K" "50K")
  local results=()

  echo -e "\n${B}  ⏱  Performance Benchmark${R}\n"
  echo -e "  ${DIM}Dataset      Query               Matches    Time${R}"
  echo -e "  ${DIM}───────────  ──────────────────  ─────────  ──────${R}"

  for i in "${!sizes[@]}"; do
    local n=${sizes[$i]}
    local label=${size_labels[$i]}
    local tmpfile
    tmpfile=$(mktemp)
    generate_large_dataset "$n" > "$tmpfile"

    # fuzzy match
    local start_ns end_ns elapsed count
    start_ns=$(date +%s%N)
    count=$(fzf --filter="core init_0050" < "$tmpfile" | wc -l | tr -d ' ')
    end_ns=$(date +%s%N)
    elapsed=$(( (end_ns - start_ns) / 1000000 ))
    printf "  %-11s  %-18s  %9s  %4dms\n" "${label} lines" "core init_0050" "${count} hits" "$elapsed"
    trace "perf: n=$n query='core init_0050' matches=$count time=${elapsed}ms"

    # exact match
    start_ns=$(date +%s%N)
    count=$(fzf --filter="'worker/handler" < "$tmpfile" | wc -l | tr -d ' ')
    end_ns=$(date +%s%N)
    elapsed=$(( (end_ns - start_ns) / 1000000 ))
    printf "  %-11s  %-18s  %9s  %4dms\n" "${label} lines" "'worker/handler" "${count} hits" "$elapsed"
    trace "perf: n=$n query=\"'worker/handler\" matches=$count time=${elapsed}ms"

    rm -f "$tmpfile"
  done

  echo ""
  if [[ -t 0 ]]; then
    read -rp "  Press Enter to return to menu..." _
  fi
}

# ── Insight Report ─────────────────────────────────────────────────────────
generate_insight() {
  local duration=$(( $(date +%s) - SESSION_START ))
  local mins=$(( duration / 60 ))
  local secs=$(( duration % 60 ))

  cat > "$INSIGHT_FILE" <<INSIGHT
# fzf-lua Playground — Session Insight Report
> Generated: $(date '+%Y-%m-%d %H:%M:%S')

## Session Summary
| Metric           | Value                             |
|------------------|-----------------------------------|
| Duration         | ${mins}m ${secs}s                 |
| Modes Used       | ${SESSION_COUNTS[modes]}          |
| Total Queries    | ${SESSION_COUNTS[queries]}        |
| Total Selections | ${SESSION_COUNTS[selections]}     |
| Errors           | ${SESSION_COUNTS[errors]}         |

## Query History
$(if [[ ${#SESSION_QUERIES[@]} -gt 0 ]]; then
  echo "| # | Query |"
  echo "|---|-------|"
  local idx=1
  for q in "${SESSION_QUERIES[@]}"; do
    echo "| $idx | \`$q\` |"
    ((idx++))
  done
else
  echo "_No queries recorded._"
fi)

## Log Files
- **Debug log**: \`${DEBUG_LOG}\`
- **Trace log**: \`${TRACE_LOG}\`

## Quick Analysis
$(if [[ ${SESSION_COUNTS[queries]} -eq 0 ]]; then
  echo "- ⚠️  No queries executed. Try running some search modes!"
elif [[ ${SESSION_COUNTS[queries]} -lt 3 ]]; then
  echo "- 💡 Light usage. Try more modes for a broader test."
else
  echo "- ✅ Active session with ${SESSION_COUNTS[queries]} queries across ${SESSION_COUNTS[modes]} modes."
fi)
$(if [[ ${SESSION_COUNTS[errors]} -gt 0 ]]; then
  echo "- ❌ ${SESSION_COUNTS[errors]} error(s) detected. Check debug.log for details."
else
  echo "- ✅ No errors."
fi)
INSIGHT

  info_log "insight report written to $INSIGHT_FILE"
}

show_insight() {
  if [[ ! -f "$INSIGHT_FILE" ]]; then
    echo -e "${YELLOW}No insight report found. Run the playground first.${R}"
    return
  fi
  echo ""
  if command -v bat &>/dev/null; then
    bat --style=plain --language=markdown "$INSIGHT_FILE"
  else
    cat "$INSIGHT_FILE"
  fi
  echo ""
}

# ── Log Viewer ─────────────────────────────────────────────────────────────
show_logs() {
  local log_choice
  log_choice=$(printf "debug.log  (high-level events, errors)\ntrace.log  (detailed trace, every action)" | fzf \
    $FZF_COMMON \
    --prompt="📋 Log❯ " \
    --header="  Select a log file to view" \
    --header-first \
    --border-label=" 📋 Log Viewer " \
    --preview-window="hidden" \
    2>/dev/null)

  case "$log_choice" in
    debug*) [[ -f "$DEBUG_LOG" ]] && less -R "$DEBUG_LOG" || echo "No debug.log yet." ;;
    trace*) [[ -f "$TRACE_LOG" ]] && less -R "$TRACE_LOG" || echo "No trace.log yet." ;;
  esac
}

# ── Main Menu ──────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    local choice
    choice=$(printf '%s\n' \
      "📁  File Search          Fuzzy find in real project files with preview" \
      "🔎  Grep Search          Search mock code output (--nth column filtering)" \
      "⚡  Live Reload          Dynamic reload on each keystroke (change:reload)" \
      "🏷️   Multi-Select         Symbol picker with Tab multi-select" \
      "📊  Scoring & Ranking    Explore fzf scoring schemes and tiebreak" \
      "📁  Hierarchical Search  Two-step: pick directory → search files" \
      "⏱️   Performance Bench    Benchmark fzf --filter on 1K–50K datasets" \
      "───────────────────────────────────────────────────────────────" \
      "📋  View Logs            Browse debug and trace logs" \
      "📈  Insight Report       Session analysis and statistics" \
      "🚪  Exit" \
      | fzf \
        $FZF_COMMON \
        --prompt="▶ Menu❯ " \
        --header="$(printf '  fzf-lua Fuzzy Search Playground  │  fzf %s' "$(fzf --version 2>/dev/null | head -1)")" \
        --header-first \
        --border-label=" 🎮 Playground Main Menu " \
        --no-multi \
        --preview-window="hidden" \
        --info=hidden \
        --pointer="▶" \
        2>/dev/null)

    trace "menu selection: '$choice'"

    case "$choice" in
      *"File Search"*)         mode_file_search ;;
      *"Grep Search"*)         mode_grep_search ;;
      *"Live Reload"*)         mode_live_reload ;;
      *"Multi-Select"*)        mode_multi_select ;;
      *"Scoring"*)             mode_scoring_compare ;;
      *"Hierarchical"*)        mode_hierarchical ;;
      *"Performance"*)         mode_perf_bench ;;
      *"View Logs"*)           show_logs ;;
      *"Insight"*)             generate_insight; show_insight ;;
      *"Exit"*|"")
        info_log "session end"
        generate_insight
        echo -e "\n${GREEN}Session insight saved to: ${CYAN}${INSIGHT_FILE}${R}"
        echo -e "${DIM}Logs: ${TRACE_LOG}${R}"
        echo -e "${DIM}      ${DEBUG_LOG}${R}\n"
        return 0
        ;;
    esac
  done
}

# ── CLI Entry Point ────────────────────────────────────────────────────────
main() {
  preflight

  case "${1:-}" in
    --insight)
      show_insight
      ;;
    --logs)
      show_logs
      ;;
    --clean)
      rm -rf "$LOG_DIR"
      echo -e "${GREEN}Cleaned: ${LOG_DIR}${R}"
      ;;
    --file-search)         mode_file_search ;;
    --grep-search)         mode_grep_search ;;
    --live-reload)         mode_live_reload ;;
    --multi-select)        mode_multi_select ;;
    --scoring)             mode_scoring_compare ;;
    --hierarchical)        mode_hierarchical ;;
    --perf)                mode_perf_bench ;;
    ""|--menu)
      main_menu
      ;;
    --help|-h)
      cat <<HELP
fzf-lua Fuzzy Search Playground

Usage:
  bash scripts/playground.sh              Launch interactive menu
  bash scripts/playground.sh --file-search   Run file search directly
  bash scripts/playground.sh --grep-search   Run grep search directly
  bash scripts/playground.sh --live-reload   Run live reload directly
  bash scripts/playground.sh --multi-select  Run multi-select directly
  bash scripts/playground.sh --scoring       Run scoring comparison
  bash scripts/playground.sh --hierarchical  Run hierarchical search
  bash scripts/playground.sh --perf          Run performance benchmark
  bash scripts/playground.sh --insight       View last session report
  bash scripts/playground.sh --logs          View debug/trace logs
  bash scripts/playground.sh --clean         Remove all session data

Modes:
  File Search       Fuzzy find real project files + bat/cat preview
  Grep Search       Search mock code lines, --nth filters by code column
  Live Reload       change:reload dynamic search (like live_grep)
  Multi-Select      Tab multi-select symbols with bulk confirm
  Scoring           Compare fzf scoring schemes (default/path)
  Hierarchical      Two-step: directory → files drill-down
  Performance       Benchmark fzf --filter on 1K–50K datasets

Logs & Insight:
  All actions are logged to .playground/debug.log and .playground/trace.log.
  Session insight report is auto-generated on exit at .playground/insight.md.
HELP
      ;;
    *)
      echo -e "${RED}Unknown option: $1${R}" >&2
      echo "Run: bash scripts/playground.sh --help"
      exit 1
      ;;
  esac
}

main "$@"
