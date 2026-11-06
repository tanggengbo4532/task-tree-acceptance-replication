# 仙剑奇侠传 98 柔情版 —— Godot 4.7 完整移植（REA 逆向工程）

本工程是对《仙剑奇侠传 98 柔情版（电脑版/WIN95）》发行版文件的**逆向重建**（REA =
Reverse Engineer Anything）：原始 `Pal.exe` / `Pal.dll` / `PALOLD.DLL` 与 `*.mkf` 数据文件
经 REA 工具链（Ghidra 12.1.4 + 字节级格式解析）取证，再据证据用 GDScript 重写引擎；
游戏逻辑以 sdlpal（GPL-3.0）为移植参照并在 `docs/port/PORT_SPEC.md` 中标注依据。

原始游戏数据不包含在本工程内：运行期从本机安装目录读取 `*.mkf` / `M.msg` / `Word.dat`。

## 运行

1. Godot **4.7.x**（本机 `E:\Godot_v4.7.2-stable_mono_win64\`）。
2. 数据目录（`pal/pal_config.gd` 依次探测，第一个含 `Sss.mkf` 的生效）：
   - `<LOCAL_PATH>`
   - `<LOCAL_PATH>`
   - `res://data/game/`
3. 启动：编辑器打开 `project.godot` 运行；或
   `Godot_v4.7.2-stable_mono_win64_console.exe --path <本目录>`
4. 操作：`↑↓←→/WASD` 移动，`空格/回车` 对话/确认/调查，`Esc` 系统菜单。

### 调试/验收参数

| 参数 | 用途 |
|---|---|
| `--auto` | 无人值守演示：自动推进对白、BFS 寻路到最近触发物、自动战斗/关闭商店、截图到 `_rea_runtime/out/shots/` |
| `--quit-after=N` | N 帧后退出（配合 `--auto` 做回归） |
| `--debug-hud` | 显示场景/坐标/HP 调试 HUD |
| `--scene=N` `--party=0,1,2` `--pos=x,y` `--night` `--wave=N` | 直接进入指定场景/队伍/坐标/夜色/波动的验收入口 |
| `--script-entry=N` | 场景加载后直接执行指定脚本入口（用于 0x0007/0x000A 等验收） |
| `--battle-test=<team>` `--battle-test-mode=win\|flee\|ui\|demo` | 战斗单测 |
| `--menu-test=<kind|auto|roundtrip>` | 菜单/存读档单测 |
| `--text-test` `--audio-test` `--rng-test` `--ending-test` | 文本/音频/RNG/结局单测 |
| `--no-collision` | 测试用：无视障碍（也可游戏内 **F6** 切换，左上会显示状态条） |
| **F7**（游戏内） | 测试用：跳过战斗（验证剧情时用） |

黑盒试玩（真实窗口键鼠）：`_rea_runtime/playtest/PlaytestKit.ps1` +
`round1.json`（含置顶截屏扩展），启动命令：
`PlaytestKit.ps1 -Action launch -Config _rea_runtime/playtest/round1.json`。

一键自检：

```
Godot_..._console.exe --headless --path . --script res://tools/port_check.gd      # 数据/状态/存档
Godot_..._console.exe --headless --path . --script res://tools/scene_sweep.gd    # 全地图/全场景
```

## 已移植模块

| 模块 | 文件 | 说明 |
|---|---|---|
| MKF/YJ2/调色板 | `pal/mkf.gd` `pal/pal_sprite.gd` | 容器 + WIN95 自适应 Huffman 解压；与独立 Python 实现对拍一致 |
| 地图/图块 | `pal/pal_map.gd` | 64×128×2 双层预渲染、遮挡图块、阻挡/高度 |
| 精灵/RLE | `pal/pal_sprite.gd` | MGO/GOP/BALL/RGM/ABC/FIRE sprite |
| SSS/对白/词条 | `pal/pal_data.gd` `pal/pal_tables.gd` `pal/text_db.gd` | 事件/场景/脚本/消息/词条；控制码与分页按 text.c |
| 全局状态/存档 | `pal/pal_state.gd` | 对齐 sdlpal GLOBALVARS；SAVEDGAME_WIN 兼容存读档 |
| 事件脚本 VM | `pal/script_vm.gd` `pal/npc_move.gd` | 全量 opcode 覆盖、NPC 寻路/自动脚本 |
| 场景/探索/渲染 | `game/world.gd` | 移动/碰撞/相机/Y 排序/触发/昼夜/波动/震动/淡入淡出/BFS 自动导航 |
| 战斗 | `pal/battle_data.gd` `game/battle.gd` `game/battle_ui.gd` | 回合制、行动队列、伤害/升级/偷窃/逃跑、FBP/ABC/F/特效/UI |
| 菜单/存档 UI | `game/menu.gd` 等 8 文件 | 主/系统/物品/仙术/装备/状态/商店/5 槽存读档 |
| 对话框 | `game/dialog_box.gd` | 打字机/分页/颜色/头像/选项/上中下窗 |
| 音频 | `pal/pal_audio.gd` + `tools/audio_midi_render.py` | Sounds.mkf 音效全量；BGM 离线 MIDI→WAV |
| RNG/结局 | `pal/rng_player.gd` `game/ending.gd` | 12 块 1464 帧命令流动画；ending.c WIN95 顺序 |
| 标题 | `game/title.gd` | FBP 3 + MGO 0x47 标题字，新的故事/旧的回忆/结束 |

## 证据与文档

- `docs/rea/INDEX.md`：REA 证据索引（目标 SHA-256、evidence_id、结论/未知）
- `docs/rea/PORT_SPEC.md`：逐子系统移植规格（证据 → 实现）
- `docs/port/INTERFACES.md`：模块接口契约
- `docs/port/STATUS.md`：进度板与已知偏差
- `docs/rea/screenshots/`、`docs/port/screenshots/`：实机验收截图
- `tools/*.py`：REA 侧参考解码器（mkf/sss/map/mgo/misc/validate）

## 已知偏差 / 未实现（[unk]）

1. `Pal.exe` 是 VB4 **p-code** 主程序，未解码；操作码语义来自 sdlpal 交叉参照 + 目标脚本实跑验证。
2. 行走为平滑 2/1px 步进（原版 16/8px 离散），速度/轨迹等价。
3. **BGM**：`MUS.MKF`（0x55AA 头）未解；利用音乐号 ↔ `Musics/NNN.mid` 对应关系离线渲染 WAV，
   仓库只含 3 首示例（`data/bgm/001..003.wav`），全量用 `python tools/audio_midi_render.py --all`（约 186MB）。
4. **AVI 过场**（1-6.AVI）无解码器，跳过。
5. 结局的抖动/水波用 alpha 近似；`iCurPlayingRNG` 暂用 0。
6. 字体用 SystemFont（原版 F.MKF 位图字体未移植）；战斗 UI 为文字菜单+精灵（非原版图标）。
7. 部分战斗/结局特效为近似实现（敌人死亡白闪、RNG 未接入战斗特效）。
8. 存档写 `user://pal_save_<slot>.sav`（格式按 SAVEDGAME_WIN，非游戏目录）。
9. 本作 168/171 号地图块为空槽；搜索触发/场景入口以 sdlpal 语义为准。

## 许可

本移植参照 [sdlpal](https://github.com/sdlpal/sdlpal)（GPL-3.0）的格式与算法知识，按 **GPL-3.0**
分发；不含原始美术/音频/文本资源文件（`data/msg_zh.json`、`data/word_zh.json` 为从用户自备
正版数据生成的 UTF-8 文本索引，可用 `tools/extract_msg.py`、`tools/extract_word.py` 重新生成）。
