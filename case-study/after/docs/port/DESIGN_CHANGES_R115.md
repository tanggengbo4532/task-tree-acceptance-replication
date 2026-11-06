# R115 将军冢链 scene55/57/59 路线 + scene59「查看将军墓」交互修复

## 1) 新增路线文件（headless 真实按键逐步校验）
- `round82/keys_r115_25_scene55_evt927.txt`
  - scene55 白河村外 **(864,1696) → evt927 (352,512)**（mode6 SPACE，脚本9696 → scene57 落点 (1472,1824)）
  - **242 步，N 242→0**，终点 (304,504) ring80；SHA256 `D53DD87B…C6C33`。
  - 说明：校验时为量纯路径**临时屏蔽了 scene55 怪物事件928-931**；正式游戏会遇敌，战斗/逃跑后位置不变，继续按当前坐标文件走。
- `round82/keys_r115_26_scene57_evt938.txt`
  - scene57 **(1472,1824) → evt938 (992,560)**（mode6 SPACE，脚本11229 → scene59 落点 (1376,1392)）
  - **244 步，N 244→0**，终点 (1056,560) ring80；SHA256 `31262C99…A762B`。
- `round82/keys_r115_27_scene59_evt959.txt`
  - scene59 **(1376,1392) → evt959 (656,1000)**（将军墓剧情，mode2，脚本11399，含战斗）
  - **87 步，N 87→5**；终点 (768,1000) 进入 **120px 交互半径**（HUD 剩5格是到事件中心），中央提示「按空格查看将军墓（第3章）」
    → **按 SPACE** 触发脚本11399；SHA256 `70ED7780…31FA11`。

## 2) 修复：scene59「查看将军墓」没有 SPACE 交互
- 根因：evt959 是 **mode2** 事件（需 SPACE 搜索），而 R105 第3章通用扫描只给商店 NPC 提示；A28 剧情脚本从来无人启动
  （`_a28_talk_started` 只在外层 update 判断、无入口置 true）。
- 修复（world.gd）：
  1) `_scan_extra_interact` 新增 scene59 分支：走近 evt959（120px）→ 提示「按空格查看将军墓（第3章）」kind=a28talk；
  2) SPACE 处理：`a28talk` → `_a28_talk_started=true`，真实执行 **A28_TALK_SCRIPT=11399**；
  3) `_update_a28` 完成/超时收尾时写 **a28_stage=1**（HUD 不再重复指该剧情）。
- headless 验证：(768,1000) interact=959 kind=a28talk；SPACE 后 vm entry=**11399**、busy/dialog 正常启动。

## 3) tester 流程
1) scene55 (864,1696) → 按 `keys_r115_25` 242步 → evt927 (304,504) SPACE → scene57 (1472,1824)（途中遇敌先打完/逃跑，回原位继续）；
2) 按 `keys_r115_26` 244步 → evt938 (1056,560) SPACE → scene59 (1376,1392)；
3) 按 `keys_r115_27` 87步 → **(768,1000)** 出现「按空格查看将军墓」→ SPACE 触发将军墓剧情（含战斗）；
4) 剧情结束 a28_stage=1，HUD 继续将军冢深处/赤鬼王方向。
