# 验证记录（VERIFICATION）

对应实现：`新建游戏项目`（Godot 4.7.2）。本文件只记录**实际执行过**的验证与结果。

## 1. 资源层自检（Godot headless）

命令：

```powershell
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/probe_assets.gd
```

结果（原文摘录）：

```
[probe] Sss.mkf chunks=5 sizes=162464 2360 7910 54056 348456
[probe] Map chunks=226 Gop chunks=226 Mgo chunks=637 Pat chunks=9
[probe] Map chunk1 decompressed = 65536 (expect 65536)
[probe] PalData.load_all = true scenes=295 events=5077 script_words=174228
        msg_offsets=13514 msgs=13513
[probe] msg[0] = $10李～逍～遥，李～逍～遥！~30
[probe] map 20 tiles=16 load_ms=42
[probe] map 12 tiles=323 load_ms=65
[probe] MGO 2 bytes=8676 frames=12 dims=22x50 ×12
[probe] MGO 193 bytes=9786 frames=14 dims=45x31 45x63 …
[probe] total_ms=550
```

判定：SSS 五块长度与 `EVENTOBJECT 32×5077 / SCENE 8×295 / … / SCRIPTENTRY 8×43557`
逐字节吻合；Map 块解压 65536B；`msg_offsets` 末项 224455 = `M.msg` 长度；MGO 2 号精灵 12 帧
（4 方向 × 3 步）符合玩家行走图。

## 2. YJ2 解压一致性验证

- 独立实现 A：`tools/mkf.py`（REA 证据侧，Python，已验证 1143 个压缩块）。
- 独立实现 B：`pal/mkf.gd`（GDScript，移植目标）。
- 交叉验证脚本：`_rea_runtime/debug_yj2.py`（把 B 逐行转写成 Python 后与 A 对拍）。
- 结果：Map.mkf 块 1（13182B 压缩）两种实现输出均 65536B，sha1 均为
  `fda207a8e0232e36ca82ac33299ce5e8d9a93b91`，`match=True`。
- 调试过程中定位并修复的两个实现问题（已写入 PORT_SPEC §11）：
  1. `PackedInt32Array` 是值类型 → 自适应树状态在辅助函数里丢失 → 改用 `Array[int]`；
  2. 建树时内部节点权重需**边建边算**（`w[cur]=w[i]+w[i+1]`），且左右孩子初值应为 0。

## 3. 实机流程验证（Godot 窗口 + 自动演示）

命令：

```powershell
Godot_v4.7.2-stable_mono_win64_console.exe --path . --auto --quit-after 4200
```

自动模式动作：标题截图 → 自动“新的故事” → 每 12 帧推进一次对白 → 记录场景装载/切场景/未知
操作码 → 脚本结束后模拟方向键行走 → 定点截图到 `_rea_runtime/out/shots/`。

日志（筛选后原文）：

```
[auto] LOAD scene=1 map=20 events=[0,0) tiles=16
[auto] CHANGE_SCENE -> 2
[auto] LOAD scene=2 map=12 events=[0,32) tiles=323
[auto] DIALOG msg=0  李～逍～遥，李～逍～遥！
[auto] ...（梦境 5 句）...
[auto] DIALOG msg=1317 李大娘：
[auto] ...（客栈起床整段对白 1300+）...
[auto] UNKNOWN_OP 0x0016 at entry 3627
[auto] UNKNOWN_OP 0x0070 at entry 3663
[auto] UNKNOWN_OP 0x006C at entry 3678
[auto] DIALOG msg=1383 现在被发现就惨了
```

判定：
1. 场景 1（map 20）入场脚本执行：`0x0046` 出生点 → 黑屏梦境对白（与目标数据一致，场景 1
   仅含一张床且相机在图外，原版即“黑屏对白”开场）；随后 `0x0059` 切场景 2；
2. 场景 2（map 12）地图 323 个图块正常渲染（客栈 6 房间、床/桌/柜/盆栽），32 个事件对象装载；
3. 对白按 `0xFFFF` 正确取消息并等待按键；`0x0043`（音乐 31）、`0x0045`、`0x0047`（音效 98）、
   `0x0065`（玩家精灵→2）、`0x0075`（队伍）、`0x0015`（朝向/帧）均命中日志；
4. 脚本结束后控制权交还：方向键行走使坐标 `(1312,288) → (1312,264)`，视口跟随
   `(1152,176) → (1152,152)`，行走帧动画与碰撞生效。

## 4. 截图索引（`docs/rea/screenshots/`）

| 文件 | 内容 |
|---|---|
| [`01_title.png`](screenshots/01_title.png) | 标题画面：FBP 块 3 山水画 + MGO 0x47 “仙剑奇侠传”标题字 + 菜单 |
| [`02_scene1_dream_dialog.png`](screenshots/02_scene1_dream_dialog.png) | 场景 1 梦境对白（黑屏 + 中文对白） |
| [`03_scene2_inn_dialog.png`](screenshots/03_scene2_inn_dialog.png) | 场景 2 余杭客栈 + 李大娘/李逍遥 + 对白 |
| [`04_scene2_walking.png`](screenshots/04_scene2_walking.png) | 脚本结束后自由行走（相机跟随/动画/遮挡） |
| [`05_godot_map12_prerender.png`](screenshots/05_godot_map12_prerender.png) | Godot 侧 map 12 双层预渲染结果（与 Python 独立渲染一致） |
| [`06_godot_mgo_sprite2.png`](screenshots/06_godot_mgo_sprite2.png) | MGO 2 号（李逍遥）12 帧精灵表 |

## 5. 未覆盖 / 未通过

- 战斗、菜单、存档、NPC 自动脚本、昼夜调色板、地图边界之外场景（场景 3+）未做端到端验证。
- 自动演示只模拟方向键（`_auto_walk_dir`），未验证真实键盘事件路径；真实键盘已在窗口手动
  运行中确认标题菜单与空格推进可用。
- 与原始 `Pal.exe` 的运行时行为**未做对比**（未运行目标进程；见 INDEX §0 声明）。

## 6. 复跑清单

```powershell
# 1) 对白提取（会重写 data/msg_zh.json）
python tools/extract_msg.py data/msg_zh.json
# 2) 资源层自检
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/probe_assets.gd
# 3) 实机自动验收（截图输出 _rea_runtime/out/shots/）
Godot_v4.7.2-stable_mono_win64_console.exe --path . --auto --quit-after 4200
# 4) REA 证据侧全量校验
python tools/validate_all.py
```
