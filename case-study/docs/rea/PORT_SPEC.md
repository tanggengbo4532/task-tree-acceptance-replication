# 移植规格（PORT_SPEC）—— REA 证据 → Godot/GDScript 实现

本文是 `新建游戏项目` 的实现依据。每条规格都给出**证据来源**与**实现位置**；证据等级沿用
REA 约定：`[obs]` 静态观察、`[inf]` 推断、`[unk]` 未知。原始目标（SHA-256）：

| 目标 | SHA-256 | 证据 |
|---|---|---|
| `Pal.exe` | `75d612b9…61c450` | `ev_18e96b76…d9f1`（REA analyze）、`ev_dcd55e88…fa30`（PE resources） |
| `Pal.dll` | `b0b00d69…bd1020` | `ev_32fe2f02…82c4`、`ev_e4ee3034…9ffc` |
| `PALOLD.DLL` | `c6a34e51…27e8` | `ev_054e2f7b…d6901`、`ev_357fa8d2…73d9`（`unpak` 函数级） |

工具链：REA `rea-agents` 6.5.0（skill `reverse-engineer-anything` v42）+ Ghidra 12.1.4
（Windows P0，`--provider ghidra`）+ Python/Pillow 字节级解析。完整证据见
[`evidence/native/`](evidence/native/)、[`evidence/assets/`](evidence/assets/)。

---

## 1. MKF 容器 — `pal/mkf.gd: MkfFile`

**证据**：[`evidence/assets/MKF-FORMAT.md`](evidence/assets/MKF-FORMAT.md)、
[`evidence/native/REA-FN-MKF-container.md`](evidence/native/REA-FN-MKF-container.md)。

```
u32@0          = head（头部字节数，= 首块偏移 = 4*(n+1)）
u32@(4i), i=0..n = 块起点 B[i]（B[0]=head, B[n]=filesize）
块 i 负载       = data[B[i] .. B[i+1])
```
- `[obs]` 11~13 个 MKF 全部满足非递减、末项=文件长度；`Sss.mkf` head=24→5 块
  `B=[24,162488,164848,172758,226814,575270]`，块长 162464/2360/7910/54056/348456。
- 实现：`chunk_count=(head>>2)-1`，`offsets[i]=u32(4i)`。
- **不要**把它当成 “u32 count + count+1 偏移”。

### 1.1 压缩块（YJ2）

- `[obs]` 压缩块前 4B = 解压后字节数（LE，例如 Map 块 65536、FBP 块 64000），随后为
  YJ2 位流。压缩文件：`Map/Mgo/Fbp/Abc/Fire`；原样文件：`Sss/Pat/Gop/Ball/Rng/Sounds/Mus/Data`。
- `[inf]` native 侧 `paksize` 伪代码为 `*p >> 1`，暗示头部含 1 位类型位；但实测头部直接等于
  解压长度（65536>>1≠65536），且 1143 个压缩块按“头部=长度 + YJ2”全部解出且长度校验通过
  （`tools/validate_all.py`）。**实现采用实测语义**；`paksize` 的位移差异记为待解释项。
- YJ2 算法（自适应 Huffman 641 节点 + 12bit 距离 LZ，`0xFFF` 终止）：与独立 Python 实现
  (`tools/mkf.py`) 与 GDScript (`MkfFile.yj2_decompress`) 输出逐字节一致（Map 块 1：65536B，
  sha1 `fda207a8…3b91`）。

## 2. 调色板 — `pal/pal_sprite.gd: palette_from_bytes`

- `[obs]` `Pat.mkf` 块 0 = 1536B（day 768B + night 768B），块 1..8 = 768B；每色 3 字节 6bit VGA。
- 实现：`r,g,b = min(255, v*4)`；索引 0 记为透明（精灵/图块用），标题背景单独把索引 0 当黑。
- `[unk]` 场景内调色板切换（脚本 `0x0053/0x0054`）未接；当前统一 0 号（day）。

## 3. 地图 — `pal/pal_map.gd`

**证据**：[`evidence/assets/MAP-FORMAT.md`](evidence/assets/MAP-FORMAT.md)、`map.c: PAL_LoadMap / PAL_MapBlitToSurface`。

- `[obs]` Map.mkf 每块经 YJ2 解压恒为 **65536B = 64 列 × 128 行 × 2 半格 × 4B**，无宽高字段。
- 每个 `(x,y,h)` 的 DWORD（h=0 下层、h=1 上层共用同一 DWORD 的低/高 16 位）：

| 字段 | 表达式 |
|---|---|
| 下层图块号 | `(d & 0xFF) | ((d >> 4) & 0x100)` |
| 上层图块号 | `(((d >> 16) & 0xFF) | ((d >> 20) & 0x100)) - 1`（-1=空） |
| 下层阻挡 | `(d & 0x2000) != 0` |
| 下层高度 | `(d >> 8) & 0xF`（上层同理 `>>16` 后再取） |

- 图块位图来自 `Gop.mkf` **同号块**，是**原样** sprite 数据（非 YJ2），32×15/32×16 RLE 位图。
- 整图尺寸：`64*32+16 = 2064` × `128*16+8 = 2056`（预渲染图取 2064×2064）。
- 绘制：先整层下层（索引 0 透明→黑底），再整层上层；tile(x,y,h) 像素位置
  `(x*32 + h*16, y*16 + h*8)`（已含 sdlpal 的 −16/−8 基准）。
- 场景↔地图：`地图号 = SCENE[场景-1].wMapNum`（场景 1→20，2→12，3→12，4→10，5→1…）。
- 渲染验证：[`screenshots/05_godot_map12_prerender.png`](screenshots/05_godot_map12_prerender.png)，
  与 Python 独立实现（`tools/map_render.py`）一致。

## 4. 精灵 — `pal/pal_sprite.gd`

**证据**：[`evidence/assets/MGO-FORMAT.md`](evidence/assets/MGO-FORMAT.md)。

- `[obs]` sprite 块 = `u16` 表：表项 i 在字节 `2i`，值为帧数据位置/2；表项 0 = 帧数+1。
  因此 **帧数 = u16@0 − 1**，帧 i 数据位置 = `u16@(2i) * 2`。
- 单帧 = RLE 位图：可选 4B 魔数 `0x00000002`，然后 `u16 w, u16 h`，随后 RLE 流：
  `b = byte`；`b&0x80` 且 `b <= 0x80+w` → 跳过 `b-0x80` 像素；否则复制 `b` 个字面像素。
  调色板索引 0 = 透明。
- 玩家角色 sprite 号：`MGO = (2,3,7,525,5,26)`（角色 0 = 2）；帧号 = `方向*3 + 步`
  （方向 0 南 1 西 2 北 3 东）。MGO 精灵 2 解出 12 帧 22×50（`screenshots/06_godot_mgo_sprite2.png`）。
- `[unk]` `MGO#571` 非普通 sprite。

## 5. SSS 数据表 — `pal/pal_data.gd`

**证据**：[`evidence/assets/SSS-FORMAT.md`](evidence/assets/SSS-FORMAT.md)。

| 块 | 长度 | 结构 | 实现 |
|---|---|---|---|
| 0 | 162464 | `EVENTOBJECT[5077]`，32B/条 = 16×u16 | `events` |
| 1 | 2360 | `SCENE[295]`，8B/条 = 4×u16（map / onEnter / onTeleport / evtIndex） | `scenes` |
| 2 | 7910 | `OBJECT[565]`，14B/条（WIN95） | `objects_raw`（未用） |
| 3 | 54056 | 消息偏移 `u32[13514]`，末项=224455=M.msg 长度 | `msg_offsets` |
| 4 | 348456 | `SCRIPTENTRY[43557]`，8B/条 = op + 3×operand(u16) | `scripts` 扁平化 |

- 场景 n 的事件对象下标区间：`[SCENE[n-1].evtIndex, SCENE[n].evtIndex)`（1-based id = i+1）。
- 事件对象字段（`global.h tagEVENTOBJECT`，与脚本操作数下标一致）：
  `0 sVanishTime / 1 x / 2 y / 3 sLayer / 4 wTriggerScript / 5 wAutoScript / 6 sState /
   7 wTriggerMode / 8 wSpriteNum / 9 nSpriteFrames / 10 wDirection / 11 wCurrentFrameNum /
   12 nScriptIdleFrame / 13 nSpriteFramesAuto`
- `sState`：`0 隐藏 / 1 普通 / 2 阻撞`；`<0` 为离屏缓存态。

## 6. 对白 — `tools/extract_msg.py` → `data/msg_zh.json`、`pal/pal_data.gd`

- `[obs]` `M.msg` 为 GBK 拼接文本，无内嵌分隔符；偏移表在 SSS 块 3（13514 项）。
  消息 i = `M.msg[off[i] .. off[i+1])`，共 13513 条。
- 控制码：`$nn`（色号/延时）、`~n`（等待/延时）、`@` 与 `"`（颜色/图标），显示前剥离
  （`PalData.strip_control_codes`）。
- 生成：`python tools/extract_msg.py data/msg_zh.json`（JSON 数组，UTF-8）。
- `[unk]` 7 条含 GBK 私用区符号，显示为原样字符。

## 7. 场景装载与移动 — `game/world.gd`

- 装载：`SCENE[n]` → `PalMap.load_map(map_mkf, gop_mkf, mapNo, palette)`；
  事件对象复制为运行时可变数组；入场脚本 `wScriptOnEnter`（teleport 用 `wScriptOnTeleport`）。
- 相机/队伍：`viewport = party − partyoffset`，`partyoffset = (160,112)`；
  钳制到 `[0, 2048−320] × [0, 2048−200]`。
- 移动步长：西/东 2px，北/南 1px（`PAL_NPCWalkOneStep` 的方向增量同源）；
  行走帧 4 步循环 → `frame = dir*3 + ((step+1)/2 if step odd else 0)`。
- 碰撞 `[obs]`（`scene.c PAL_CheckObstacleWithRange`）：
  ```
  x=px/32; y=py/16; h=0; xr=px%32; yr=py%16
  if xr+yr*2 >= 16:
      if xr+yr*2 >= 48: x++; y++
      elif 32-xr+yr*2 < 16: x++
      elif 32-xr+yr*2 < 48: h=1
      else: y++
  blocked = map.blocked(x,y,h)
  ```
  另加地图边界 `[blockX, 64−blockX−1] × [blockY, 128−blockY−1]`（`blockX=160/32, blockY=112/16`）；
  事件对象 `sState>=2` 且 `|dx| + |dy|*2 < 16` 也阻挡。
- 触碰触发 `[obs]`：`mode>=4` 且 `|dx| + |dy|*2 < (mode−4)*32 + 16` → 执行 `wTriggerScript`。
- 搜索触发：`mode 1..3`，本实现按距离近似（`16/32/48`），精确 13 点检查表未移植 `[unk]`。

## 8. 渲染管线 — `game/world.gd`

对齐 `scene.c PAL_MakeScene`：

1. 下层整图 crop（`image = game + (16,8)`）`blit_rect` 到 320×200 帧缓冲；
2. 上层整图同区域 `blend_rect`（alpha=0 透明）；
3. 精灵（队伍 + 可见事件对象）+ 可能遮挡精灵的上层图块，按 `pos.y` 升序混合：
   - 队伍：`pos=(party.x − vx − w/2, party.y − vy + 10)`，`iLayer=6`，绘制
     `y = pos.y − h − 6`；
   - 事件对象：`pos.x = obj.x − vx − w/2`，`pos.y = obj.y − vy + layer*8 + 9`，
     `iLayer = layer*8 + 2`，绘制 `y = pos.y − h − iLayer`；
   - 遮挡图块 `[obs]` `PAL_CalcCoverTiles`：以精灵 `sx=abs_x−iLayer/2, sy=abs_y−iLayer`
     扫描 `5` 个候选格 ×2 层，条件 `tile && height>0 && (dy+height)*16 + dh*8 >= sy`，
     加入排序列表（`x = dx*32+dh*16−16−vx`，`y = dy*16+dh*8+7+l+height*8−vy`）。
4. 输出：`ImageTexture.update(320×200 RGBA8)`，Sprite2D `scale=2` + nearest（640×400 视口）。

## 9. 事件脚本虚拟机 — `pal/script_vm.gd`

**证据状态**：解释器在 `Pal.exe` 的 **VB4 p-code** 内（`[obs]` 导入仅 VB40032、Ghidra 只识别 3 个
native 过程；两个 DLL 全部 1594+196 个函数无 opcode 分派）。p-code 未解码 → 操作码语义为
`[inf]`（sdlpal `script.c` 交叉参照），并用目标数据集的实际脚本跑通验证（见 VERIFICATION）。

已实现（`ScriptVM`）：

| 操作码 | 语义 | 依据 |
|---|---|---|
| `0x0000` | 停止（不返回入口） | `[inf]` script.c |
| `0x0001` | 停止，返回下一行作为入口 | `[inf]` |
| `0x0002` | 空闲帧计数未到 → `entry=op0` 并停止；否则继续 | `[inf]` |
| `0x0003` | 无条件跳转 `ip=op0`（受 op1 空闲帧计数） | `[inf]` |
| `0x0004` | 调用子脚本 `op0`（op1 指定事件对象） | `[inf]` |
| `0x0005` | 重绘（可带等待） | `[inf]` |
| `0x0006` | 按百分比随机跳转 `op1` | `[inf]` |
| `0x0008` | 返回下一行作为入口 | `[inf]` |
| `0x0009` | 等待 `op0` 帧 | `[inf]` |
| `0x000A` | 是/否分支（当前自动选“是”） | `[inf]`+`[unk]` UI |
| `0x0015` | 队伍朝向/帧：`dir=op0, frame=op1, idx=op2` | `[inf]` |
| `0x003B/3C/3D/3E` | 对话窗口分区（简化为统一样式） | `[inf]` |
| `0x0043/0x0045/0x004A` | 音乐/战斗音乐/战场（记录日志） | `[inf]` |
| `0x0046` | 出生点：`x=op0*32+op2*16, y=op1*16+op2*8`，`viewport=x−(160,112)` | `[obs]` 实机命中（场景 2 出生点 41,18） |
| `0x0047` | 音效（记录） | `[inf]` |
| `0x0049` | 设事件对象状态（op0!=0 用 op0，否则 last） | `[inf]` |
| `0x0050/0x0051` | 淡出/淡入 | `[inf]` |
| `0x0053/0x0054` | 调色板（未接） | `[unk]` |
| `0x0059` | 切场景 `op0`（`1..295`，同场景忽略），结束脚本由 world 重载 | `[obs]` 实机命中（1→2） |
| `0x0065` | 玩家精灵：`role=op0, sprite=op1`，`op2!=0` 立即刷新 | `[obs]` 实机命中（场景1→193，场景2→2） |
| `0x0073` | 淡入场景（重绘+短等待） | `[inf]` |
| `0x0075` | 设置队伍（op0..2 为 role+1，0=空） | `[obs]` 实机命中 |
| `0x008E` | 恢复画面/清对话 | `[inf]` |
| `0xFFFF` | 显示消息 `op0`，等待按键推进 | `[obs]` 实机命中（13513 条对白） |

未实现（`script_note_unknown` 记录）：`0x0007` 战斗、`0x0010-0x0014/0x0016` NPC 寻路朝向、
`0x0017/0x0018` 属性、`0x001E/0x001F` 金钱/物品、`0x0020+` 仙术/战斗族、`0x0070/0x006C` 等。
实跑开场脚本时出现并已记录的未知操作码：`0x0016`、`0x0070`、`0x006C`。

## 10. 标题画面 — `game/title.gd`

- `[obs+inf]` sdlpal `main.c`：WIN95 开场位图 = `Fbp.mkf` 块 3（+4），标题字 = `Mgo.mkf` 块 `0x47`，
  鹤 = `0x49`，调色板 = `PAL_GetPalette(1)`。
- 实现：FBP 3 解码 320×200 → 叠加 MGO 71 第 0 帧（居中 y=40）→ 菜单三项 + 提示。
- `[unk]` 菜单词条原版来自 `Word.dat`（565×10B GBK），本阶段用等价中文常量。

---

## 11. 与证据的冲突 / 处理记录

| 项 | 冲突 | 处理 |
|---|---|---|
| 压缩块头 | native `paksize=*p>>1` 暗示 `(size<<1)|type` | 实测头部=解压长度（65536/64000），YJ2 解压长度校验通过 → 采用实测，native 推理记为待解释 |
| GOP 是否压缩 | 早期把 GOP 当 YJ2 解压后为空 | 证据表：GOP 原样 → 改 `chunk()`，地图恢复正常 |
| sprite 帧数 | `u16@0` 看似帧数（会多出 1x1 垃圾帧） | 表项 0 = 帧数+1 → `帧数 = u16@0 − 1`，MGO 2 = 12 帧 ✓ |
| PackedInt32Array | GDScript 值类型，辅助函数内修改不回写 | YJ2 树状态改用 `Array[int]`（引用类型） |

## 12. 未决问题（REA unknowns）

1. `Pal.exe` p-code 解码：脚本操作码逐条语义、EVENTOBJECT 构造、`M.msg` 寻址、伤害公式的**二进制**
   证据仍缺（当前为 sdlpal 交叉推断 + 目标脚本实测）。
2. `MUS.MKF`（0x55AA 头）、`0.rpg`、`Data.mkf` 块 0、`MGO#571` 未解释。
3. `paksize` 位域语义、`unpak` 静态树与实测 YJ2 的等价性未做逐位对照（输出已逐字节一致）。
4. 搜索触发 13 点检查表、对话框分区/头像、昼夜调色板、NPC 自动脚本未移植。
5. `Pal.dll` 补丁层（录屏/截图/语言切换/按键设置）未复刻。

## 13. 复现命令

```powershell
# 资源层自检（Godot headless）
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/probe_assets.gd

# 对白提取
python tools/extract_msg.py data/msg_zh.json

# 全资源校验（REA 证据侧）
python tools/validate_all.py

# 实机自动演示（截图到 <LOCAL_PATH>
Godot_v4.7.2-stable_mono_win64_console.exe --path . --auto --quit-after 4200
```
