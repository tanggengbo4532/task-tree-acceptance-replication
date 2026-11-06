# R223 修复 scene83↔85 N2 回环 + 第5章蜀山真实入口接通

## 回环根因
- a35_stage>=1（第4章完成）后：
  - c3 scene85 仍指 evt1574→scene83「返回街道」；
  - c3 scene83 `_a33_done_state()` 又指 evt1546→scene85「返回衙门」；
  - 形成 N2↔N2 互跳，HUD 无明确终态。

## 修复（R223-SHUSHAN-1）
1) **scene85**：a35_stage>=1 且 a36_stage<1 → c3 返回 []（不再指 evt1574）；
   显示右上地点文案「扬州街道：按空格前往蜀山（第 5 章）」，并新增 SPACE 交互：
   - 提示「按空格前往蜀山（第 5 章）」；
   - SPACE → `_a36_enter_started=true`，调用**真实蜀山入口脚本 21692（evt2342→scene141）**；
2) **scene83**：a35_stage>=1 → c3 返回 []，不再指 evt1546→scene85；
3) 加载新场景时清空 `_a19g_t/_a14g_left/_a14g_key/_a19g_dist/_hint_label`，防止 c3 返回空时 HUD 残留旧目标形成假回环；
4) `_update_a36` 到达 scene141 后写 `a36_stage=1`（原代码检查但没人写），供右上地点文案「已到蜀山（E1）」。

## headless（团队槽2，a35_stage=1）
- scene85：prompt **「按空格前往蜀山（第 5 章）」**；
- SPACE → **scene141 (1344,1328)**，真实蜀山脚本21692 已执行（busy=true 剧情中）；
- 随后 load scene83：HUD **target=(0,0)、N=0、key 空**，**不再 N2↔N2 回环**；
- boot exit0；槽1/槽2 未写、未开窗。

## 第5章入口说明
- 原版蜀山链：scene139 evt2342(1376,1360) 脚本21692→scene141；
- 中间 scene118/140/139 在当前已通章节数据里没有可达门，故本移植从 scene85（原版 HUD 明示“按空格前往蜀山”）调用**真实21692脚本**进入 scene141；非伪造路/非传送。
- scene141 内 A37（剑圣）/A38后续代码目前仍是占位（无 stage setter），需要下一步接蜀山剧情。

## tester
- 回环档 E8431A55：scene85 应显示「按空格前往蜀山」；SPACE 应切 scene141，不再 83↔85 N2。
- 槽1只读、只团队槽2；锚点沿用 scene85 a34done。
