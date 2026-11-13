# SSS.MKF 五块结构（事件对象 / 场景 / 对象 / 消息偏移 / 脚本）

> 解析器：`新建游戏项目/tools/sss_parse.py`（输出 `_rea_runtime/out/assets/sss_tables.json`）
> 校验：`_rea_runtime/out/assets/assets_validate.json` 的 `checks.sss`
> 结构语义参考 sdlpal `global.h` / `global.c` [inference]，**尺寸与条数由实际字节直接验证**。

## 1. 容器

文件：`Sss.mkf` 575270 B，sha256 `3acf15a8…b36b774`（全文见 assets_validate.json）。
头部 `0x18=24` → 块数 `(24-4)/4 = 5`，偏移表 `[24, 162488, 164848, 172758, 226814, 575270]`。

| 块 | 字节区间 | 长度 | 结构 | 单元大小 | 条数 | 校验 |
|---|---|---|---|---|---|---|
| 0 | [24, 162488) | 162464 | EVENTOBJECT | 32 B | **5077** | 32×5077 = 162464 ✔ |
| 1 | [162488, 164848) | 2360 | SCENE | 8 B | **295** | 8×295 = 2360 ✔ |
| 2 | [164848, 172758) | 7910 | OBJECT (WIN95) | 14 B | **565** | 14×565 = 7910 ✔ |
| 3 | [172758, 226814) | 54056 | 消息偏移 | 4 B | **13514** | 4×13514 = 54056 ✔ |
| 4 | [226814, 575270) | 348456 | SCRIPTENTRY | 8 B | **43557** | 8×43557 = 348456 ✔ |

所有块均为**原样存储**（无 YJ2 头，`mkf.try_decompress` 全部失败/不适用）。
全部数组已导出：`sss_tables.json`（2.19 MB，含 5077 事件对象、295 场景、565 对象、
13514 消息偏移、43557 脚本条目的完整数值）。

## 2. 块0 EVENTOBJECT（32 B / 条，16 × WORD，全小端）

| 偏移 | 类型 | 字段 | 语义 | 示例（事件对象 #0） |
|---|---|---|---|---|
| 0x00 | int16 | sVanishTime | 消失/隐藏计时 | 0 |
| 0x02 | uint16 | x | 地图像素 X | 512 |
| 0x04 | uint16 | y | 地图像素 Y | 800 |
| 0x06 | int16 | sLayer | 层级 | 0 |
| 0x08 | uint16 | wTriggerScript | 触发脚本入口（SCRIPTENTRY 下标） | 251 |
| 0x0A | uint16 | wAutoScript | 自动脚本入口 | 0 |
| 0x0C | int16 | sState | 0=隐藏 1=普通 2=阻挡 | 1 |
| 0x0E | uint16 | wTriggerMode | 触发方式 0..8（近/中/远、踩踏…） | 5 |
| 0x10 | uint16 | wSpriteNum | MGO 精灵块号（0 = 玩家角色） | 0 |
| 0x12 | uint16 | nSpriteFrames | 每方向帧数（3 = 行走角色，按方向取 12 帧） | 0 |
| 0x14 | uint16 | wDirection | 方向 0南 1西 2北 3东 | 0 |
| 0x16 | uint16 | wCurrentFrameNum | 当前帧 | 0 |
| 0x18 | uint16 | nScriptIdleFrame | 触发脚本 idle 帧计数 | 0 |
| 0x1A | uint16 | wSpritePtrOffset | 运行期字段（初始 0） | 0 |
| 0x1C | uint16 | nSpriteFramesAuto | 自动脚本用总帧数 | 0 |
| 0x1E | uint16 | wScriptIdleFrameCountAuto | 自动脚本 idle 计数 | 0 |

事件对象下标 **1 基**：场景 k 的对象范围 = `rgScene[k].wEventObjectIndex + 1`
到下一个场景的 `wEventObjectIndex`（sdlpal `PAL_LoadScene` 循环）[inference]；
`sss_tables.json.scene_map_sample` 已按此给出 scene→evt_first/evt_count。
场景 1 的 `wEventObjectIndex = 0`，因此其对象从 #1 开始；#0 不归属场景 1 [inference，
依据 sdlpal 的 +1 循环约定与场景2/3 的 evt_idx=0/32 边界]。

## 3. 块1 SCENE（8 B / 条，4 × WORD）

| 偏移 | 类型 | 字段 | 语义 |
|---|---|---|---|
| 0x00 | uint16 | wMapNum | Map.mkf / Gop.mkf 块号 |
| 0x02 | uint16 | wScriptOnEnter | 进入场景执行的脚本入口 |
| 0x04 | uint16 | wScriptOnTeleport | 传送/离开场景的脚本入口 |
| 0x06 | uint16 | wEventObjectIndex | 本场景事件对象起始（对象下标 = +1） |

场景号与 sdlpal 一致：**内部索引 0 基，游戏显示/存档的"场景号" 1 基**
（`PAL_LoadResources`: `i = wNumScene - 1; rgScene[i].wMapNum`）[inference]。

前 10 个场景实测（sss_tables.json `scenes`）：

| 场景(1基) | map | on_enter | on_teleport | evt_idx |
|---|---|---|---|---|
| 1 | 20 | 4 | 0 | 0 |
| 2 | 12 | 3545 | 0 | 0 |
| 3 | 12 | 0 | 0 | 32 |
| 4 | 10 | 0 | 0 | 44 |
| 5 | 1 | 1 | 0 | 76 |
| 6 | 2 | 0 | 0 | 115 |
| 7 | 4 | 20 | 1635 | 148 |
| 8 | 5 | 0 | 2201 | 169 |
| 9 | 11 | 0 | 0 | 174 |
| 10 | 13 | 0 | 0 | 185 |

→ **场景 1 → 地图 20，场景 2 → 地图 12**（渲染验证见 MAP-FORMAT.md）。
295 个场景中有多个场景共用同一地图块（如场景2、3 都用 map 12）。

## 4. 块2 OBJECT（14 B / 条，7 × WORD，WIN95 结构）

7910 / 14 = 565 条，最大对象号 564。WIN95 版为 7 WORD 的 union（sdlpal `global.h OBJECT`）[inference]：
```
WORD w0..w6
 玩家  player : [reserved, reserved, scriptOnFriendDeath, scriptOnDying]
 物品  item   : [bitmap(BALL块号), price, scriptOnUse, scriptOnEquip, scriptOnThrow, scriptDesc, flags]
 法术  magic  : [magicNumber, reserved, scriptOnSuccess, scriptOnUse, scriptDesc, reserved, flags]
 敌人  enemy  : [enemyId(DATA#1/ABC块号), resistSorcery, scriptOnTurnStart, scriptOnBattleEnd, scriptOnReady]
 毒    poison : [poisonLevel, color, playerScript, reserved, enemyScript]
```
DOS 版为 6 WORD（12 B）[inference]，本数据集实测 14 B（7910 能被 14 整除、不能被 12 整除）。
完整数值：`sss_tables.json.objects[*].w`。

## 5. 块3 消息偏移表（4 B / 条，13514 条）

- 13514 个 uint32 偏移，`offs[0]=0`，单调不减，`offs[13513]=224455` = **M.msg 文件长度** ✔
- 消息条数 = 13514 - 1 = **13513**（第 i 条 = `M.msg[offs[i]:offs[i+1]]`）
- 实测前几项：`0, 30, 37, 67, 85, 108, …`；末三项 `224412, 224436, 224455`
- 解析/导出见 `MSG-FORMAT.md` 与 `tools/gen_msg_json.py`。

## 6. 块4 SCRIPTENTRY（8 B / 条）

```
偏移 0x00  uint16 wOperation     操作码（脚本 VM 的 opcode）
偏移 0x02  uint16 rgwOperand[3]  3 个操作数
```
43557 条，`sss_tables.json.script_entries` 为 `[[op,a,b,c], …]`。
实测前 8 条：`[0,0,0,0] [67,49,0,0] [1,0,0,0] [0,0,0,0] [70,32,64,0] [101,0,193,0] [21,0,0,0] [117,1,0,0]`。
`wOperation` 是 opcode **枚举值**（sdlpal `script.c` 中 `switch (pScript->wOperation)` 的 case 常量）[inference]；
操作数含义随 opcode 变化，属于脚本 VM 队友的范畴，本文件只保证 8 B 定长切分与条数。
入口约定：EVENTOBJECT.wTriggerScript / SCENE.wScriptOnEnter 等均为**该数组的下标**；
脚本以 `0x0000`(end) 类操作码结束（样例中有 `op=0` 条目）。

## 7. 验证方式汇总

| 校验项 | 结果 |
|---|---|
| 5 块长度与结构倍数 | 全整除 ✔ |
| 块0 = 32×5077 | ✔ |
| 块1 = 8×295 | ✔ |
| 块2 = 14×565（WIN95） | ✔（12 不整除，排除 DOS 结构） |
| 块3 首项 0 / 末项 = M.msg 长度 / 单调 | ✔ |
| 块4 = 8×43557 | ✔ |
| 场景→地图映射 | 场景1→20、场景2→12（已渲染 PNG，见 MAP-FORMAT.md） |

复跑：`python tools/sss_parse.py`（固定读本机数据目录，输出 JSON 并打印校验）。
