# 完整移植进度板（STATUS）

> 每轮由 Lead 更新。✅ 完成 / 🟡 进行中 / ⬜ 未开始 / ⚠️ 阻塞或未知。
> 参照：sdlpal（`<LOCAL_PATH>`，GPL-3.0）；数据格式见 `docs/rea/`；试玩记录见 `docs/port/PLAYTEST.md`。

## 基础设施

| 项 | 状态 | 说明 |
|---|---|---|
| autoload（PALTables/PALState/PALText/PALAudio） | ✅ | 全部可用 |
| PALTables 数据表 | ✅ | objects=565 / enemies=154 / teams=380 / magics=104 / fields=58 / stores=21 / words=565 |
| PALState 全局状态 + global.c 工具函数 | ✅ | 含 SAVEDGAME_WIN 存档 |
| 存/读档往返（位置/HP/场景/不重播） | ✅ | 黑盒实测：村道 (1120,1024) 存槽5 → F9 → 读回同坐标同 HP |
| 自检 tools/port_check.gd | ✅ | PASS=32 FAIL=0 |
| 全量扫描 tools/scene_sweep.gd | ✅ | 223 地图 / 294 场景，PASS=518 FAIL=0 |
| VM 全场景压测 tools/vm_scene_sweep.gd | ✅ | 295 场景 / 227 入场脚本 / 3681 触发 / 2165 自动；崩溃 0、unknown 0、missing hooks 0 |
| 调试入口 | ✅ | `--auto/--scene/--party/--pos/--script-entry/--battle-test/--menu-test/--vm-sweep/--debug-hud/--sim-space/--selftest-saveload/--log-file` |
| 测试热键 | ✅ | F6 穿墙 / F7 跳过战斗 / F8 换场景门 / F9 村道 / F10 战斗team2 / F11 持久战team7 / F12 商店(给2000文钱) |

## 场景/探索

| 项 | 状态 | 说明 |
|---|---|---|
| 解码层（MKF/YJ2/MAP/MGO/SSS/M.msg/Word） | ✅ | docs/rea |
| 渲染/碰撞/相机/遮挡/跟随者 | ✅ | 碰撞对齐 sdlpal PAL_CheckObstacleWithRange；**移动为 16/8px 离散格点步**（修掉半步卡死/极慢） |
| 触碰/搜索触发（13 检查点） | ✅ | 场景 2→4 门实测 |
| NPC 自动脚本 / 消失 / 离屏恢复 | ✅ | vm.run_auto 每帧 |
| 昼夜/波动/震动/颜色渐变 | ✅ | 0x0053/54、0x0057、0x0035、0x008C |
| 事件脚本 VM | ✅ | 160/160 opcode；全场景压测 0 异常 |
| 对话框（打字机/分页/颜色/头像/中窗） | ✅ | 中窗按 text.c 整句瞬显+1.4s；**修复 advance() 关闭返回值**（此前导致对话后脚本卡死） |
| 场景切换落点保持 | ✅ | `_position_scripted`；场景 4 黑屏根因已修 |
| 战败 Game Over | ✅ | 全队 HP0/战败 → 中窗提示（可按键继续，最多 8s）→ 回标题；黑盒实测 |
| 自动长跑串联 | 🟡 | 已到 1,2,3,4,5,9,10,11,13；靠 F8/超时推进，尚未真实走完整主线 |

## 战斗

| 项 | 状态 | 说明 |
|---|---|---|
| 战斗数据/流程/渲染 | ✅ | port-battle 完成 |
| 战斗菜单/子菜单/提示 | ✅ | 十字布局（↑攻击 ←仙术 →合击 ↓其他）；“其他”列表已上移不压状态行；提示已标注十字 |
| 战斗交互验收 | ✅ | 黑盒：攻击/仙术(伤害70)/防御/物品菜单/逃跑失败提示/胜利结算/战败 GameOver |
| 金钱入账 | ✅ | 胜利后 Esc 金钱面板 0→6 |
| 战斗脚本（26 op） | ✅ | 自带 ScriptVM + 代理；0x0007 全链路实测 |

## 菜单/商店/存档 UI

| 项 | 状态 | 说明 |
|---|---|---|
| 主菜单/状态/仙术/物品(装备/使用)/系统 | ✅ | Esc 打开；黑盒逐页验证 |
| 商店买/卖 | ✅ | 黑盒：ENTER 买（2000→1800，现有1）、TAB 卖（1800→1900，售价=半价） |
| 存读档 5 槽 | ✅ | 单进程/跨进程 roundtrip PASS；黑盒实测位置恢复 |
| 商店底部键位提示 | 🟡 | 已移到顶部（待下轮复核） |
| P1 UI：仙术/装备/商店页背景平铺压字、HUD 压菜单 | ⬜ | 待修 |

## 音频/动画/结局

| 项 | 状态 | 说明 |
|---|---|---|
| 音效 Sounds.mkf 505 块 | ✅ | --audio-test 0 失败 |
| BGM | 🟡 | MUS.MKF(0x55AA) 未解 [unk]；离线 MIDI→WAV 3 首示例 |
| RNG 动画 | ✅ | 12 块 1464 帧；--rng-test 16/16 |
| 结局 | ✅ | ending.c WIN95 顺序；--ending-test 可跑 |
| AVI 过场 | ⚠️ | 无解码器，跳过 |

## 本轮（目标 Round 10）主线连续通关 + 结局验收

- **单次自动长跑（新游戏 → 结局）达成**：`--headless --fixed-fps 600 --auto --auto-graph --log-file ... --quit-after 250000`
  - 覆盖 **275/294 场景**（含 scene 282 终局场景、286–294 结局后场景），日志汇总见 `docs/port/evidence/story_final_run_summary.log`；
  - 执行 **40+ 场剧情战斗**（team=3/6/7/58/61/65/93/96/119/122/125/146/183/…/313/315…，auto 模式 force_win）；
  - 到达 scene 282 时自动触发结局事件（`AUTO_ENDING_TRIGGER scene=282 event=4801 script=35464`）：
    终局 BOSS 战 team=313 → 终局对白 msg 12220 → `[auto] ENDING` → `[Ending] 开始结局演出`；
  - 0 SCRIPT ERROR；`POS_STUCK`/`CYCLE_DETECT`/`fallback unvisited` 等看门狗按预期工作。
- 结局独立验证：`--ending-test` 跑完 `[Ending] 开始… → 结束`，生成 `ending_fbp75/77/68/anim150` 截图。
- 回归：编译门禁 0 错误；`port_check` PASS=32 FAIL=0；`vm_sweep` PASS（missing hooks 空、上限 0、不变式 []；
  战斗=100 / 商店=23 / RNG=19 / 切场景=100 样本）。

## 验收证据索引

| 项目 | 证据 |
|---|---|
| 主线连续通关 | `docs/port/evidence/story_final_run_summary.log`（275 场景 + 40+ 战斗 + AUTO_ENDING_TRIGGER + ENDING） |
| 结局动画 | `docs/port/screenshots/37_ending_fbp68.png`、`38_ending_fbp75.png`；`evidence/ending_auto_trigger.log` |
| 终局场景 | `docs/port/screenshots/36_final_scene_dialog.png`、`43_auto_s282_*.png` |
| 各区域场景 | `docs/port/screenshots/29~42_story_scene*.png` |
| 战斗/商店/存读档/GameOver/菜单 | tester 11 轮黑盒报告 + `30~35_*.png` |
| 数据/脚本静态校验 | `docs/port/evidence/vm_sweep.json` |

## 已知偏差（如实记录）

1. Pal.exe 为 VB4 p-code，未解码；操作码语义来自 sdlpal 交叉参照 + 实跑验证。
2. MUS.MKF（0x55AA）未解：BGM 仅离线 MIDI→WAV 示例（data/bgm/001-003.wav），其余曲目运行时静音提示。
3. AVI 过场无解码器，跳过（结局内 AVI 段跳过）。
4. 字体用 SystemFont 替代 F.MKF 位图字体。
5. 结局抖动/水波为 alpha 近似；自动通关使用 force_win/场景图跳转（验收模式专用，正常游戏不受影响）。
6. 存档写 `user://`，SAVEDGAME_WIN 格式。

## 结论

自动化主线从新游戏连续跑到结局并触发结局演出；战斗/菜单/商店/存读档/对话/音频/动画/结局各系统均通过模块级+黑盒验收；
以上偏差均为已记录项。


## 已知偏差 / 未知

1. Pal.exe 为 VB4 p-code，未解码；操作码语义来自 sdlpal 交叉参照 + 实跑验证。
2. 行走 16/8px 离散步 + 冷却（观感 2px/帧），与原版按键步进等价。
3. MUS.MKF 0x55AA 未解；AVI 无解码器；字体 SystemFont。
4. 结局抖动/水波 alpha 近似；`iCurPlayingRNG` 暂用 0。
5. 存档写 `user://`，SAVEDGAME_WIN 格式。
6. 菜单/商店/仙术页背景为整屏平铺卷轴纹理（原版为局部框），P1 待修。
