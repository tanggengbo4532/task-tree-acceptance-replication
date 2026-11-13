# 后端动作契约（Backend Contract）v4 · 通用应用

> 本文件是 `game-playtest` 插件**与引擎/平台无关**的边界：4-Agent 框架（Lead/开发/测试/记录）
> 与所有工具只依赖本契约，不依赖任何具体引擎或窗口实现。任何应用（桌面软件、Web/Electron、
> 游戏）只要实现下列动作，即可被本插件黑盒驱动。

## 0. 两个已注册后端

| 后端 | 入口 | 运行方式 | 覆盖 |
|---|---|---|---|
| `windows` | `scripts/windows/PlaytestKit.ps1`（共用 `Common.ps1`，截图 `Capture.ps1`） | PowerShell 5.1+ | Windows 桌面应用/游戏 |
| `web` | `scripts/backends/web/adapter.py` | Python 3.8+，Edge/Chrome（CDP，零第三方依赖） | 网页/Electron 渲染层 |

选择方式只有一个：`playtest.json` 的 `backend` 字段（或 `backend_path` 直接给适配器路径）。
所有工具（`tools/backendlib.py`、探针、`step_runner`、`hud_walker`、`anchor_check`）都通过同一分发层
调用后端，工具不关心具体后端。

## 1. 调用与输出

```text
<runner> <adapter> -Action <name> [-Value <args>] -Config <playtest.json>
```

`runner` 按适配器扩展名决定：`.ps1` → `powershell -NoProfile -ExecutionPolicy Bypass -File`；
`.py` → `python -B`。**stdout 最后一行必须是且只用一个 JSON 对象**（其余行可为人类可读摘要）：

```json
{"ok": true,  "action": "shot", "path": "C:\\evidence\\a.png", "method": "printwindow"}
{"ok": false, "action": "keys", "error": "input gate: target window is not foreground"}
{"ok": false, "action": "state", "unsupported": true, "error": "state is not implemented"}
```

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 失败（`ok:false` 且有 `error`） |
| 3 | 该动作**未实现**（`unsupported:true`）；工具据此降级或报"能力缺失"，**绝不当作通过** |

stderr 写人类可读的错误详情。

## 2. 动作

### 2.1 必需动作

| 动作 | Value | 语义 |
|---|---|---|
| `launch` | （读配置） | 启动目标（单实例）。等窗口/页面就绪后返回 `pid`、`hwnd`/`url`、`title`。**就绪失败必须返回非 0**（并可通过 `close` 清理）。 |
| `close` | — | 关闭**由 launch 启动的**进程。禁止关闭无关进程；无启动记录时只有在定位唯一时才可关闭。 |
| `focus` | — | 目标置前台。 |
| `info` | — | `pid hwnd title iconic/zoomed rect client foreground`（Web：`url title client dpr`）。 |
| `keys` | `KEY[,KEY...]` | 依次轻按（时长/间隔见 `keys.default_hold_ms`/`gap_ms`）。**发送前先校验全部键名**，未知键则一个都不发。 |
| `hold` | `KEY,MS` | 按住 MS 毫秒后释放。 |
| `shot` | `NAME`（可空） | 截客户区/视口整帧，返回**绝对路径**；同名**自动加后缀，绝不覆盖**。 |
| `click` | `X,Y[,left\|right\|double]` | 按客户区/视口坐标点击。越界或目标点在**别的窗口/元素之下**必须拒绝。 |
| `type` | `TEXT` | 向当前焦点输入文本（支持任意 Unicode）。 |
| `scroll` | `X,Y,NOTCHES` | 在坐标处滚动（正数向上）。 |

### 2.2 可选动作

| 动作 | Value | 语义 |
|---|---|---|
| `diag` | `KEY1,KEY2,MS` | 双键组合（斜向移动等）。 |
| `hint` | `NAME` | 整帧 + 按 `capture.crop_hint` 裁剪的局部图（检查提示文案）。**未配置裁剪区域时报错**，不得猜区域。 |
| `read_text` | 空 / `css=<selector>` | 读取**用户可见**文本（无障碍树/DOM `innerText`）。未实现时返回 `UNSUPPORTED`。 |
| `state` | — | 只读导出当前状态 JSON（见 §3）。未实现时返回 `UNSUPPORTED`。 |
| `test_fast` | `on\|off` | **仅测试构建**的时间缩放；不得改变逻辑。 |
| `failure_snapshot` | `NAME` | 打包"截图 + 最近按键 + 状态 JSON"到失败目录。 |

> Windows 参考后端实现了 2.1 全部与 `diag`/`hint`；`state`/`read_text`/`test_fast`/`failure_snapshot`
> 显式返回 `UNSUPPORTED`（退出码 3），因为像素后端无法在不侵入应用的前提下导出状态。
> `failure_snapshot` 的组装在工具侧完成（`tools/verify/step_runner.py`），不依赖后端。

### 2.3 `click` 的元素定位（只用于"点哪里"，不替代点击）

`web` 后端额外接受 `css=<selector>` 或 `text=<可见文本>`，服务端解析出坐标后**仍发送真实鼠标事件**，
并在解析阶段拒绝：元素不存在、隐藏（尺寸为 0）、`disabled`、文本匹配到多个元素、中心点被其他元素遮挡。
这属于"输入门禁"：点不到就报错，而不是点偏了算通过。

## 3. `state` 导出 schema

公共字段（能提供的后端尽量提供）：

```json
{
  "location": "app://notes#/list",
  "title": "Notes - List",
  "visible_text": "Notes\nWelcome, ann\n...",
  "focus": {"tag": "input", "id": "note", "value": "milk"},
  "busy": false,
  "viewport": [1280, 800],
  "scroll": [0, 120]
}
```

游戏类后端可扩展 `scene`/`floor`/`pos`/`flags`/`central_text`/`objective` 等**引擎自定义字段**；
工具只认公共字段加自己声明的路径（`step_runner` 的 `expect.state` 支持点路径，如 `focus.value`）。

约束：`state` **只读**，不得写状态、跳阶段、改存档。无法导出必须返回 `UNSUPPORTED` 或非 0，
**不得返回伪造数据**。

## 4. 配置（playtest.json v3）

公共必填：`backend`（或 `backend_path`）、`launch`，以及定位信息（`title_pattern`/`process_name` 至少一个，
或 `web.url`）。其余可选。

```json
{
  "name": "notes-web-app",
  "backend": "web",
  "launch": "https://staging.example.com/login",
  "process_name": "msedge",
  "title_pattern": "*Notes*",
  "args": [],
  "startup_ms": 15000,
  "focus_before_key": true,
  "input": { "method": "postmessage" },
  "capture": { "method": "auto", "dpi_aware": true, "topmost_ms": 400, "crop_hint": [200, 80, 880, 60] },
  "keys": { "default_hold_ms": 60, "gap_ms": 550, "allow_postmessage": true },
  "web": { "browser": "msedge", "headless": false, "viewport": [1280, 800], "url": "", "state_text_limit": 4000 },
  "evidence": { "dir": "C:\\QA\\evidence\\round01\\shots", "manifest": "manifest.json", "append_only": true },
  "metrics": { "sessions_dir": "", "window": null },
  "notes": {}
}
```

- `input.method`：`postmessage`（默认，见 §5）或 `sendinput`（真实全局输入，目标必须前台）。
  `keys.allow_postmessage=false` 等价于 `sendinput`（v2 兼容）。
- `web.*` 仅 `web` 后端使用；`capture.*` 仅 `windows` 后端使用。
- `notes`：自由备注。调试快捷键只允许开发 Agent 使用，不得出现在测试用例/验收证据中。

## 5. 输入方式与门禁

| method | 实现 | 适用 | 代价 |
|---|---|---|---|
| `postmessage` | `WM_KEYDOWN/UP`、`WM_CHAR`、`WM_LBUTTONDOWN/UP`、`WM_MOUSEWHEEL` | 大多数 Win32/WinForms/WPF/Unity(旧输入)/Electron | 使用 Raw Input 或 DirectInput 的应用可能收不到 |
| `sendinput` | `SendInput`（全局真实输入） | 任何应用 | 占用真实光标/焦点；后端**必须**在前置校验前台窗口是目标，否则拒绝发送 |
| `cdp-input` | CDP `Input.dispatchKeyEvent/dispatchMouseEvent/insertText` | 浏览器 | 仅在浏览器内生效 |

发送前门禁（违反即报错，不得"发送后再说"）：

1. `sendinput`：目标必须是前台窗口，否则拒绝；
2. `postmessage` 点击：目标点必须位于客户区内，且该点所在窗口属于目标进程；
3. 键名/坐标/按钮格式非法时**整批拒绝**（不发送半批）；
4. 每次成功注入都追加一行到 `<evidence>/input-log.jsonl`（时间/动作/值/方式），作为"真实输入"的可审计证据。

## 6. 纪律（可交付/可复现的硬约束）

1. **单实例**：定位信息缺失时**不得**退化为"任意窗口"；匹配到多个窗口时报错并列出候选。
   `launch` 记录 pid + 进程启动时间 + 窗口所属 pid，后续动作优先按该记录定位；`close` 只关闭
   这次启动的进程（pid 复用会被启动时间识别出来）。
2. **截图**：优先 `PrintWindow`，空白/纯色帧自动回退 `CopyFromScreen`，并把使用方式写入输出。
3. **DPI**：后端启动即声明 DPI aware；坐标一律客户区物理像素（Web 为视口 CSS 像素）。
4. **证据只增**：`shot`/`hint` 同名不覆盖，自动加 `_2`、`_3` 后缀。
5. **不伪造**：不写应用内存、不伪造事件、不跳剧情/不直接改数据库或内部状态；一切输入走真实键鼠或
   平台公开输入 API；`state` 只读。
6. **不抢资源**：同一时刻只允许一个被测实例；用户或其他 Agent 在同机测试时不得再启动。
7. **可插拔**：新增引擎/平台只需实现 §2 必需动作 + 本文件约定，并在 `plugin.json` 的 `backends`
   注册（`name`/`path`/`runtime`/`platforms`/`actions`/`unsupported`/`status`），**不得改动** 4-Agent
   框架与模板。
8. **错误语义**：窗口/页面找不到、权限拒绝、截图失败必须非 0 并给出可操作信息；能力缺失用
   `UNSUPPORTED`（退出码 3），不得静默成功。

## 7. verification 扩展：state / test_fast / failure_snapshot

自动验证（`step_runner`、`hud_walker`、`anchor_check`）依赖后端能力，缺失时**降级并标注**，不得假装成功：

| 能力 | 用途 | 缺失时 |
|---|---|---|
| `state` | 每步期望（文本/位置/场景/焦点）与锚点比对 | `step_runner` 只能用截图差异判断 `changed`；其他期望直接报配置错误（退出码 2）；`hud_walker`/`anchor_check` 退出码 2 |
| `read_text` | 状态里没有 `visible_text` 时读可见文本 | 文本类期望不可用 |
| `test_fast` | 仅测试构建的时间缩放 | 不加速 |
| `failure_snapshot` | 失败备份 | `step_runner` 自己组装（截图 + `keys.jsonl` + `state.json` + `manifest.json`） |

### 7.1 `test_fast` 强制约束（与 `references/standards/no-cheat.md` §6 一致）

**正式包不得包含**测试分支、时间缩放开关或任何测试后门。`test_fast` 只允许存在于独立 debug 构建，
或由构建外工具实现；使用 `test_fast` 时证据必须标注构建类型，且不得用于"让节点通过"。

### 7.2 失败快照目录

```text
<evidence_dir>/failures/fail_<node>_<yyyymmdd-HHMMSS>_s<NN>/
  frame.png          # 失败瞬间完整帧
  keys.jsonl         # 截至失败的全部输入步骤
  state.json         # 失败瞬间 state 导出（有则写）
  manifest.json      # 节点/步骤/期望/失败原因/文件清单
```

### 7.3 引擎实现指引

- **Godot**：`state` 从 world/scene 单例只读导出（建议 debug 构建）；`keys` 用 InputEvent 或沿用
  Windows 消息；`test_fast` 用 `Engine.time_scale`（仅 `--test-fast` 启动的测试构建）；
- **Unity**：`state` 从只读单例/序列化快照导出；`keys` 用 Input System 注入或 Windows 消息；
  固定窗口分辨率；避免 Editor 与 Player 同时运行；
- **Web/Electron**：见 `web` 后端（`state` 由可访问性/DOM 导出，`read_text` = `innerText`）；
  Electron 若只测渲染层直接用 `web` 后端指向调试端口即可；
- **桌面通用**：无状态导出能力时显式 `UNSUPPORTED`，工具降级为截图差异并标注局限。
