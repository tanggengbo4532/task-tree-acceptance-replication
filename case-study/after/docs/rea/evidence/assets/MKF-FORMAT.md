# MKF 容器与解压格式（仙剑98柔情版 / WIN95 build）

> 证据全部来自本机数据文件的实际字节解析，解析器：`新建游戏项目/tools/mkf.py`；
> 校验报告：`_rea_runtime/out/assets/assets_validate.json`（含全部 sha256）。
> 参考实现 sdlpal（`palcommon.c` / `yj1.c`）仅用作算法假设来源，标注 [inference]。

## 0. 数据环境判定 [observation]

数据目录同时存在 `Pal.exe`(169472) / `Pal.dll`（PAL.Administrator.ini），
且所有"压缩块"首 4 字节 = 解压后长度（见下），全库 **没有任何** `YJ_1` 签名
（对 13 个 MKF 全文件 `b.count(b'YJ_1') == 0`）。因此本数据集是 **WIN95/98 柔情版**，
压缩算法为 **YJ2**（sdlpal 中 `gConfig.fIsWIN95 ? YJ2_Decompress : YJ1_Decompress`）[inference]。
DOS 版的 `YJ_1` 算法在 `mkf.py` 中保留为参考实现（`yj1_decompress`），本数据未使用。

## 1. 文件哈希（完整值见 assets_validate.json）

| 文件 | 字节 | sha256(前16) | 块数 | 头部字节 | 空块 | YJ2 块 | 原样块 |
|---|---|---|---|---|---|---|---|
| Sss.mkf | 575270 | 3acf15a825b674e5 | 5 | 24 | 0 | 0 | 5 |
| Map.mkf | 1614602 | 62739644af65b5e8 | 226 | 908 | 3 | 223 | 0 |
| Mgo.mkf | 1443503 | 0df639e22da1cf76 | 637 | 2552 | 1 | 636 | 0 |
| Fbp.mkf | 1242530 | 29bbc71c10c58a55 | 78 | 316 | 2 | 76 | 0 |
| Rng.mkf | 4085342 | 5d62cad87b330d2e | 12 | 52 | 0 | 0 | 12 |
| Abc.mkf | 932346 | f9685ba8d22e851a | 154 | 620 | 1 | 153 | 0 |
| Ball.mkf | 145070 | b9925833a9d921aa | 252 | 1012 | 1 | 0 | 251 |
| Fire.mkf | 764381 | 5a23940d3daab5bf | 55 | 224 | 0 | 55 | 0 |
| Gop.mkf | 16437766 | 5745d016a8d9c280 | 226 | 908 | 3 | 0 | 223 |
| Pat.mkf | 8488 | b2d6a3db53a3e801 | 9 | 40 | 0 | 0 | 9 |
| Sounds.mkf | 18112888 | 039a5cc64be93716 | 505 | 2024 | 142 | 0 | 363 |
| MUS.MKF | 331284 | 8367c9d34331f67b | 88 | 356 | 2 | 0 | 86 |
| Data.mkf | 63978 | c0bc968e5322b06f | 15 | 64 | 2 | 0 | 13 |

## 2. 容器布局 [observation]

```
偏移 0x00  uint32  head_words
偏移 0x04  uint32  off[0]   (= head_words)
偏移 0x08  uint32  off[1]
 ...
偏移 4*n  uint32  off[n]    (= 文件长度)
总头部     head_words = 4 * (nchunks + 1)
nchunks = (head_words - 4) / 4
chunk i = bytes[ off[i], off[i+1] )    i ∈ [0, nchunks)
```

- `off[0]` 同时是**第 0 块的起始偏移**和**头部长度**，二者数值相同，这是 PAL MKF 的
  自描述技巧（sdlpal `PAL_MKFGetChunkSize` 读 `dword[i]` 与 `dword[i+1]` 作差）[observation]。
- 空块（长度 0）合法（大多数 MKF 的 0 号块为空，作为"无资源"编号）。
- 全 13 个文件均满足：`off[0] = head_words = 4*(n+1)`、`off[nchunks] = 文件长度`、
  `Σ块长 + head_words = 文件长度`（assets_validate.json 的 `offsets_ok / sizes_sum_plus_hdr`）。

### 2.1 Sss.mkf 头部逐字节（答复 Lead 的 count 疑问）

```
18 00 00 00 | b8 7a 02 00 | f0 83 02 00 | d6 a2 02 00 | fe 75 03 00 | 26 c7 08 00
0x18=24     | 0x27ab8      | 0x283f0      | 0x2a2d6      | 0x375fe     | 0x8c726
```
- `0x18=24` 是**头部字节数**（`4*(5+1)=24`），不是块数；块数 = `(24-4)/4 = 5`。
- 块边界（= off 数组）：`[24, 162488, 164848, 172758, 226814, 575270]`。
- 若按"dword0=count=24、后接 25 个偏移"解释，第 6 项是 0、后续偏移不单调，
  无法得到任何语义自洽的块；而下面的实际映射完全自洽：
  - 块0 = `162488-24 = 162464 = 32 * 5077` → 5077 条 EVENTOBJECT ✔
  - 块1 = `2360 = 8 * 295` → 295 条 SCENE ✔
  - 块2 = `7910 = 14 * 565` → 565 条 OBJECT（WIN95 结构 7 WORD）✔
  - 块3 = `54056 = 4 * 13514` → 13514 个消息偏移（最后一项 = 224455 = M.msg 长度）✔
  - 块4 = `348456 = 8 * 43557` → 43557 条 SCRIPTENTRY ✔
  详见 `SSS-FORMAT.md`。

## 3. 压缩与"每块 4 字节头"

**本数据集没有逐块压缩类型字段/位域** [observation]：
- 所有 YJ2 块的起始 4 字节是 `uint32 解压后字节数`，不是 type+size。
  例：Map.mkf 块1 前 4 字节 `00 00 01 00` = 65536 = 64×128×2×4 的图块缓冲；
  Fbp.mkf 块0 前 4 字节 `00 fa 00 00` = 64000 = 320×200。若解释为 type/size 位域则
  必然与解压结果的尺寸校验冲突（YJ2 解出长度必须等于该 dword）。
- 原样块（Sss/Pat/Gop/Ball/Rng/Sounds/MUS/Data）没有任何头，直接是数据。
- 因此"解压类型 0/1/2"在本数据中**不适用**。压缩与否由**文件/用途**决定（见 §1 表），
  这也是 sdlpal 的做法：`Decompress()` 指针按 WIN95 选 YJ2，调用方决定哪些块要解压
  （map.c / res.c / battle.c 解压，PAL_LoadMap 里 GOP 块、SSS 全块、PAT、BALL、RNG 原样读）。
- DOS 版约定（[inference]，未在本数据出现）：`Decompress` = `YJ1_Decompress`，
  数据块自带 `"YJ_1"` 4 字节签名 + 16 字节文件头，不是 0/1/2 类型字节。
  `mkf.py: yj1_decompress()` 为忠实移植，可用于兼容其它版本数据。

### 3.1 YJ2 解压算法（完整步骤，已用 1154 个块验证）

块布局：`uint32 unc_len` + 位流。位流按 **LSB-first** 取位（`bit = (data[pos>>3] >> (pos&7)) & 1`）。

1. 初始化 641 个节点的自适应 Huffman 树：节点 0..0x140 为 321 个叶子
   （符号 0..0xFF 是字面字节；0x100..0x140 是匹配长度符号），0x141..0x280 为内部节点，
   初始权重全 1；根 = 0x280；`node[0x280].parent = 自身`。
   内部节点 k (0x141..0x280) 的左/右孩子 = 2*(k-0x141)、2*(k-0x141)+1。
2. 循环：从根按位下降到叶子，得到符号 `val`。
3. 若 `weight[root] == 0x8000`：对所有满足 `weight[list[i]] & 1` 的 i∈[0,0x140] 调
   `adjust(i)`，再把所有 641 个权重右移 1 位（周期重标定）。
4. 对 `val` 调 `adjust(val)`：按"兄弟性质"把该节点向后移动越过同权重兄弟，
   交换节点记录并更新父/子指针，权重 +1，再沿父链重复。
5. `val <= 0xFF` → 输出该字节。
6. `val > 0xFF` → 匹配：读 8 位 `temp`；`tmp = temp & 0xFF`；
   再读 `data2[tmp & 0xF]` 位追加到 temp 高位；`temp >>= data2[tmp & 0xF]`；
   `pos = (temp & 0x3F) | (data1[tmp] << 6)`（data1/data2 为 `yj1.c` 中 256/16 字节常量表）。
   `pos == 0xFFF` → 流结束；否则从输出缓冲 `dest[-pos-1]` 起**逐字节**复制
   `val - 0xFD` 个字节（允许重叠，等价 LZ77）。
7. 输出长度必须等于 unc_len（本文实现强校验，防止误判原样块）。

验证：Map 223/223、Mgo 636/636、Fbp 76/76、Abc 153/153、Fire 55/55 块全部解压成功且
长度符合语义（65536 / sprite / 64000）；共 1143 个压缩块，见 assets_validate.json。

### 3.2 BITMAPRLE（精灵帧压缩，非 MKF 层）[observation]

用于 MGO/ABC/FIRE/GOP/BALL 的帧位图：
```
可选前缀 02 00 00 00（4 字节，存在则跳过）
uint16 width
uint16 height
流：  T = 下一字节
      if (T & 0x80) and T <= 0x80 + width : 输出 (T-0x80) 个透明像素（索引 0）
      else                                : 复制紧随其后的 T 个字面索引字节
直到输出 width*height 字节
```
说明：字面段可跨行；索引值 = 调色板下标，**0 表示透明**。
例：GOP 图块 452 帧全部为 32×15；MGO 玩家 12 帧/块，尺寸 22×50 等。

### 3.3 PAL sprite 帧表（MGO/ABC/FIRE/GOP/BALL 共用的容器内结构）[observation]

```
uint16 n          # n 同时也是偏移表长度（字）和帧0的字偏移
uint16 offs[n]    # offs[0] == n；帧 k 字节偏移 = offs[k] * 2，k = 0..n-2
帧数据 = BITMAPRLE
哨兵：offs[n-1] == 0（表尾，不是帧）；真实帧数 = n - 1
```
验证：GOP 块 n=453 → 452 帧，全 32×15；MGO 玩家块 n=13 → 12 帧；
Ball 块 n=2 → 1 帧（物品图标单帧，与 sdlpal `PAL_SpriteGetNumFrames` 一致）。

## 4. Godot 侧建议实现（硬常量）

```gdscript
# 1) 容器
head := u32(0); n := (head - 4) / 4; offs := 读 (n+1) 个 u32
chunk(i) = bytes[offs[i], offs[i+1])
# 2) 压缩块判定：按文件策略表（§1）
#    YJ2 文件: Map/Mgo/Fbp/Abc/Fire  -> yj2_decompress(raw)
#    原样文件: Sss/Pat/Gop/Ball/Rng/Sounds/Mus/Data -> raw
# 3) YJ2: unc_len=u32; 自适应 Huffman 641 节点 + LZ 回溯; 常量表 256+16 字节
# 4) RLE: 见 §3.2; 5) sprite: 见 §3.3
```

## 5. 验证产物

| 产物 | 路径 |
|---|---|
| 容器/解压校验 JSON（含全部 sha256、块表、计数校验） | `_rea_runtime/out/assets/assets_validate.json` |
| 解码器（可复跑） | `新建游戏项目/tools/mkf.py` |
| CLI | `python mkf.py <file.mkf> [dumpdir]` 打印块表并解压 YJ2 块 |
| 地图/精灵/消息渲染 | 见 MAP/MGO/MSG-FORMAT.md |

[unknown]：0x55AA 开头的 MUS.MKF 音乐块格式未解码（见 ASSETS-SUMMARY.md）；
`0.rpg` 176432B 未解释（疑似存档/记录数据，仅记录头部字节）。
