# R163 战斗宽限改墙钟 + 宽限内拒绝任意遭遇战（r162 日志事实修复）

## r162 日志定位到的事实
1) 旧守卫用**帧数**：测试机 143fps 下 600 帧≈4.2s，而两场战斗本身约 4s，`age` 很快 601/602 帧过期；
2) 相邻遭遇 **team 交替**（33/evt1385 ↔ 106/evt1386），旧“同 team/同来源”判定放行另一队；
3) evt1385 离开后仍被重新触发：清场没有保持（其他 event/auto 重新 arm）。

## 修复（R163-BATTLEGUARD-3）
1) **墙钟毫秒**：`_battle_guard_until_ms = Time.get_ticks_msec()` 计时；
   - flee 后 **10s**（`BATTLE_GUARD_FLEE_MS=10000`）；
   - win 后 **5s**（`BATTLE_GUARD_WIN_MS=5000`）。
2) **宽限内拒绝任何“遭遇战”**：不再要求同 team/同来源；
   - 来源事件是 encounter（触发 0x0007 或 auto 0x004C）→ 拒绝（任意 team）；
   - 来源未知且 `flee_disabled=false` → 视为遭遇 → 拒绝；
   - `flee_disabled=true`（Boss/剧情不可逃）或来源不是 encounter → 放行（剧情战豁免）。
3) **清场保持**：flee/win 结束与每次 blocked 时，把当前场景所有 encounter 事件
   `state=0、vanish=max(600,...)、auto=0`，防止相邻队/auto 重新 arm。
4) 日志保留并改 ms：
   `[battleguard] blocked ... age_ms=... team=... src_evt=... stack=...`；
   `battleguard cleared N encounter events in scene 71`。
5) touch/auto 跳过条件改为 `Time.get_ticks_msec() < _battle_guard_until_ms`，不再用帧。

## headless 实测（槽1只读，真实 sleep）
- scene71 evt1385/team33 flee 后：
  - `guard_until_ms = last_frame_ms + 10000`；
  - **真实 sleep 2.4s**：`request_battle(33)` 与 `request_battle(106)` 均返回 **false**，
    `guard_check BLOCKED`、`[battleguard] blocked ... age_ms=2426/2427`、`cleared 5 encounter events`；
  - 继续 sleep 至 **11.4s**：`guard_check blocked=false age_ms=11438`（宽限到期，可再战）。
  - 全程 battles=0。
- boot exit0；槽1未写；未开窗。

## tester4 复测（A-1/A-2）
1. A-1：固定遭遇点 flee；原地/走 20 步，确认 10s 内任何队（33/106 等）都不开战；
2. A-2：走 100 步统计场数（可 flee），应明显下降；
3. 若仍有战斗，抓 `[battle-entry] guard_check ... age_ms=` 与 `[battleguard] blocked` 日志。
- B4 已 PASS 不重测；固定怪 HP1800 不改。
