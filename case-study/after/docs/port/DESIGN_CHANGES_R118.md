# R118 A28 战败读档后「查看将军墓」软锁修复（P1）

## 复现链路（tester4，构建 79cb97a，槽2 16:57 scene59 (768,1000) 战前锚点）
- (768,1000) SPACE → A28 剧情 → **真实战斗**；战败回档后再走近 evt959：提示消失、SPACE 无反应；
  退圈再回/菜单重载进度二仍无效 → 本进程 A28 无法重试（软锁）。

## 根因
- `_scan_extra_interact` 的 scene59 交互门禁含运行期标志 `_a28_talk_started == false`；
- 该标志在 SPACE 触发时置 true，但战败 0x004E 读档 / 菜单读档 **不会复位它**（它不属于存档变量）；
  读档回 scene59 后标志仍 true → 提示消失、SPACE 不产生 a28talk。
- 是否已看过将军墓应只由**存档真实变量 a28_stage** 决定，运行期标志必须在重载/读档时复位。

## 修复（world.gd，R118-A28RETRY-1）
1) scene59 交互门禁改为只看 `a28_stage < 1`（去掉 `_a28_talk_started` 依赖）；
2) 新增 `_reset_a28_runtime()`：`_a28_talk_started=false / _a28_timer=0 / _a28_last_scene=-1 / _a28_fade_frames=0`；
3) **`load_scene(n)` 进入 scene59 时调用复位**（覆盖菜单读档/0x004E 读档/场景重载）；
4) **`request_load_game()`（0x004E 战败读档）开头也调用复位**。
- 不改 A28 战斗：仍是脚本11399 的**真实战斗**，无任何自动胜/跳过。

## 验证（headless，槽2 只读）
- 槽2 场景59 (768,1000)：提示「按空格查看将军墓（第3章）」interact=959 kind=a28talk。
- 模拟残留 `_a28_talk_started=true` → `load_scene(59)`：提示恢复，a28started=false。
- 模拟 `request_load_game()`（current_save_slot=2）：提示恢复；SPACE → vm entry=**11399**、dialog/busy 正常启动（可再次触发）。
- boot exit0；槽1/2 未写。

## A28 真实战斗数据（Data#5/Teams 28，确认非自动胜）
- team28 = **红衣喇嘛（enemy54，HP800）＋智杖和尚（enemy84，HP1100）＋灰衣喇嘛（enemy56，HP800）**；
  合计 HP **2700**；物理抗性 2/3/2，元素抗性 4~5。
- 技能「剑神」（magic obj 363）：cost_mp **64**，base_damage **450**，elemental 0。
- tester4 李逍遥 Lv11 MP215 → **最多 3 发剑神（192MP）**；单发实际伤害=450 + 灵力/随机加成，
  合计输出不足以稳清 2700HP 的三敌，建议带药/先练级/用合击，**不代打、不改自动胜**。
- 此前文档如出现“剧情战斗自动胜”口径，以此真实战斗数据为准（A28 无自动胜）。
