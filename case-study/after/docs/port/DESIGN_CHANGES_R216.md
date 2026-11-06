# R216 A34 自动全链测试 + HUD 残留/回环防护

## A34 自动跟随结果（团队槽2 scene85 起，headless 按键模拟）
- scene90：HUD 衙门后院 evt1650 **N28** → 走 28 步 → SPACE；
- scene91：HUD evt1664 **N16** → 走 16 步 → SPACE；
- scene93：HUD 进屋内 evt1692 **N24** → 走 24 步 → SPACE 进屋；
- 随后自动 **scene93→scene82**，落点 (1504,1008)；
- scene82 HUD 出现 **旧 scene93 交互文案残留**「按空格继续查案（屋内）」，target evt1683(928,1328) N80；
- 420 步内未完成 scene82 审案后出口（测试上限）。

## 修复（R216）
1) **加载新场景时清空交互提示残留**：`_interact_id=0`、`_interact_prompt=""`、`_hint_label.text=""`；
   - 解决跨场景「按空格继续查案（屋内）」残留覆盖 HUD。
2) **scene85 回环防护**：A34 审案/后院已走过（`a34_case>=1`）后，scene85 done 不再指 evt1579→scene90，
   改指真实街道门 **evt1574→scene83**「返回街道（A34 后续）」，避免 85↔90 来回。

## 当前状态
- HEAD 上一版 `7ec64dd`（R215）；本批 R216 提交后为新 hash；
- boot exit0；槽1/槽2 未写、未开窗；
- 已知后续：scene82 审案 evt1683 → 出门 evt1666→scene89→scene85 后，A34 主线没有明确下一节点数据；
  scene83 在 A33/A34 完成后仍可能回 evt1546→85；需要按原版后续剧情数据接下一节点，不能伪造。
