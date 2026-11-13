# ASSETS-SUMMARY —— 资源层一页速查（Godot 4.7 用）

数据：`<LOCAL_PATH>`
证据+解码器：`新建游戏项目/tools/*.py`；产物：`_rea_runtime/out/assets/`
详细字段表见同目录 `MKF-FORMAT.md` / `SSS-FORMAT.md` / `MAP-FORMAT.md` / `MGO-FORMAT.md` /
`MSG-FORMAT.md` / `MISC-FORMAT.md`。

## 1. 容器（MKF）——所有 .mkf 通用

```gdscript
# head = u32@0;  n = (head-4)/4;  head == 4*(n+1)
# off[0..n] = u32@(4*i);  off[0] == head;  off[n] == filesize
# chunk(i) = data[off[i] .. off[i+1])
static func mkf_open(path) -> {data, n, off}
static func mkf_chunk(m, i) -> PackedByteArray
```
⚠ **不是**"u32 count + count+1 偏移"：`u32@0` 是头部字节数/首块偏移（Sss.mkf=24→5 块）。
本数据集**没有**逐块压缩类型字段；压缩与否按文件/用途（表 §3），YJ2 块前 4B = 解压长度。

## 2. 解码函数签名（建议直接照抄）

```gdscript
static func yj2_decompress(raw: PackedByteArray) -> PackedByteArray
# raw[0..3]=unc_len; 自适应 Huffman(641节点)+LZ; 常量表 256B+16B; 0xFFF 终止
static func rle_bitmap(bm: PackedByteArray) -> Dictionary  # {w,h,idx:PackedByteArray}
static func sprite_frames(sp: PackedByteArray) -> Array    # n=u16; offs[k]*2; 帧数=n-1
static func palette(pat_chunk: PackedByteArray, night:=false) -> PackedColorArray
# 256*RGB, 6bit<<2; day@0, night@768(块长1536时)
static func load_map(map_id:int) -> Dictionary
# {tiles: PackedInt32Array[16384], gop: Array[sprite帧], pal:int}
static func load_sss() -> Dictionary
# {event_objects(5077x32B), scenes(295x8B), objects(565x14B),
#  msg_offsets(13514x4B), script_entries(43557x8B)}
static func load_msg_json() -> Array  # msg_zh.json.messages
```

## 3. 文件策略表（压缩 = YJ2；原样 = raw）

| 文件 | 块数 | 压缩 | 内容 | 解码 |
|---|---|---|---|---|
| Sss.mkf | 5 | raw | 事件/场景/对象/消息偏移/脚本 | sss_parse |
| Map.mkf | 226 | **YJ2** | 每块 65536B 图块数据 | map_render |
| Gop.mkf | 226 | raw | 每块 sprite(32×15 图块, 452 帧) | sprite_frames+rle |
| Mgo.mkf | 637 | **YJ2** | 场景/NPC/玩家精灵 | sprite_frames+rle |
| Fbp.mkf | 78 | **YJ2** | 每块 64000B 320×200 索引图 | 直接 L8 纹理 |
| Abc.mkf | 154 | **YJ2** | 战斗敌人 sprite | sprite_frames+rle |
| Fire.mkf | 55 | **YJ2** | 法术效果 sprite | sprite_frames+rle |
| Ball.mkf | 252 | raw | 物品图标 sprite(单帧) | sprite_frames+rle |
| Pat.mkf | 9 | raw | 调色板 | palette() |
| Rng.mkf | 12 | raw(嵌套MKF) | 战斗动画；帧=YJ2 命令流 | rng_apply_frame |
| Sounds.mkf | 505 | raw | RIFF/WAVE | 直接播放 |
| MUS.MKF | 88 | raw | 非标准音乐 [unknown] | 暂不解码 |
| Data.mkf | 15 | raw | 全局表；#3=PLAYERROLES | 见 MISC |
| M.msg | - | - | GBK 文本 13513 条 | msg_zh.json |
| Word.dat | - | - | 565×10B GBK 词条 | 定长切分 |

## 4. 关键常量

```
MAP: 64 列 x 128 行 x 2 层; 每格 2 个 u32; 全图 2064x2056
     tile_px = (x*32 + h*16, y*16 + h*8);  TILE 32x15; idx0 = 透明
     bottom = (d&0xFF)|((d>>4)&0x100);  top = ((d>>16&0xFF)|((d>>20)&0x100))-1
     block = d & 0x2000;  height = (d>>8)&0xF
     draw: 先整层 bottom 再整层 top
MGO: n=u16; frame k @ offs[k]*2; 帧数=n-1; 玩家精灵 MGO = (2,3,7,525,5,26)
     frame = dir*3 + step;  dir 0南 1西 2北 3东
SSS: 5077 事件对象(32B) / 295 场景(8B) / 565 对象(14B, WIN95) /
     13514 消息偏移(4B, 末项=224455) / 43557 脚本(8B: op+3 operand)
     场景1→map20(床特写) 场景2→map12(客栈6房间) 场景3→map12 …场景5→map1
MSG: 13513 条; 控制码 $NN(延时) ~N(等待结束) @/" 颜色 ( ) 图标
PAT: 6-bit RGB; 块0=day+night
```

## 5. 已知坑 / 未解项

- **地图无宽高字段**：固定 64×128×2 网格，未用区域为 0；一个 map 块可含多个房间
  （map 12 = 6 间客栈），场景只决定出生点/事件对象范围。
- **调色板不在地图块内**：由脚本 set palette 决定；本批渲染统一用 PAT 块0(day)，
  个别 FBP/ABC 图因此偏色（格式已确认，只差 palette 号）。
- 场景 1 = map 20 只有一张床（176×96 内容），不是坏图。
- MGO #571 非 sprite（[unknown]，疑似结尾用特殊图）；`0.rpg` 176432B 未解释；
  `MUS.MKF` 0x55AA 头音乐未解码；`Data.mkf` 块0(378B) 语义未知。
- msg_zh.json 中 7 条含私用区符号（U+E0xx，原 GBK 非法双字节），显示时可留空。
- RNG 帧是**累积 delta**，不能每帧清屏。

## 6. 产物清单（`_rea_runtime/out/assets/`）

```
map_scene1.png (场景1/map20)  map_scene2.png (场景2/map12)  map_scene3/4.png
mgo_player0..5_role*.png (6 玩家 4 方向 x3 帧)  mgo_npc_scene2_21/55/628.png
sss_tables.json (2.2MB 全表)  msg_zh.json (13513 条 UTF-8)  msg_sample.txt
mgo_index.json (636 精灵)  assets_validate.json (全部 sha256/块表/校验)
misc_index.json (Word/Data/Sounds/MUS/0.rpg/Pat)  map_render.json  rng_index.json
fbp_bg0/1.png fbp_montage.png abc_enemy1..3.png fire_effect0/1.png ball_items.png
pat_palettes.png rng0_frame000/032/063.png rng1_last.png
```
复跑：`python tools/{mkf,sss_parse,map_render,mgo_decode,gen_msg_json,misc_decode,validate_all}.py`
