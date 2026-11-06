# REA 调查索引 —— 仙剑奇侠传 98 柔情版（电脑版）

> REA = Reverse Engineer Anything。本索引记录本次移植所用**证据**、**结论**、**未知项**与
> **验证记录**，是 `新建游戏项目` 中 GDScript 实现的依据总目录。
> 规格化实现细节见 [`PORT_SPEC.md`](PORT_SPEC.md)，验收记录见 [`VERIFICATION.md`](VERIFICATION.md)。

## 0. 执行环境与如实声明

- **Skill**：本会话的 skill 目录里没有安装 `rea` 系列 skill；经检查本机 npm 缓存中有
  `rea-agents@6.5.0`，其自带 skill 为 `reverse-engineer-anything`（v42，207 个工具）。本次调查
  按该 skill 的规范执行：REA CLI（`_rea_runtime/rea.cmd`）以 `--provider ghidra` 调用
  Ghidra 12.1.4 做原生静态分析；数据文件用字节级解析取证；结论一律标注
  `[observation]/[inference]/[unknown]`，不把社区资料当作本二进制实证。
- **未运行目标进程**：所有原生结论来自静态分析；仅有“游戏本身”的运行时观察是**我们自己的
  Godot 移植版**（见 VERIFICATION），不是原始 `Pal.exe`。
- 环境坑（已解决，记录备查）：非 harness 运行时启动的子进程（java）只能写
  `<LOCAL_PATH>`，故 REA/Ghidra 的 TMP/TEMP 与
  `user.home` 重定向到该树下；`JAVA_HOME` 必须在 wrapper 内显式设置。

## 1. 目标身份

| 目标 | 大小 | SHA-256 |
|---|---|---|
| `Pal.exe` | 169472 | `75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450` |
| `Pal.dll` | 434176 | `b0b00d696176b25cc49ec5e0831949f2e673d5328e5efa647491e694b0bd1020` |
| `PALOLD.DLL` | 64512 | `c6a34e511ed1c7bb2ecddfaaba00992d53006db3ed4b5ab3da61943b417227e8` |
| `Sss.mkf` | 575270 | 见 `evidence/assets/assets_validate.json`（全部 MKF 的 sha256/块表） |
| `Map.mkf` / `Mgo.mkf` / `Gop.mkf` / `Pat.mkf` / `M.msg` | … | 同上 |

数据根：`<LOCAL_PATH>`（与 `<LOCAL_PATH>`
副本逐字节同尺寸；`PalConfig` 两个路径都探测）。

## 2. 证据清单

### 2.1 原生（Ghidra 12.1.4，REA provider `ghidra`）

| 文件 | 内容 | evidence_id |
|---|---|---|
| `evidence/native/REA-BIN-PALEXE-analyze.json` | Pal.exe 概览 | `ev_18e96b76…d9f1` |
| `evidence/native/REA-BIN-PALEXE-resources.json` | PE 资源树 | `ev_dcd55e88…fa30` |
| `evidence/native/REA-BIN-PALDLL-analyze.json` | Pal.dll 概览 | `ev_32fe2f02…82c4` |
| `evidence/native/REA-BIN-PALDLL-resources.json` | PE 资源树 | `ev_e4ee3034…9ffc` |
| `evidence/native/REA-BIN-PALOLD-analyze.json` | PALOLD.DLL 概览 | `ev_054e2f7b…d6901` |
| `evidence/native/REA-FN-PALOLD-unpak.json` | `unpak` 函数级 dossier | `ev_357fa8d2…73d9` |
| `evidence/native/REA-NATIVE-SUMMARY.md` | 结论汇总（Q1–Q6，含地址表） | — |
| `evidence/native/REA-FN-*.md` | 逐函数证据（unpak / MKF 容器 / Pal.dll init-patch / lopen / Pal.exe entry） | — |
| `evidence/native/REA-AUX-*.txt` | Ghidra 批量反编译原文（Pal.dll 1594 函数 / PALOLD 196 / Pal.exe 2） | — |

**结论摘要**

1. `[obs]` `Pal.exe` 是 **VB4 p-code 主程序**：导入表只有 `VB40032.DLL` 16 个序号；
   Ghidra 仅识别 3 个 native 过程；`.text` 主体非 x86 函数。字符串含全部 11 个 MKF 名、
   48 个 Pal.dll 导出名（VB `Declare` 元数据）与 DirectDraw/DirectInput 错误串。
2. `[obs]` `PALOLD.DLL` = 原版图形/声音/输入/MKF 运行时（66 导出：`unpak/paksize/DrawString/
   SetMode/rngput/wtime/exmap…`；导入 DDRAW/DSOUND/DINPUT/WINMM/GDI32）。
3. `[obs]` `Pal.dll` = 补丁 2.0.10.3：`LoadLibraryA("PALOLD.DLL")` + 51 项 `GetProcAddress`
   转发表 + `WriteProcessMemory` 钩子；失败串“无法找到原始的 PAL.DLL 文件”。
4. `[inf]` 因此**游戏主循环与事件脚本 VM 在 Pal.exe 的 p-code 内**；两个 DLL 全部函数中
   不存在 opcode 分派（`case 0x59/0x3b/0x3c/0x1f/0xffff` 均为 0）。
5. `[obs]` MKF 容器：`u32@0 = head = 首块偏移 = 4*(n+1)`；块 i = `[B[i],B[i+1])`，
   `B[n]=filesize`；11 个 MKF 全部验证。
6. `[obs]` `unpak`（`PALOLD.DLL+0x2b1c`）为树编码 + 12bit 距离 + `len=code-0xFD` 的 LZ，
   表地址 `DAT_1000c1d4`/`DAT_1000c2d4`/`DAT_1000da68` 已给出；`paksize` = `*p >> 1`。
7. `[unk]` 操作码逐条语义、EVENTOBJECT 构造、`M.msg` 寻址、MKF 类型位分派、伤害公式
   —— 均在 p-code 内，**本轮未取得静态证据**（如实记录，未用社区资料冒充实证）。

### 2.2 数据格式（字节级解析，`tools/*.py` 可复跑）

| 文档 | 结论要点 |
|---|---|
| [`evidence/assets/MKF-FORMAT.md`](evidence/assets/MKF-FORMAT.md) | 容器；压缩块 = 4B 解压长度 + YJ2；13 个 MKF 交叉验证 |
| [`evidence/assets/SSS-FORMAT.md`](evidence/assets/SSS-FORMAT.md) | 5 块：5077 事件对象 / 295 场景 / 565 对象 / 13514 消息偏移 / 43557 脚本 |
| [`evidence/assets/MAP-FORMAT.md`](evidence/assets/MAP-FORMAT.md) | 65536B=64×128×2×4B，位域/阻挡/高度，双层绘制、tile 偏移 |
| [`evidence/assets/MGO-FORMAT.md`](evidence/assets/MGO-FORMAT.md) | sprite 帧表（`帧数=u16@0−1`）+ RLE；玩家 6 角色 sprite 号 |
| [`evidence/assets/MSG-FORMAT.md`](evidence/assets/MSG-FORMAT.md) | GBK、偏移表、`$/~` 控制码；13513 条 |
| [`evidence/assets/MISC-FORMAT.md`](evidence/assets/MISC-FORMAT.md) | FBP/ABC/FIRE/BALL/PAT/RNG/Sounds/Word 解码；未解项 |
| [`evidence/assets/ASSETS-SUMMARY.md`](evidence/assets/ASSETS-SUMMARY.md) | 一页速查（解码函数签名/常量/坑） |

渲染交叉验证产物：`_rea_runtime/out/assets/`（`map_scene1..4.png`、`mgo_player*.png`、
`fbp_bg*.png`、`abc_enemy*.png`、`rng*_frame*.png`、`pat_palettes.png`、
`sss_tables.json`、`assets_validate.json` 含全部 sha256）。

## 3. 结论 → 实现映射

| 结论 | 实现 |
|---|---|
| MKF 容器 | `pal/mkf.gd: MkfFile` |
| YJ2 解压 | `pal/mkf.gd: yj2_decompress`（与 Python 独立实现逐字节一致） |
| PAT 调色板 | `pal/pal_sprite.gd: palette_from_bytes` |
| MAP/GOP 地图 | `pal/pal_map.gd: PalMap` |
| MGO/GOP sprite + RLE | `pal/pal_sprite.gd: decode_sprite / decode_frame` |
| SSS 表 | `pal/pal_data.gd: PalData` |
| M.msg | `tools/extract_msg.py` → `data/msg_zh.json`；`PalData.msg` |
| 场景/事件/触发/渲染 | `game/world.gd` |
| 脚本 VM（`[inf]`） | `pal/script_vm.gd` |
| 标题画面 | `game/title.gd` |

## 4. 未决问题（保持 open）

1. `Pal.exe` VB4 p-code 解码（脚本操作码、EVENTOBJECT、M.msg 寻址、伤害公式的二进制证据）。
2. `MUS.MKF`（0x55AA 头）、`0.rpg`、`Data.mkf` 块 0、`MGO#571`。
3. `paksize` 的 `>>1` 与实测“头部=长度”的差异；`unpak` 静态树与实测 YJ2 的逐位等价性。
4. 搜索触发 13 点表、对话分区/头像、昼夜调色板、NPC 自动脚本/寻路、战斗与菜单。
5. `Pal.dll` 补丁功能（窗口化/录屏/截图/语言切换）未复刻。

## 5. 许可

移植参照 [sdlpal](https://github.com/sdlpal/sdlpal)（GPL-3.0）的格式与算法知识 →
本工程按 **GPL-3.0**；不包含原始游戏资源文件。
