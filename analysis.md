# fzf-lua 核心链路实现原理

> 本文逐函数追踪一次 `:FzfLua files` 调用的完整执行路径，结合源码解析每个环节的实现机制。

---

## 全局调用链路总览

```
用户输入 :FzfLua files
│
├─❶ plugin/fzf-lua.lua          命令注册与路由
├─❷ cmd.lua:run_command()        参数解析
├─❸ init.lua:M[k]()             惰性加载 Provider
├─❹ providers/files.lua:files() 数据源构造
├─❺ config.normalize_opts()     三级配置合并
├─❻ core.mt_cmd_wrapper()       命令包装（headless 分叉点）
├─❼ core.fzf_exec()             管道编排入口
├─❽ core.fzf_wrap()             协程创建
├─❾ core.fzf()                  窗口 + Previewer + fzf 启动
├─❿ fzf.raw_fzf()               FIFO 管道 ↔ fzf 二进制
├─⓫ actions.act()               结果分发与执行
│
└─ 用户看到文件被打开
```

---

## ❶ 命令注册 — `plugin/fzf-lua.lua`

```lua
-- plugin/fzf-lua.lua:11-13
vim.api.nvim_create_user_command("FzfLua", function(opts)
  require("fzf-lua.cmd").run_command(unpack(opts.fargs))
end, { nargs = "*", range = true, complete = ... })
```

**原理**: Neovim 启动时加载 `plugin/` 目录下的文件，注册 `:FzfLua` 用户命令。`nargs = "*"` 允许任意参数。`require("fzf-lua.cmd")` 在命令首次调用时才触发，实现零启动开销。

---

## ❷ 参数解析 — `cmd.lua:run_command()`

```lua
-- cmd.lua:9-36
function M.run_command(cmd, ...)
  local args = { ... }
  cmd = cmd or "builtin"       -- 无参数时打开 builtin 命令列表

  if not builtin[cmd] then     -- 校验命令合法性
    utils.info(string.format("invalid command '%s'", cmd))
    return
  end

  local opts = {}
  for _, arg in ipairs(args) do
    local key = arg:match("^[^=]+")
    local val = arg:match("=") and arg:match("=(.*)$")
    if val and #val > 0 then
      local ok, loaded = serpent.load(val)  -- 用 serpent 反序列化
      -- ...
      opts[key] = loaded or val             -- 解析失败则保留原始字符串
    end
  end

  builtin[cmd](opts)  -- 调用 init.lua 上的对应函数
end
```

**原理**: 将 `:FzfLua files cwd=~/code` 这样的命令行解析为 `{ cwd = "~/code" }`，使用 serpent (一个 Lua 序列化库) 支持复杂值（表、布尔值等）。最终调用 `builtin["files"](opts)`。

---

## ❸ 惰性加载 — `init.lua` 的 `__index` 机制

```lua
-- init.lua:226-342（核心片段）
local lazyloaded_modules = {
  files     = { "fzf-lua.providers.files", "files" },
  grep      = { "fzf-lua.providers.grep",  "grep" },
  git_files = { "fzf-lua.providers.git",   "files" },
  -- ... 共 96 个映射
}

for k, v in pairs(lazyloaded_modules) do
  M[k] = function(...)
    -- 首次调用: 替换自身为直接调用版本
    M[k] = function(...)
      M.set_info { cmd = k, mod = v[1], fnc = v[2] }
      return require(v[1])[v[2]](...)
    end
    return M[k](...)
  end
end
```

**原理**: 双层函数包装实现**一次性惰性加载**：

1. 第一次调用 `M.files()` → 执行外层函数 → 将 `M.files` **重写**为内层函数
2. 内层函数中 `require("fzf-lua.providers.files")` 触发模块加载
3. 此后所有调用直接走内层函数，跳过加载逻辑
4. `set_info` 记录当前 Provider 元信息（用于 quickfix 命名等）

这意味着 96 个 Provider 模块仅在**用户首次调用时**才会 `require`，Neovim 启动时 init.lua 只注册了 96 个轻量函数指针。

---

## ❹ Provider 数据源构造 — `providers/files.lua`

```lua
-- providers/files.lua:44-66
M.files = function(opts)
  -- ❺ 配置标准化（见下一节）
  opts = config.normalize_opts(opts, "files")
  if not opts then return end

  -- 忽略当前文件（可选）
  if opts.ignore_current_file then
    local curbuf = vim.api.nvim_buf_get_name(0)
    -- ... 添加到 file_ignore_patterns
  end

  -- 智能选择文件查找工具
  opts.cmd = get_files_cmd(opts)

  -- ❻ 包装为可处理的命令（添加图标、Git 状态等）
  local contents = core.mt_cmd_wrapper(opts)

  -- 设置 header 显示（提示快捷键和当前目录）
  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })

  -- ❼ 进入核心管道
  return core.fzf_exec(contents, opts)
end
```

**文件查找工具选择逻辑**:

```lua
-- providers/files.lua:21-42
local get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd > 0 then return opts.raw_cmd end
  if opts.cmd and #opts.cmd > 0 then return opts.cmd end
  -- 优先级: fdfind > fd > rg > find
  if vim.fn.executable("fdfind") == 1 then
    return string.format("fdfind %s", opts.fd_opts)
  elseif vim.fn.executable("fd") == 1 then
    return string.format("fd %s", opts.fd_opts)
  elseif vim.fn.executable("rg") == 1 then
    return string.format("rg %s", opts.rg_opts)
  else
    return string.format("find -L . %s", opts.find_opts)
  end
end
```

**原理**: Provider 是纯粹的**数据源工厂**，职责是构造一个命令字符串（如 `fd --type f --hidden`），然后交给 core 层处理。所有 Provider 遵循相同的模式: `normalize_opts → 构造数据 → fzf_exec`。

---

## ❺ 三级配置合并 — `config.normalize_opts()`

这是整个系统中最复杂的函数之一（约 200 行），负责将用户选项、全局默认值、Provider 默认值合并为一个完整的 opts 表。

```lua
-- config.lua:75-128 — globals 代理表
M.globals = setmetatable({}, {
  __index = function(_, index)
    -- 优先级:
    --   (1) provider 特定配置 (setup 后)
    --   (2) 通用 defaults (setup 后)
    --   (3) fzf-lua 内置默认值 (setup 前, 静态)
    local fzflua_default = utils.map_get(M.defaults, index)
    local setup_default = utils.map_get(M.setup_opts.defaults, index)
    local setup_value = utils.map_get(M.setup_opts, index)

    -- 非表类型: 返回最高优先级的非 nil 值
    if setup_value ~= nil and type(setup_value) ~= "table" then
      return setup_value
    end
    -- ...

    -- 表类型: 逐层 deep_extend
    local ret = utils.tbl_deep_clone(fzflua_default) or {}
    ret = vim.tbl_deep_extend("force", ret, M.setup_opts.defaults or {})
    ret = vim.tbl_deep_extend("force", ret, setup_value or {})
    return ret
  end,
  -- 禁止直接修改 globals，防止意外的全局污染
  __newindex = function(_, index, _)
    assert(false, string.format("modifying globals directly isn't allowed"))
  end
})
```

```lua
-- config.lua:145-218 — normalize_opts 核心流程
function M.normalize_opts(opts, globals, __resume_key)
  -- 1. 展开点号 key: "winopts.border=single" → opts.winopts.border = "single"
  for _, k in ipairs(to_convert) do
    utils.map_set(opts, k, opts[k])
    opts[k] = nil
  end

  -- 2. 保存用户原始参数 (用于 resume)
  opts.__call_opts = opts.__call_opts or utils.deepcopy(opts)

  -- 3. 如果是 resume，合并上次的 call_opts
  if opts.resume then
    opts = M.resume_opts(opts)
  end

  -- 4. 合并 Provider 全局配置
  opts = vim.tbl_deep_extend("keep", opts, utils.tbl_deep_clone(globals))

  -- 5. 合并 winopts/keymap/fzf_opts/hls 等子表
  for _, k in ipairs({ "winopts", "keymap", "fzf_opts", "fzf_tmux_opts", "hls" }) do
    opts[k] = vim.tbl_deep_extend("keep", opts[k] or {}, M.globals[k] or {})
  end

  -- 6. 向后兼容选项迁移
  -- 如 winopts.win_row → winopts.row

  -- 7. 设置标记
  opts._normalized = true
  return opts
end
```

**原理**: `normalize_opts` 是配置系统的**统一入口**。每个 Provider 调用它时传入一个 key (如 `"files"`)，它从 `globals` 代理表获取该 Provider 的默认配置，然后通过 `vim.tbl_deep_extend` 按优先级合并。`__newindex` 断言确保没有人能意外修改全局配置，只能通过 `setup()` 修改。

---

## ❻ 命令包装 — `core.mt_cmd_wrapper()`

这是 fzf-lua 性能架构的**关键分叉点**，决定数据处理是在主进程还是 headless 子进程。

```lua
-- core.lua:772-897
M.mt_cmd_wrapper = function(opts)
  assert(opts and opts.cmd)

  -- 快速路径: 无需额外处理（无图标、无 Git、无过滤），直接返回原始命令
  if not opts.requires_processing
      and not opts.git_icons
      and not opts.file_icons
      and not opts.file_ignore_patterns
      and not opts.path_shorten
  then
    return opts.cmd  -- 直接返回 "fd --type f" 这样的字符串
  end

  -- 慢路径 A: 多进程模式（默认）— 启动 headless Neovim 子进程
  if opts.multiprocess then
    local cmd = libuv.wrap_spawn_stdio(
      serialize(filter_opts(opts)),           -- 序列化选项
      serialize(opts.__mt_transform or ...),  -- 转换函数的字符串形式
      serialize(opts.__mt_preprocess or ...), -- 预处理函数
      serialize(opts.__mt_postprocess or ...) -- 后处理函数
    )
    return cmd  -- 返回 "nvim --headless -l shell_helper.lua ..." 命令字符串
  end

  -- 慢路径 B: 单进程模式 — 在主 Neovim 进程中处理
  return libuv.spawn_nvim_fzf_cmd(opts,
    function(x) return make_entry.file(x, opts) end,   -- 逐行转换
    function(o) return make_entry.preprocess(o) end     -- 预处理
  )
end
```

**原理**: 这里的设计体现了 fzf-lua 的核心性能策略:

- **快速路径**: 当用户不需要图标/Git 状态时，直接将 `fd --type f` 传给 fzf，零开销
- **多进程路径**: 启动一个 `nvim --headless` 子进程，在其中执行 Lua 转换函数（添加图标、Git 状态、路径缩短等），通过管道将处理后的数据输出给 fzf。主 Neovim UI 完全不阻塞
- **单进程路径**: 在主进程中用 libuv 异步 spawn 命令，逐行转换数据。适用于无法序列化的复杂回调

`serialize` 函数使用 `serpent.line()` 将 Lua 表序列化为字符串，再用 base64 编码传给子进程，确保特殊字符不会破坏 shell 命令。

---

## ❼ 管道编排入口 — `core.fzf_exec()`

```lua
-- core.lua:135-194
M.fzf_exec = function(contents, opts)
  -- 支持 {{name, value}, ...} 数组格式
  if type(contents) == "table" and type(contents[1]) == "table" then
    contents = contents_from_arr(contents)
  end

  -- 确保 opts 已标准化
  if not opts or not opts._normalized then
    opts = config.normalize_opts(opts or {}, {})
  end

  -- 设置默认选择回调: 调用 actions.act()
  opts.fn_selected = opts.fn_selected or function(selected, o)
    if not selected then return end
    actions.act(opts.actions, selected, o)
  end

  -- ★ 关键分支: 如果 contents 是字符串且需要转换
  if type(contents) == "string" and (opts.fn_transform or opts.fn_preprocess) then
    -- 包装为 headless Neovim 命令
    contents = libuv.spawn_nvim_fzf_cmd(...)
  end

  -- ★ 关键分支: Live 模式 (fn_reload)
  if type(opts.fn_reload) == "string" then
    -- 原生模式: 利用 fzf 的 change:reload 事件
    opts = M.setup_fzf_interactive_native(opts.fn_reload, opts)
    contents = opts.__fzf_init_cmd
  end
  if type(opts.fn_reload) == "function" then
    -- 包装模式: 通过 headless Neovim 中转
    opts = M.setup_fzf_interactive_wrap(opts)
    contents = opts.__fzf_init_cmd
  end

  -- 进入协程包装
  return M.fzf_wrap(opts, contents)
end
```

**原理**: `fzf_exec` 是所有搜索的**统一入口**。它根据 `contents` 的类型和 `opts.fn_reload` 的存在，选择不同的数据管道:

| contents 类型 | fn_reload | 管道 |
|---|---|---|
| string | 无 | 命令直接给 fzf 作为 `$FZF_DEFAULT_COMMAND` |
| string | string | fzf 的 `change:reload` 原生重载 |
| string | function | headless Neovim 包装重载 |
| table | 无 | 写入 FIFO 管道 |
| function | 无 | 异步调用，逐行写入 FIFO |

---

## ❽ 协程创建 — `core.fzf_wrap()`

```lua
-- core.lua:223-247
M.fzf_wrap = function(opts, contents, fn_selected)
  opts = opts or {}
  local _co
  coroutine.wrap(function()
    _co = coroutine.running()

    -- 调用核心 fzf 函数（会在 coroutine.yield() 处暂停）
    opts.fn_selected = opts.fn_selected or fn_selected
    local selected = M.fzf(contents, opts)

    -- fzf 退出后，协程恢复，执行选择回调
    if opts.fn_selected then
      xpcall(function()
        opts.fn_selected(selected, opts)
      end, function(err)
        -- 特殊处理 E325 (swap file) 错误
        if err:match("Vim%(edit%):E325") then return end
        utils.err("fn_selected threw an error: " .. debug.traceback(err, 1))
      end)
    end
  end)()
  return _co
end
```

**原理**: 整个 fzf 交互被包裹在一个协程中。协程使得异步的 fzf 进程（通过 `termopen` 启动）能够以同步风格编写代码:

1. `coroutine.wrap` 创建协程并立即执行
2. 在 `M.fzf()` → `fzf.raw_fzf()` 内部，调用 `coroutine.yield()` **暂停**协程
3. 当 fzf 进程退出时，`on_exit` 回调调用 `coroutine.resume(co, output, rc)` **恢复**协程
4. 协程恢复后，`selected` 得到用户选择的结果，继续执行 `fn_selected`

`xpcall` 包裹确保即使 action 回调抛出异常，也不会导致协程崩溃。

---

## ❾ 主函数 — `core.fzf()`

这是约 160 行的核心函数，编排了窗口、预览器、fzf 进程的整个生命周期。

```lua
-- core.lua:303-465（关键步骤注释）
M.fzf = function(contents, opts)
  -- [1] 保存 --print-query，用于 resume 时恢复查询
  opts.fzf_opts["--print-query"] = true

  -- [2] 为 esc/ctrl-c 等设置 dummy 回调，确保查询也能被保存
  for _, k in ipairs({ "ctrl-c", "ctrl-q", "esc", "enter" }) do
    if opts.actions[k] == nil then
      opts.actions[k] = actions.dummy_abort
    end
  end

  -- [3] 存储 resume 数据
  config.__resume_data = { opts = utils.deepcopy(opts), contents = ... }

  -- [4] 保存调用者上下文 (窗口/缓冲区/光标位置)
  opts.__CTX = M.CTX()

  -- [5] ★ 创建浮动窗口
  local fzf_win = win(opts)
  if not fzf_win then return end

  -- [6] ★ 实例化 Previewer
  if preview_opts and type(preview_opts._ctor) == "function" then
    previewer = preview_opts._ctor()(preview_opts, opts, fzf_win)
  end
  if previewer then
    opts.preview = previewer:cmdline()  -- 获取预览命令行
    -- fzf 0.40: 无匹配时清空预览
    if opts.__FZF_VERSION >= 0.40 and previewer.zero then
      utils.map_set(opts, "keymap.fzf.zero", previewer:zero())
    end
  end

  -- [7] 执行 pre-fzf 钩子
  if opts.fn_pre_fzf then opts.fn_pre_fzf(opts) end

  -- [8] 将 Previewer 绑定到窗口
  fzf_win:attach_previewer(previewer)
  local fzf_bufnr = fzf_win:create()

  -- [9] 将 opts.actions 转换为 fzf 的 --bind 参数
  opts = M.convert_reload_actions(opts.__reload_cmd or contents, opts)

  -- [10] ★★★ 构建 fzf CLI 参数并启动 fzf 进程
  local selected, exit_code = fzf.raw_fzf(
    contents,
    M.build_fzf_cli(opts, fzf_win),  -- 构建 ["--prompt=...", "--bind=...", ...]
    { fzf_bin = opts.fzf_bin, cwd = opts.cwd, ... }
  )
  -- ^^^ 协程在这里 YIELD，等待 fzf 退出 ^^^

  -- [11] fzf 退出，协程恢复
  -- 提取查询字符串 (--print-query 的第一行)
  if selected and #selected > 0 then
    config.resume_set("query", selected[1], opts)
    table.remove(selected, 1)  -- 移除查询行，只保留选中项
  end

  -- [12] 执行 post-fzf 钩子
  if opts.fn_post_fzf then opts.fn_post_fzf(opts, selected) end

  -- [13] 检查退出状态，处理窗口关闭
  fzf_win:check_exit_status(exit_code, fzf_bufnr)

  -- [14] 解析按键绑定，决定是否关闭窗口
  local keybind = actions.normalize_selected(opts.actions, selected, opts)
  local action = keybind and opts.actions[keybind]
  local noclose = type(action) == "table"
      and (action[1] ~= nil or action.reload or action.noclose)
  if not noclose then
    fzf_win:close(fzf_bufnr)
  end

  return selected
end
```

**原理**: `core.fzf()` 是整个管道的**编排中心**，按照严格的生命周期管理各组件:

```
创建窗口 → 实例化 Previewer → pre_fzf 钩子 → 创建终端缓冲区
→ 构建 CLI 参数 → 启动 fzf (yield) → ... 用户交互 ...
→ fzf 退出 (resume) → 提取查询 → post_fzf 钩子
→ 检查退出码 → 解析按键 → 关闭/保留窗口 → 返回 selected
```

---

## ❿ FIFO 管道与 fzf 交互 — `fzf.raw_fzf()`

这是数据最终到达 fzf 二进制的核心函数。

```lua
-- fzf.lua:41-320
function M.raw_fzf(contents, fzf_cli_args, opts)
  -- [1] 必须在协程中运行
  if not coroutine.running() then
    error("[Fzf-lua] function must be called inside a coroutine.")
  end

  local cmd = { opts.fzf_bin or "fzf" }     -- fzf 命令
  local fifotmpname = tempname()              -- FIFO 命名管道路径
  local outputtmpname = tempname()            -- 输出临时文件路径

  -- [2] 根据 contents 类型选择输入方式
  if type(contents) == "string" then
    -- 字符串命令: 设为 $FZF_DEFAULT_COMMAND，让 fzf 自己执行
    FZF_DEFAULT_COMMAND = contents
  else
    -- 表或函数: 通过 FIFO 管道输入
    -- "cat {fifo}" 作为 FZF_DEFAULT_COMMAND（解决 fish shell 兼容性）
    FZF_DEFAULT_COMMAND = string.format("cat %s", shellescape(fifotmpname))
  end

  -- [3] 输出重定向到临时文件
  table.insert(cmd, ">")
  table.insert(cmd, shellescape(outputtmpname))

  -- [4] 如果 contents 是表/函数，创建 FIFO
  if type(contents) == "function" or type(contents) == "table" then
    vim.fn.system({ "mkfifo", fifotmpname })  -- 创建命名管道
  end

  -- [5] ★ 通过 termopen 在浮动窗口的终端中启动 fzf
  local co = coroutine.running()
  vim.fn.termopen(shell_cmd, {
    cwd = cwd,
    pty = true,
    env = {
      ["FZF_DEFAULT_COMMAND"] = FZF_DEFAULT_COMMAND,
      -- 清理 FZF_DEFAULT_OPTS 中的 --preview-window（防冲突）
      ["FZF_DEFAULT_OPTS"] = cleaned_default_opts,
      -- 置空 RIPGREP_CONFIG_PATH（防冲突）
      ["RIPGREP_CONFIG_PATH"] = "",
    },
    on_exit = function(_, rc, _)
      -- [8] fzf 退出: 读取输出文件
      local output = {}
      local f = io.open(outputtmpname)
      if f then
        output = vim.split(f:read("*a"), printEOL)
        f:close()
      end
      -- 清理临时文件
      vim.fn.delete(fifotmpname)
      vim.fn.delete(outputtmpname)
      -- ★ 恢复协程，将结果传回
      coroutine.resume(co, output, rc)
    end
  })

  -- [6] 设置终端模式
  vim.cmd [[set ft=fzf]]
  vim.cmd [[startinsert]]  -- 进入终端 INSERT 模式

  -- [7] 如果 contents 是表/函数，打开 FIFO 写端并写入数据
  if type(contents) == "function" or type(contents) == "table" then
    fd = uv.fs_open(fifotmpname, "w", -1)    -- 打开 FIFO 写端
    output_pipe = uv.new_pipe(false)
    output_pipe:open(fd)
    handle_contents()  -- 调度数据写入
  end

  -- ★ 暂停协程，等待 on_exit 回调
  return coroutine.yield()
end
```

**数据写入机制**:

```lua
-- fzf.lua:191-204
handle_contents = vim.schedule_wrap(function()
  if type(contents) == "table" then
    -- 表: 一次性写入所有行
    write_cb(vim.tbl_map(function(x) return x .. "\n" end, contents))
    finish()
  elseif type(contents) == "function" then
    -- 函数: 调用用户函数，传入写入回调
    -- usr_write_cb(true) 返回一个自动添加换行的写入函数
    contents(usr_write_cb(true), usr_write_cb(false), output_pipe)
  end
end)
```

**原理**:

整个 fzf 交互通过三个临时文件/管道实现进程间通信:

```
数据源 ──→ FIFO 命名管道 (fifotmpname) ──→ fzf 进程 stdin
                                              │
                                              ↓
                              fzf 进程 stdout ──→ 临时文件 (outputtmpname)
                                                       │
                                                       ↓
                                              Lua 读取结果
```

- **输入**: 如果 contents 是字符串（如 `fd --type f`），设为 `$FZF_DEFAULT_COMMAND` 让 fzf 自己执行，这样 fzf 退出时能自动终止数据源命令。如果 contents 是表/函数，通过 FIFO 管道异步写入
- **输出**: fzf 的选择结果重定向到临时文件，`on_exit` 中读取并解析
- **协程桥接**: `coroutine.yield()` 暂停等待 fzf 退出，`on_exit` 中 `coroutine.resume()` 恢复，实现了异步操作的同步编码风格

---

## ⓫ 结果分发 — `actions.act()`

```lua
-- actions.lua:87-113
M.act = function(actions, selected, opts)
  if not actions or not selected then return end

  -- [1] 将 fzf 输出分离为 (按键, 条目列表)
  local keybind, entries = M.normalize_selected(actions, selected, opts)

  -- [2] 根据按键查找对应的 action
  local action = actions[keybind]
  if not action and keybind == "enter" then
    action = actions.default  -- 向后兼容
  end

  -- [3] 执行 action
  if type(action) == "table" then
    if action.fn then
      action.fn(entries, opts)           -- {fn=..., reload=true} 形式
    else
      for _, f in ipairs(action) do
        f(entries, opts)                 -- 串行执行多个 action
      end
    end
  elseif type(action) == "function" then
    action(entries, opts)                -- 简单函数
  elseif type(action) == "string" then
    vim.cmd(action)                      -- Vim 命令字符串
  end
end
```

**按键解析机制** (`normalize_selected`):

```lua
-- actions.lua:55-84
M.normalize_selected = function(actions, selected, opts)
  if opts.__FZF_VERSION >= 0.53 then
    -- fzf 0.53+: 使用 print(key)+accept，keybind 在 selected[1]
    local entries = vim.deepcopy(selected)
    local keybind = table.remove(entries, 1)
    return keybind, entries
  else
    -- 旧版本: 使用 --expect，keybind 在 selected[1] (enter 为空字符串)
    if utils.tbl_count(actions) > 1 or not actions.enter then
      local entries = vim.deepcopy(selected)
      local keybind = table.remove(entries, 1)
      if #keybind == 0 then keybind = "enter" end
      return keybind, entries
    else
      return "enter", selected
    end
  end
end
```

**原理**: fzf 的输出格式取决于版本:

- **fzf ≥ 0.53**: 使用 `--bind "enter:print(enter)+accept"` 语法，按键名通过 `print()` 输出到第一行
- **fzf < 0.53**: 使用 `--expect` 标志，按键名输出到第一行（enter 输出空字符串）

`actions.act` 根据按键名从 `opts.actions` 表中查找对应的处理函数。默认 enter 绑定的 action 通常是 `actions.file_edit`，它会解析文件路径/行号并在 Neovim 中打开文件。

---

## 附: `build_fzf_cli()` — fzf 命令行组装

```lua
-- core.lua:624-690 (关键步骤)
M.build_fzf_cli = function(opts, fzf_win)
  -- 1. 合并全局 fzf_opts
  opts.fzf_opts = vim.tbl_extend("force", config.globals.fzf_opts, opts.fzf_opts)

  -- 2. 将 opts.query/prompt/header/preview 映射到 --query/--prompt 等
  for _, flag in ipairs({ "query", "prompt", "header", "preview" }) do
    if opts[flag] ~= nil then
      opts.fzf_opts["--" .. flag] = opts[flag]
    end
  end

  -- 3. 转换 preview 函数为 shell 命令
  if type(opts.fzf_opts["--preview"]) == "function" then
    opts.fzf_opts["--preview"] = shell.raw_action(preview_fn, "{}")
  end

  -- 4. 构建 --bind (键绑定) 和 --color (颜色)
  opts.fzf_opts["--bind"] = M.create_fzf_binds(opts)
  opts.fzf_opts["--color"] = M.create_fzf_colors(opts)

  -- 5. 构建 --expect (按键监听)
  local expect_keys, expect_binds = actions.expect(opts.actions, opts)
  opts.fzf_opts["--expect"] = table.concat(expect_keys, ",")

  -- 6. 构建 --preview-window
  opts.fzf_opts["--preview-window"] = M.preview_window(opts, fzf_win)

  -- 7. 将 opts.fzf_opts 表转为命令行参数数组
  return M.fzf_opts_to_cli(opts)
end
```

这个函数将高层的 Lua 配置表翻译为 fzf 能理解的命令行参数数组，如 `["--prompt=Files❯ ", "--bind=ctrl-a:select-all", "--color=fg:#c0caf5", ...]`。

---

## 总结: 核心设计决策

| 决策 | 实现 | 意义 |
|------|------|------|
| **协程驱动** | `coroutine.wrap` + `yield`/`resume` | 异步 fzf 进程以同步风格编码，避免回调地狱 |
| **FIFO 管道** | `mkfifo` + `uv.new_pipe` | 支持流式大数据写入，不阻塞主进程 |
| **$FZF_DEFAULT_COMMAND** | 字符串命令设为环境变量 | fzf 自行管理子进程生命周期，退出时自动终止 |
| **Headless Neovim** | `nvim --headless -l shell_helper.lua` | 在独立进程中执行 Lua 数据转换，UI 零阻塞 |
| **惰性加载** | 双层函数包装 + 元方法 | 96 个命令零启动开销，按需加载模块 |
| **三级配置** | `__index` 元方法 + `tbl_deep_extend` | 灵活的优先级配置而不复制全局状态 |
| **print()+accept** | fzf 0.53 按键路由 | 替代 `--expect`，避免空行 bug (#1241) |
