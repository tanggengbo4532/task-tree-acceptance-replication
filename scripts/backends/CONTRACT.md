# 后端动作契约（Backend Contract）v1 · verification 扩展 v3.2

> 本文件是 `game-playtest` 插件**引擎无关**的边界：4-Agent 框架（Lead/开发/测试/记录）只依赖本契约，
> 不依赖任何具体引擎或窗口实现。任何引擎/应用只要实现下列动作，即可被本插件黑盒驱动。

## 1. 动作（Actions）

所有动作通过后端入口脚本以 `-Action <name> -Value <args>` 调用（Windows 参考实现：
`scripts/windows/PlaytestKit.ps1`）。**成功返回 0，失败返回非 0**，并在 stdout 输出机器可解析的一行摘要
（`KEY=value` 或 JSON 行）；stderr 输出错误详情。

| 动作 | 参数（Value 约定） | 语义 | 必需 |
|---|---|---|---|
| `launch` | 无（读配置） | 启动目标应用/游戏（单实例），等待窗口出现并记录 pid/hwnd | ✅ |
| `close` | 无 | 关闭由 `launch` 启动的进程（优先用记录的 pid；禁止杀无关进程） | ✅ |
| `focus` | 无 | 把目标窗口置前台（必要时先 restore），返回 pid/hwnd | ✅ |
| `info` | 无 | 输出窗口状态：`pid hwnd title iconic/zoomed rect client fgIsGame` | ✅ |
| `keys` | `KEY[,KEY...]` 或 `TEXT` | 依次发送轻按（默认 60ms/键，间隔由配置）；方向键/空格/回车/ESC/F1..F12 | ✅ |
| `hold` | `KEY,MS` | 按住某键 MS 毫秒后释放（长按/蓄力/连续移动） | ✅ |
| `diag` | `KEY1,KEY2,MS` | 斜向/组合双键（避免单键被门/轨道吃掉） | 可选* |
| `shot` | `NAME`（可空=时间戳） | 截取**客户区**完整帧，输出**绝对路径**；优先 PrintWindow，空白则回退屏幕拷贝 | ✅ |
| `hint` | `NAME`（可空） | 截完整帧 + 按配置裁剪的提示条图（用于逐步检查文案/箭头） | 可选* |
| `diag`（诊断输出） | 无 | 返回窗口/前台/DPI/截帧方式（printwindow/screencopy）等诊断信息 | 可选* |
| `read_text` | `REGION` 或全帧 | **可选**：读取 UI 文本（引擎钩子/Ocr/内部日志）。未实现时必须明确返回 `UNSUPPORTED` | ❌ 可选 |

\* 为兼容旧版保留；实现方可只实现必需动作，缺失动作用 `UNSUPPORTED` 显式返回并写 stderr。

## 2. 配置（playtest.json v2）

**必填**：`name`、`launch`、`title_pattern`（或 `process_name`，二者至少一个）；
**可选**：其余字段；旧 v1 字段（顶层 `hint_region` / `shot_dir`）仍向后兼容。

```json
{
  "name": "app-name",
  "backend": "windows",
  "launch": "C:\\path\\to\\app.exe",
  "args": ["--path", "C:\\game", "res://main.tscn"],
  "process_name": "app*",
  "title_pattern": "*Window Title*",
  "startup_ms": 8000,
  "focus_before_key": true,
  "shot_dir": "C:\\evidence\\shots",
  "capture": {
    "method": "auto",
    "dpi_aware": true,
    "topmost_ms": 400,
    "crop_hint": [60, 145, 1160, 100]
  },
  "keys": { "default_hold_ms": 60, "gap_ms": 550, "allow_postmessage": true },
  "evidence": { "dir": "C:\\evidence\\shots", "manifest": "C:\\evidence\\manifest.json", "append_only": true },
  "metrics": { "sessions_dir": "%USERPROFILE%\\.dsh\\storages\\session_projcache\\sessions", "window": null },
  "notes": {}
}
```

字段要求：
- `launch`：可执行文件绝对路径（或后端约定的启动命令）。
- `backend`：后端名（默认 `windows`；Web/Unity/Godot 见 §4）；`backend_path` 可选，覆盖入口脚本路径。
- `title_pattern` / `process_name`：窗口定位（多实例时以 `launch` 返回 pid 为准）。
- `shot_dir`：证据目录（v1 兼容；推荐改用 `evidence.dir`），后端必须写**绝对路径**到 stdout。
- `capture.method`：`auto|printwindow|screencopy`；`capture.crop_hint`：提示条裁剪区域 `[x,y,w,h]`（客户区像素；v1 `hint_region` 等价）。
- `keys.default_hold_ms`/`gap_ms`：轻按时长与间隔（默认 60/550ms）；`allow_postmessage` 默认 true。
- `evidence.manifest`：append-only 证据清单路径；`append_only` 默认 true。
- `metrics.sessions_dir`：DSH `session_projcache/sessions` 目录，供 `tools/metrics/dsh_metrics.py` 估算 token/用时。
- `notes`：自由备注（调试快捷键只允许开发 Agent 使用，不得写入测试用例）。

## 3. 纪律（可交付/可复现的硬约束）

1. **单实例**：同一应用同时只允许一个被测试窗口/进程；启动前如发现残留窗口须先 `close`。
2. **前台**：截图/按键前 `focus`；截图时临时 topmost，完成后**恢复非 topmost**，避免压住用户其他窗口。
3. **DPI**：后端启动即声明 DPI aware；截图一律按**客户区物理像素**，坐标不得混用逻辑像素。
4. **防假帧**：PrintWindow 可能返回空白/纯色帧；必须做空白检测并**回退 CopyFromScreen**，并把使用方式写入输出。
5. **不伪造**：后端不得直接写游戏内存、伪造事件状态、跳过剧情/战斗、瞬移/改档；一切输入走真实键鼠/引擎公开输入 API。
6. **不抢资源**：host 上有用户/其他 Agent 测试时，禁止启动第二个实例；headless/自检不得拉起游戏窗口。
7. **可插拔**：实现方通过 `backend` 字段选择；新增引擎只需实现 §1 必需动作 + 本文件约定，不得改动 4-Agent 框架与模板。
8. **错误语义**：窗口找不到、权限拒绝、截图失败等必须非 0 退出并给出可操作错误；不得静默成功。

## 4. 常见引擎实现指引

### 4.1 Windows 桌面应用 / 通用（参考实现）
- 实现：`scripts/windows/PlaytestKit.ps1`（键鼠/窗口）+ `scripts/windows/Capture.ps1`（截图/裁剪/空白回退）。
- 键：`PostMessage(WM_KEYDOWN/UP)` 优先（不抢焦点）；应用不认时改为前台 `SendInput`。
- 截图：`PrintWindow(PW_RENDERFULLCONTENT)` → 空白检测 → `CopyFromScreen` 回退。

### 4.2 Web / Electron
- `launch`：起本地服务或打包 exe；`title_pattern` 匹配浏览器窗口标题或使用 Playwright。
- `keys/hold`：Playwright `page.keyboard`（真实事件）；`shot`：`page.screenshot()`（客户区）。
- `info`：`page.title/url/viewport`；`read_text`：可用 `page.locator(...).inner_text()` 明确实现。
- 纪律：单浏览器上下文、固定 viewport、禁多标签；截图前 `bringToFront()`。

### 4.3 Unity
- `launch`：exe（`-screen-width/-screen-height -screen-fullscreen 0` 便于固定窗口）；或用 Unity Test Framework 走引擎内输入。
- `keys/hold`：Windows 消息实现即可（同上）；`read_text` 可用引擎内测试钩子（如 `TestBridge`）暴露为文件/HTTP。
- 纪律：开发模式 `-logFile` 输出可观测日志；测试窗口固定分辨率；避免 Editor 与 Player 同时跑。

### 4.4 Godot（本项目参考）
- `launch`：`Godot...exe --path <proj> res://main.tscn`；可用 `--headless` 跑非交互自检（自检不得截图/抢前台）。
- 可观测性钩子：项目内提供 `--debug-hud`（状态行）、`quit_trace.log`、probe 场景（输入脚本）等，见 `examples/godot-project.md`。
- 纪律：编辑器/游戏单实例；窗口标题用 `title_pattern` 精确匹配，避免误杀编辑器。

## 5. 后端交付清单（新引擎适配时）

- [ ] `scripts/backends/<engine>/adapter.<ext>` 实现 §1 必需动作（`-Action`/`-Value` 入口）。
- [ ] 在 `plugin.json` 的 `backends` 注册（name/path/platforms/status）。
- [ ] `examples/<engine>-*.json` 配置样例（脱敏）。
- [ ] `tools/tests/selftest.py` 增加该后端 dry-run 校验（无窗口也能跑）。
- [ ] 在 README/SKILL 中写清后端切换方式（由 Lead/主控写，开发者不改他人写区）。

## 6. verification backend 契约（v3.2 验证自动化扩展）

> v3.2 起，自动验证（锚点库 + HUD 走位器 + 自动断言 + trace diff）依赖 backend 具备"注入按键 + 导出状态 + 证据/失败快照"能力。**引擎无关**；能力缺失必须显式 `UNSUPPORTED`，不得假装成功。
> 旧 backend 不实现本节时，v3.1 流程仍可跑；walker 自动降级为截图 OCR / 人工并标注局限。

| 能力 | 动作 / 参数 | 语义 | 必需性 |
|---|---|---|---|
| **keys** | 沿用 §1 `keys`/`hold`/`diag` | 真实按键注入（**自动化走位依赖**；不传送/不改状态） | ✅ 必需 |
| **shot / screenshot** | `shot NAME`（别名 `screenshot`） | 证据/失败快照截图，stdout 返回绝对路径 | ✅ 必需 |
| **state** | `state`（Value 空或 `json`） | 只读导出当前状态 JSON（见下 schema）；供 walker 断言/trace | ✅ verification 必需（无则降级 OCR 并标注） |
| **test_fast** | `test_fast on|off`（或配置 `test_fast: true`） | **仅测试构建**时间缩放（过场/淡入淡出/对白打字/ride 动画）；不改逻辑、不跳剧情/战斗、不改状态；默认 off；HUD 显示测试角标 | 可选 |
| **failure_snapshot** | `failure_snapshot NAME` | 打包"截图 + 最近 30 帧按键 + 状态 JSON"到失败目录，stdout 返回目录/清单路径 | 可选（walker 可自行拼装） |

### 6.1 `state` 导出 schema（最小集）

```json
{
  "scene": "scene4",
  "floor": "1F",
  "pos": [1088, 1648],
  "central_text": "客栈：出店门 → 街道 → 十里坡（山神庙）",
  "objective": "A12",
  "flags": {"a11_stage": 1, "a9_stage": 3},
  "party": [{"id": 1, "lv": 3, "hp": 45, "mp": 12}],
  "busy": false,
  "test_fast": false,
  "build": "c77ae7a"
}
```

- 字段缺失可省略，但 `scene`/`pos` 建议必有（walker 位移判定用）；`central_text`/`objective` 用于 N/方向解析与 diff；
- **只读**：`state` 只导出、不写状态；`test_fast` 只改时间不改逻辑；
- 失败（无法导出/无能力）必须非 0 退出 + stderr 说明，或返回 `UNSUPPORTED`（机器可解析行）。

### 6.2 失败快照目录契约（可选）

```text
<evidence_dir>/failures/fail_<node>_<yyyymmdd-HHMMSS>_<seq>/
  frame.png            # 失败瞬间完整客户区帧
  keys.jsonl           # 最近 30 帧按键（ts/key/hold_ms/gap_ms）
  state.json           # 失败瞬间 state 导出
  manifest.json        # 节点/断言/失败原因/路径清单
```

### 6.3 引擎实现指引（摘）

- **Godot**：`state` 从 world/scene 单例读（只读）；`keys` 用 InputEvent；`test_fast` 用 `Engine.time_scale`（仅在 `--test-fast` 启动参数下启用）；失败快照拼接同上；
- **Web/Electron**：`state` 通过 debug bridge/只读接口导出；`keys` 用 CDP Input.dispatchKeyEvent；`test_fast` 由应用自身时间源实现；
- **Unity**：`state` 从只读单例/序列化快照导出；`keys` 用 Input System 注入；`test_fast` 用 `Time.timeScale`（仅测试构建）；
- **桌面通用**：`state` 无法导出时显式 `UNSUPPORTED`，walker 降级 OCR（标注局限）。

> 说明：task-67 提到 `references/backends/CONTRACT.md`；本插件当前唯一契约路径为 `scripts/backends/CONTRACT.md`（plugin.json references 亦引用此路径），故本节加在此处；若后续迁移到 `references/backends/` 以 dev 回执为准。
