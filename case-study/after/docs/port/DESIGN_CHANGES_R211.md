# R211 scene81 HUD“等待/绕行”修复：guide/移动 walkability 同源

## 根因
- R210 的 scene81 白名单格只覆盖 `_is_obstacle`，但 guide 方向计算与移动碰撞走 `_s4g_walk_ok` / `_walk_target_ok`，
  两处没有使用白名单 → HUD `_a14g_key` 始终为空，显示“等待/绕行中”，而 `_a14g_left` 仍是 324 的残留值；
- 表现为：载入后等待提示覆盖 N/箭头，移动后短暂出现 N 再回等待。

## 修复（R211-S81WALK-1）
1) `_s4g_walk_ok`：scene81 且白名单生效时，直接返回 `_s81_ground_cell_ok(x,y)`；
2) `_walk_target_ok`（移动/`_step_walkable` 共用）：scene81 同样直接返回白名单判定；
3) 这样 HUD BFS、方向计算、实际移动三处同源，不再出现“等待/绕行”假提示。

## headless（用户槽1 4A8CE9CE… scene81 288,416）
- HUD 稳定为：**「目标 第4章：前往扬州街道｜下一步按【↓】键 · 剩 324 格」**，`_a14g_key=down`，N=324；
- 不再出现「等待/绕行中」；guide has=true；
- 静态 324 步→N=0；
- boot exit0；槽1/槽2 未写、未开窗。

## 待确认
- headless 合成按键测试中，scene81 起点按方向键未产生位移（其他场景合成按键正常）；可能是 probe 输入/等待松键状态；
- 请 tester 实机验证：载入后 HUD 应为 ↑↓ 方向 + 324，不应等待；按方向应能走。
