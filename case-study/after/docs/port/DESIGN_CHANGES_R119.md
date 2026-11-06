# R119 队伍编成丢失修复（读档恢复李逍遥+林月如）+ A28 真实战斗数据

## 1) 真实核对
- player role：**0=李逍遥，1=赵灵儿，2=林月如**（PALTables.player_name 实测）。
- 原剧本 0x0075 `script_set_party` 参数 **1-based**：
  - scene36/37/40/43 的 `set_party(1,3,0)` => **[李(0), 林(2)]**；
  - 白河村/将军冢段（scene49..59，A28 前）应为 **李逍遥+林月如 2 人**（赵灵儿在韩医仙家养伤）；
  - A28 剧情脚本11399 战后另有 `set_party(2,0,0)` => [赵灵儿] 的剧情编成（不干预）。
- 只读槽1/2：`nparty=0`、party 5 槽全 role0（李单人），但 roles 表里林月如等级/HP 数据存在
  → 属于**运行期队伍编成丢失**（存档本身如此；正常剧情加入脚本不会被读档重放）。

## 2) 修复（world.gd，R119-PARTY-1）
- 新增 `_repair_story_party_on_load()`，在 **load_scene 检测到本次是读档**（`PALState.loaded_from_save`）时调用；
- 真实条件门禁（不伪造剧情/不改存档格式）：
  - party 当前只有 role0；
  - 存档真实剧情标志 **a24_stage>=1**（已进入白河村章）；
  - **a28_stage<1**（A28 前；A28 后剧情可能合法改队伍，不干预）；
  - role2（林月如）真实 `level>=2 且 hp>0`；
  - 满足则恢复 party=[role0, role2]，`max_party_member_index=1`（其余槽按 PAL 习惯重复末位 role）。
- 不写存档；下次正常存盘即带上 2 人编成。

## 3) 验证（headless，槽1/2 只读）
- 槽2（scene59 锚点）读档+load_scene(59)：
  `[party] restore story party=李逍遥+林月如`，party=[0,2]，`max=1`，状态菜单可显示/切换两人；
- 槽1（scene53）读档+load_scene(53)：同样恢复 [0,2]；
- scene59 (768,1000) 交互仍为 evt959 kind=a28talk；SPACE → vm entry=11399，队伍人数=**2**；
- A28 战前编成正确（非单人）；boot exit0；槽1/2 未写。

## 4) A28 真实战斗数据（确认非自动胜）
脚本11399 按分支执行两波真实战斗（0x0045 换战场 + 0x0007 BATTLE）：
- 第一波 **team28**：红衣喇嘛 HP800 + 智杖和尚 HP1100 + 灰衣喇嘛 HP800（合计 **2700HP**，
  物理抗性 2/3/2，元素抗性 4~5）；
- 第二波 **team35**：智修大师 HP1050（物理抗性等另表）。
- 「剑神」（magic obj363）：cost_mp=64、base_damage=450、elemental=0；李 Lv11 MP215 约 3 发。
- 可打赢性：修复后为 **2 人队（李+林）**，配合防具/药品/合击与目标选择（优先智杖和尚）才有机会；
  **单人理论上打不赢**；不做自动胜、不代打，具体胜负留给用户/tester 实机。
