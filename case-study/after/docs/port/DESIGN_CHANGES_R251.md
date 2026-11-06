# R251 scene85 复命触发优先级修复（S85REPORT-1）

## 用户/tester 反馈（r242）
A34 链到 scene85「回衙门复命 N30→0」前全部 PASS、0 GameOver；但复命触发点 SPACE 被旧 R151-A28EXIT fallback 抢走：
`[c3] R151-A28EXIT-1 SPACE fallback evt=1666 script=13207 scene=82`
→ HUD 切「与居民对话（可选）N4」→ 再切回复命 N4 互循环、无复命对白、卡住
（quit_trace scene=85 pos=(800,496) busy=false vm_entry=13191）。

## 根因
- 复命事件 evt1594/1599 原始坐标在墙内/不可达（HUD 目标点(512,272)障碍）；
- HUD 路径 fallback 到旧 R151 A28EXIT 的 SPACE 直触发：`_a19g_target_evt` 残留 evt1666/脚本13207（scene82 旧章逻辑），把 SPACE 抢到 scene82 流程；
- 复命 hook 用事件原始坐标120范围，玩家实际在可达落点(480,496/800,496) 距离>120，无法触发真实15031。

## 修复（R251-S85REPORT-1）
1. 新增 `S85_REPORT_ANCHOR=(512,496)`（当前 map80 可走集内离复命点最近的可达格）；
2. scene85 HUD 目标 evt1594/1599 时 `_a19g_t` 改指该锚点，N 与路径可达；
3. 复命交互 hook 判定改用锚点距离<160（不再用墙内事件坐标），SPACE → `a34report` → 真实脚本15031；
4. **scene85 内禁用 R151-A28EXIT SPACE fallback**（`int(PALState.scene) != 85`），旧 evt1666/13207 不再抢键；
5. 优先级：a34_done<1 复命 > 可选居民对话；复命完成（a34_done=1）后走 A35。

## headless（用户槽1 CB1A…只读，聚焦复命段）
- scene85 a34_case=1、a34_done未置，落点(480,544)：
  - HUD「回衙门复命」target_evt1594，target_t=(512,496)，N6↑
  - 走6步→N0→**interact=1594，prompt按空格回衙门复命**
  - SPACE → **a34_done=1**，复命对白 active，target_evt切1608
- 全链自动：scene85→91→93→82审案（choice IP15388）→89→85复命→A35→HUD「按空格前往蜀山」；boot exit0，无 SCRIPT ERROR
- 槽1 hash 前后未变 `CB1A22F7…`；槽2未写

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
