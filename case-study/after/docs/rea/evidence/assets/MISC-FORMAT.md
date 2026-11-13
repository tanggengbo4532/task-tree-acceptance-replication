# 其它资源格式（FBP / ABC / FIRE / BALL / RNG / PAT / SOUNDS / MUS / WORD / DATA / 0.rpg）

> 解析器：`新建游戏项目/tools/misc_decode.py`
> 索引：`_rea_runtime/out/assets/misc_index.json`、`rng_index.json`、`pat_palettes.png`
> 参考 sdlpal battle.c / ending.c / rngplay.c / global.c [inference]；尺寸/头字节均为实测。

## 1. FBP.MKF —— 战斗背景/全屏图 [observation]

- 容器：1242530 B，78 块（2 空），头部 316 B；**76 个非空块全部 YJ2 压缩**，
  每块解压后**恒为 64000 B = 320×200 8bpp 索引图**（与 sdlpal `PAL_FBPBlitToSurface`
  直拷贝一致）。
- 调色板由脚本/战斗场景另行设置（PAT 块），不在此文件；用 PAT 块0 渲染：
  - 块 0 = 角色状态界面背景（可见"頭戴/披掛/身穿/手持/腳穿/配帶/武術/靈力/防禦/身法/吉運"等
    繁体 UI 文字）
  - 块 1 = 竹简+蛋的标题/剧情图
  - 块 2 = WIN95 主菜单背景（`ui.h: MAINMENU_BACKGROUND_FBPNUM = fIsWIN95 ? 2 : 60`），
    用块0 调色板会偏色/抖动 → 需要正确 palette 才能还原
  - 块 6 起为典型战斗背景（草地/岩地/林间土路，320×200 完整可辨）
- 产物：`fbp_bg0.png`、`fbp_bg1.png`、`fbp_montage.png`（前 12 个非空块 3×4 拼图）。
- Godot：`FBP chunk -> 64000 bytes`；`Image.create_from_data(320,200,false,FORMAT_L8, buf)`。

## 2. ABC.MKF —— 战斗敌人帧 [observation]

- 932346 B，154 块（1 空），头部 620 B；153 块全部 YJ2，解压后均为 **sprite**
  （帧表+RLE，见 MKF-FORMAT.md §3.3），共 **613 帧**，RLE 全部可解。
- 块号 = OBJECT.enemy 的 `wEnemyID` / DATA#1 ENEMY 下标（sdlpal `battle.c` 用
  `wEnemyID` 作 ABC 块号）[inference]。
- 产物：`abc_enemy1.png`/`abc_enemy2.png`/`abc_enemy3.png`（每块 8 帧/行，2×放大）。
  用 PAT 块0 渲染颜色偏暗（战斗敌人使用其它 palette），但轮廓/帧数可辨。

## 3. FIRE.MKF —— 法术效果帧 [observation]

- 764381 B，55 块（无空块），头部 224 B；55 块全部 YJ2 → sprite，共 **837 帧**。
- 块号 = 法术/效果号（sdlpal `fight.c` 的 iEffectNum）[inference]。
- 产物：`fire_effect0.png`、`fire_effect1.png`（8 列雪碧图，2×放大）。

## 4. BALL.MKF —— 物品图标 [observation]

- 145070 B，252 块（1 空），头部 1012 B；**全部原样存储，不压缩**。
- 每块 = sprite；实测 251 个 sprite 均为 **单帧**（`n=2` → 1 帧），RLE 可解；
  块号 = OBJECT.item.wBitmap（sdlpal `itemmenu.c`）[inference]。
- 产物：`ball_items.png`（块1 起 8 列雪碧图，3×放大；蓝珠图标可辨）。

## 5. RNG.MKF —— 战斗动画（嵌套 MKF + 命令流）[observation + inference]

- 4085342 B，**12 块**（无空块），头部 52 B；块**原样存储**，但每块本身又是
  **一个 MKF 容器**：
  ```
  uint32 head_words = 4*(n+1); uint32 off[n+1]   # 嵌套
  帧 i = [off[i], off[i+1]);  实测最后一帧长度为 0 → 有效帧数 = n-1
  每个有效帧 = YJ2 流（前 4B=解压长度），解压后是 0x00~0x13 的命令流
  ```
- 12 个动画的帧数（实测）：`[64, 410, 93, 140, 40, 82, 54, 70, 33, 256, 42, 180]`；
  全部 **1138 帧 YJ2 解码成功**（12/12 块 ok）。
- 命令流语义 [inference: sdlpal rngplay.c `PAL_RNGBlitToSurface`]：
  在 320×200 8bpp 画面上**逐帧累积**绘制（不是每帧清屏）；命令字节：
  `00/13`=结束；`02`=跳过2像素；`03`=跳过(byte+1)*2；`04`=跳过(word+1)*2；
  `06..0A`=写 (cmd-5) 对像素（每对 2 字节）；`0B`=写 (b+1) 对；`0C`=写 (word+1) 对；
  `0D..10`=用同一对像素重复 (cmd-11) 次；`11`=同值重复 (b+1) 对；`12`=(word+1) 对。
  `misc_decode.py: rng_apply_frame()` 为完整 Python 实现。
- 产物：`rng0_frame000.png`/`rng0_frame032.png`/`rng0_frame063.png`、`rng1_last.png`。
  用 read_image 确认：前几帧只有顶部窄条（首个全屏帧之前的 delta），累积到最后一帧
  可见**战斗场景 + 我方/敌方角色 + 法术光效**，画面合理。
- Godot：RNG 播放 = 预解码所有帧命令流 → 维持一个 320×200 索引缓冲逐帧 apply →
  用当前 palette 上传纹理；不需要每帧清屏。

## 6. PAT.MKF —— 调色板 [observation]

- 8488 B，9 块，原样：块0=1536(day+night)，块1-4=768，块5=1536，块6-8=768。
- 每条 256×RGB，值域实测 **0..63（6-bit VGA）** → `<<2` 到 8bit。
- day 在偏移 0，night 在偏移 768（块长 1536 时）。
- 产物：`pat_palettes.png`（9 条色带）。

## 7. Sounds.mkf —— 音效库 [observation]

- 18112888 B，505 块（142 空），头部 2024 B；**全部原样存储**。
- 非空块全部是 **RIFF/WAVE**（363 个，`RIFF` 签名）；块号 = 音效号。
- 索引见 misc_index.json `sounds.sample`（size / RIFF 长度 / 数据字节数）。

## 8. MUS.MKF —— 音乐 [unknown]

- 331284 B，88 块（2 空），头部 356 B；原样存储。
- 每块头：`aa 55 00 00 | 00 00 00 00 | 14 00 00 00 | xx xx 00 00 …`
  （0x55AA 签名 + 若干长度字段），**不是标准 MIDI（无 MThd）、不是 RIFF/RIX 文本签名**。
  sdlpal 用 `RIX_Init("mus.mkf")` 读取 [inference]，但块头与已知 RIX 不符，
  本数据集该音乐编码 **未解码**（留作后续，不影响资源层重写）。

## 9. Word.dat / Data.mkf / 0.rpg

- `Word.dat` 5650 B = **565 × 10 B**，GBK 定长右补空格。索引 = 对象/UI 词条号：
  #2 "Exp"、#3 状态、#4 仙术、#5 物品、#10 文钱、#36 李逍遥、#37 赵灵儿、#38 林月如、
  #40 巫后、#41 盖罗娇 …（完整表在 misc_index.json `word.words`）。
- `Data.mkf` 15 块，全部原样，块大小：
  `[378, 10780, 3800, 900, 3328, 696, 400, 0, 0, 25532, 17478, 40, 282, 100, 200]`。
  已确认：块3 = **PLAYERROLES**（900 B，含 6 角色头像/战斗精灵/MGO精灵/名字索引等，
  见 MGO-FORMAT.md §3）；块12 = 282 B 对话框图标（sdlpal 读 282B 到 bufDialogIcons）[inference]；
  块0 = 378 B 小表（非 UTF-16/非 GBK 文本，语义 [unknown]）。
- `0.rpg` 176432 B，头 64B：`1300a004 b0000000 02000000 00001f00 25000000…`，
  疑似存档/剧情记录二进制，布局 **[unknown]**（未尝试解释）。

## 10. 复跑

```bash
python tools/misc_decode.py   # 重新生成 FBP/ABC/FIRE/BALL/PAT/RNG PNG + misc_index.json
```
