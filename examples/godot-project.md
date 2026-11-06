# Godot 项目可观测性钩子（引擎侧配合清单）

> 本文件描述「被测 Godot 项目」应提供的最小可观测性，使 4-Agent 黑盒/白盒协作可复现。
> 插件本身**不注入**任何代码到游戏；下列钩子由项目开发者（白盒 Agent）实现，测试 Agent 只读使用，
> **不得**用于跳剧情/伪造状态/改档。

## 1. 启动参数（仅开发/自检使用）

| 参数 | 作用 | 谁可以用 |
|---|---|---|
| `--debug-hud` | 输出状态行（场景/坐标/引导/交互/VM 状态）到 stdout，便于白盒定位 | 开发 Agent |
| `--auto` | 自动播放/自动走位（仅回归探针） | 开发 Agent |
| `--headless` | 无窗口运行（探针/自检，不得截图/抢前台） | 开发/测试（自检时） |
| `--quit-after N` | 跑 N 帧退出（normal 冒烟） | 测试（自检） |
| `--debug-keys` | 允许调试快捷键（F6/F8/F10…） | **仅开发 Agent**；黑盒测试禁用（防作弊） |

## 2. 日志与证据

- `user://quit_trace.log`：退出/异常追踪（正常启动也应写，便于核对崩溃/退出路径）。
- `user://*_diag.log`：**必须只在 `--debug-hud`/`--auto` 下写**；正常启动零诊断 IO（性能与用户可见性要求）。
- 关键剧情/战斗/场景切换：打印单行 `[marker] key=value`，供测试按时间轴核对（不要打印 UI 文案作为唯一证据）。

## 3. 探针场景（Godot）

- 提供 `res://tools/<probe>.tscn` + `--mode` 参数：输入脚本走真实 `Input.parse_input_event`，输出 JSON/文本结果。
- 探针**不得**直接改 `PALState`/事件 state/存档；如需模拟，只能设置"输入序列/时间"。
- 推荐模式：`p0ng`（冒烟）、`full`（主链）、`fadecheck`、`normal`（正常启动 0 调试输出）、`a6full`（长链）。
- 性能探针：用 `Time.get_ticks_usec()` 包住被测函数，输出 `[perf] name=... avg_us=...`；避免在真机窗口里跑（抢 CPU）。

## 4. 确定性要求（黑盒复验可重复）

- 固定窗口分辨率/缩放；提供 `--resolution WxH` 或项目设置固定值；避免 DPI 混用。
- 关闭随机装饰（云/粒子）或提供固定 seed；战斗随机数可用固定 seed（仅 debug 探针）。
- 帧率敏感逻辑（每帧步进/等待）应在 debug 下打印帧计数，便于分析"按键吞/长按无位移"类问题。

## 5. 单实例纪律

- 启动前检测已有窗口/进程（`title_pattern` 精确匹配），有残留先 `close`。
- 同一时刻只允许一个被测窗口；编辑器（如 Godot Editor）与游戏 Player 不得同时作为被测目标。
- 用户实机测试期间：**禁止**启动第二个实例、禁止 headless 抢 CPU、禁止改项目文件。

## 6. 与插件的衔接

```powershell
# 1) 启动并截图
powershell -NoProfile -File scripts\windows\PlaytestKit.ps1 -Action launch -Config playtest.json
powershell -NoProfile -File scripts\windows\PlaytestKit.ps1 -Action shot   -Config playtest.json -Value step01

# 2) 轻按/长按/组合键（真实输入）
powershell -NoProfile -File scripts\windows\PlaytestKit.ps1 -Action keys -Config playtest.json -Value DOWN,DOWN,SPACE
powershell -NoProfile -File scripts\windows\PlaytestKit.ps1 -Action hold -Config playtest.json -Value DOWN,800

# 3) 离线分析证据（无需窗口）
python tools\probes\walkprobe.py  --dir evidence\shots --interval-ms 200
python tools\probes\holdprobe.py  --dir evidence\hold  --interval-ms 90
python tools\probes\fps_probe.py  --dir evidence\fps   --interval-ms 90
python tools\evidence\manifest.py add --index evidence\manifest.json --dir evidence\shots --tag round01
```

> 截图/按键/证据规范详见 `scripts/backends/CONTRACT.md`；配置字段详见 `templates/playtest.json`（v2 schema）。
