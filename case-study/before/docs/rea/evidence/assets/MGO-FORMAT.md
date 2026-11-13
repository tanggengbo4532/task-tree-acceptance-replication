# MGO 精灵格式（场景/NPC/玩家角色）

> 解析/渲染器：`新建游戏项目/tools/mgo_decode.py`
> 索引产物：`_rea_runtime/out/assets/mgo_index.json`（636 个精灵的压缩/解压尺寸、帧数、帧尺寸）
> 校验：`assets_validate.json` 的 `checks.mgo`

## 1. 容器 [observation]

`Mgo.mkf`：1443503 B，sha256 `0df639e2…9f6e789`，**637 块**，头部 2552 B。
- 0 号块为空（"无精灵"编号），其余 **636 块全部为 YJ2 压缩块**，且全部**只含 sprite 结构**。
- 解压后大小：887 .. 59516 B（各精灵不等），见 mgo_index.json。
- 块号即 EventObject.wSpriteNum / PLAYERROLES.rgwSpriteNum 引用的精灵号。

## 2. 解压后结构 = PAL sprite（帧表 + RLE 帧）

```
uint16 n            # 帧数+1；n 同时是偏移表长度（字）和帧 0 的字偏移
uint16 offs[n]      # offs[0] = n；帧 k 起始字节 = offs[k]*2 (k=0..n-2)
帧数据 = BITMAPRLE   # uint16 w, uint16 h, RLE 流（见 MKF-FORMAT.md §3.2）
# 表尾 offs[n-1] == 0 是哨兵，不是帧；真实帧数 = n-1
```

实测：
- MGO #2（玩家1 李逍遥）`n=13` → **12 帧**，每帧 22×50
- MGO #3（赵灵儿）12 帧，26×46；#7（林月如）12 帧，24..29×47；
  #525（巫后）12 帧，29..39×55；#5（阿奴）12 帧，19..29×46；
  #26（盖罗娇）12 帧，19..21×48
- 全部 635 个精灵（共 4132 帧）的 RLE 均可完整解码，帧偏移单调且落在块内 ✔

## 3. 玩家 6 角色 / 帧与方向 [observation + inference]

`Data.mkf` 块 3 = PLAYERROLES（900 B）。其前 3 组各 6 个 WORD：
```
word 0..5  : rgwAvatar          = (1, 11, 21, 73, 27, 44)   # F.MKF 头像/战斗头像号
word 6..11 : rgwSpriteNumInBattle = (0,1,2,3,4,8)           # F.MKF 战斗精灵号
word 12..17: rgwSpriteNum        = (2, 3, 7, 525, 5, 26)    # ← MGO 场景精灵块号
word 18..23: rgwName             = (36,37,38,40,39,41)      # Word.dat 词条下标
```
Word.dat 验证：#36=李逍遥 #37=赵灵儿 #38=林月如 #39=阿奴 #40=巫后 #41=盖罗娇 ✔
（role 3 的名字索引 = 40 → 巫后，对应 MGO 525；role 4 的名字索引 = 39 → 阿奴，对应 MGO 5）。

帧索引 [inference：sdlpal scene.c]：
```
走行帧号 = wDirection * nSpriteFrames + iFrame
nSpriteFrames == 3 时 iFrame 0..2 循环（4 方向 × 3 步 = 12 帧）
方向 wDirection: 0=南(下) 1=西(左) 2=北(上) 3=东(右)   # palcommon.h kDirSouth=0..
```
渲染器按 4 行(方向) × 3 列(步帧) 输出精灵表，已用 read_image 确认：
行 0 = 正面朝下、行 2 = 背面朝上、行 1/3 = 左右侧身，与上述映射一致。

玩家精灵表（3 倍放大，16 色索引经 PAT 块0 调色板）：
```
mgo_player0_role2.png   李逍遥 (MGO 2)   216x624
mgo_player1_role3.png   赵灵儿 (MGO 3)   252x576
mgo_player2_role7.png   林月如 (MGO 7)   279x588
mgo_player3_role525.png 巫后   (MGO 525) 369x684
mgo_player4_role5.png   阿奴   (MGO 5)   279x576
mgo_player5_role26.png  盖罗娇 (MGO 26)  207x600
```

## 4. NPC 精灵

NPC = EVENTOBJECT.wSpriteNum 指向的 MGO 块 + nSpriteFrames 决定方向数：
- `nSpriteFrames == 3` → 4 方向 × 3 帧的行走 NPC（同玩家）
- 其它值 → 该 NPC 的帧数（如单帧/4 帧动作）
场景 2（map 12）事件对象引用到的 NPC 精灵号实测：`55, 21, 628`。
产物：
- `mgo_npc_scene2_21.png`（12 帧，紫衣店小二，4 方向行走，人形清晰可辨）
- `mgo_npc_scene2_628.png`（4 帧，持棍 NPC 的 3 个攻击/动作帧+1，武器与人物可辨）
- `mgo_npc_scene2_55.png`（1 帧，菱形地面/地毯类物件，非人形）
渲染同样用 PAT 块0 调色板；MGO 索引 0 透明。

## 5. 特殊块 [unknown]

MGO #571：YJ2 解压后 59516 B，不符合 sprite 帧表（首 WORD=3，第 2 WORD=0xC222
远超块长）。它不是普通精灵，疑似结尾/过场用的特殊图（sdlpal 结尾代码从 MGO 取
571 作全屏图，但长度与其 64000 预期不符，本数据集该块语义未定）。
其余 635 块无异常。

## 6. Godot 侧常量

```
MGO_HEADER = uint16 n; uint16 offs[n]   # offs[0]==n, 帧 k @ offs[k]*2
MGO_FRAMES = n - 1
RLE: prefix(0x02,0,0,0 可选), u16 w, u16 h, runs:
     T>0x80 && T<=0x80+w -> 跳过 T-0x80 像素(透明)
     else                -> 读 T 个字面调色板索引
player_frame = dir*3 + step   (dir 0=S,1=W,2=N,3=E)
```

复跑：`python tools/mgo_decode.py`（输出 6 张玩家精灵表 + NPC 示例 + mgo_index.json）。
