# R111 已拿糯米后 HUD 不更新修复（scene53 分支遗漏）

## 现场（只读用户槽1 12:44:57 档）
- 位置 **scene53 (464,1248)**；背包已有 **糯米 item76 ×2**；vars：a24_stage=1、a25_stage=1、
  **a26_clue=1**、a26_item=1，a26_stage 未设。
- 旧 HUD：「目标 白河村：回村找糯米（第3章）｜↓·剩7格」，指向 scene53 回程门 evt885，玩家以为还要回村。

## 根因
- `_c3_scene_step(53)` 只有 `a26_stage`、`a25_stage` 两个分支，**没有判断 a26_clue/糯米已取得**；
  用户已拿糯米（a26_clue=1）仍在 scene53 → 落入 `a25_stage>=1` 分支 →「回村找糯米」→ evt885（回白河村）。
- 其余分支（scene50/54）虽用 a26_clue，但没有“背包已有 item76”的兜底；若其它真实发放路径只给物品不写标记，会同样卡住。

## 修复（world.gd）
1) 新增 `_c3_has_rice()`：`a26_clue>=1` 或 `a26_item>=1` 或 **背包 item76>0**（真实物品）。
2) `_c3_scene_step(50)`：用 `_c3_has_rice()` 判断回韩医仙家交药引。
3) `_c3_scene_step(53)`：a26_stage>=1 → 回村出村；**`_c3_has_rice()` → evt886「韩医仙家：进门交药引」**；
   否则 a25>=1 → 回村找糯米；否则进韩医仙家求医。
4) `_c3_scene_step(54)`：带糯米进入 → 「韩医仙家：交药引（自动对白，按空格翻页）」。
5) `_update_a26`：若背包已有 item76 但 a26_clue 未写（其它真实发放路径）→ 补写 a26_clue/a26_item，保证后续判定一致。

## 验证（headless，槽1 只读）
- 载入 scene53 (464,1248)（a26_clue=1, item76=2）：
  HUD 由「回村找糯米 ↓」变为 **「目标 韩医仙家：进门交药引（第3章）｜↑ 剩79格」**，目标 evt886。
- 真实按键逐步走 79 步 N79→0 到 (880,824)，SPACE → scene54 韩医仙家。
- scene54 带糯米（a26_clue/item76）：`_update_a26` 自动交药引 → **a26_stage=1**，
  HUD 变 **「目标 韩医仙家：回白河村（出村前往将军冢）｜↓ 剩2格」**，目标 evt904。
- 后续：evt904 → scene53，HUD 指 evt885 回白河村；白河村 HUD 指 evt802 出村将军冢。
- boot exit0；槽1/2 未写。

## 路线文件
`_playtest_regress_dev/round82/keys_r111_18_scene53_rice_evt886.txt`
- 起点 scene53 (464,1248)（用户当前档）→ evt886 (864,816) ring48；**79 步，N 79→0**；逐行坐标+N；末行 SPACE。
- SHA256 `1520E22770116836E54024A922AFCCC297AA3EE89BD6AE1334B2A047DF06ED6D`。
