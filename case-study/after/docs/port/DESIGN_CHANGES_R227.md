# R227 锁妖塔 A39/A40 接线 + scene153/154 编号说明

## scene153/154 编号说明（tester quit_trace scene=153）
- A38 入口目标仍是 **scene154 (map74)**；
- scene154 onEnter 脚本 **24148** 剧情结束后 `0x59 153` → 实际落到 **scene153**（同一 map74，塔内）；
- 所以 tester 看到 scene=153 是**原版脚本正常结果**，不是锚点/映射错误；scene154 是“塔入口”，scene153 是“塔内”。

## R227 接线（A39/A40）
1) **scene153（a38_stage>=1）**：
   - 提示「按空格深入锁妖塔（救灵儿/月如）」；
   - SPACE → `a39_stage=1`、`loaded_from_save=false`、真实 `load_scene(155)`，
     并调用真实 **A39 脚本23694（evt2496）** 播塔内剧情；
2) **scene155（a39_stage>=1，a40_stage<1）**：
   - A39 剧情对话结束后提示「按空格上塔顶（月如/塔倒）」；
   - SPACE → `a40_stage=1`、真实 `load_scene(156)`，由 **scene156 onEnter 22445（A40 塔顶脚本）** 播月如/塔倒剧情；
3) HUD 与触发同源；不伪造路/场景，全部走原版脚本/onEnter。

## headless（团队槽2 + 状态）
- scene153：prompt「按空格深入锁妖塔」→ SPACE → **scene155**，a39=1，**dlg=true（A39 剧情23694 已启动）**；
- 剧情关闭后 scene155：prompt「按空格上塔顶」→ SPACE → **scene156 (1024,1600)**，a40=1，**dlg=true（onEnter 22445 已启动）**；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene153_tower_anchor`：scene153 (1680,408)，a38_stage=1；
- `round78/slot4_scene155_inside_anchor`：scene155 (1680,408)，a39_stage=1；
- `round78/slot4_scene156_top_anchor`：scene156 (1024,1600)，a40_stage=1。

## 说明
- A38「按空格前往锁妖塔」提示不会单独停留：scene154 onEnter 剧情立即接 153，HUD 由右上地点文案/场景剧情承担；如需过渡提示可后续加 `_show_a38_goal` 停留，但当前不阻断。
- 下一步：A40 塔顶剧情后的 A41 离开蜀山→苗疆（scene145/150/151/152 链）接线。
