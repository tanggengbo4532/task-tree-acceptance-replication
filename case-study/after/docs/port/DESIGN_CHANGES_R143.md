# R143 A33 夜间前置链引导（scene87→85→83→94→98→回87）

## 现场
- 槽2 `1B18095…`：scene87 绝对 (1520,648)，a31/a32_stage=1；中央/右上空白，evt1630 state0（预期）。
- A33 案件 evt1630 需要先做“客栈夜间前置”才能开启。

## 真实链（Sss）
1. scene87 evt1626 (1568,656) 脚本12940 → scene85。
2. scene85 evt1574 (176,360) 脚本12974 → scene83。
3. scene83 evt1548 (768,512) 脚本12982 → scene94（客栈）。
4. scene94 evt1741 (784,856) mode3 脚本 **13733**：`0x49 1786 1` 开启 scene98 夜间事件（并播夜间剧情）。
5. scene94 evt1728 (1248,704) 脚本13107 → scene98 夜间街道。
6. scene98 evt1786 (400,504) 脚本 **13606**：`0x49 1630 2` 等 → 开启 A33 evt1630（夜遇女飞贼）。
7. 回 scene98 evt1780 → scene94；scene94 evt1724 (768,928) 脚本12986 → scene83；
   scene83 evt1546 → scene85；scene85 evt1580 → scene87。
8. scene87 **evt1630 (1296,280)** mode7 脚本 **13834**：夜遇女飞贼 + BATTLE team=29 + 后续；走近触发（mode7 自动触碰）。

## 修复（world.gd R143-A33NIGHT-1）
- c3 引导场景加入 **87/94/98**。
- scene83：evt1630 未开 → evt1548「前往客栈（夜间前置）」；已开 → evt1546「返回衙门」。
- scene85：未开 → evt1574「返回街道（前往客栈）」；已开 → evt1580「返回衙门内堂」。
- scene87：未开 → evt1626「夜间前置（回街道→客栈）」；已开 → **evt1630「夜遇女飞贼（案件）」**。
- scene94：evt1786 未开 → evt1741「客栈夜间剧情（前置）」；已开且 evt1630 已开 → evt1724「返回衙门」；否则 evt1728「前往夜探街道」。
- scene98：evt1630 未开 → evt1786「夜间前置」；已开 → evt1780「返回衙门」。
- **新增 scene94 evt1741 专用 SPACE 交互**（kind=a33night，执行真实脚本13733）。

## headless 验证（槽2 只读）
- scene87 (1520,648)：floor 暂无新文案，但 guide=`目标 第4章：夜间前置（回街道→客栈）｜→剩2格`（target evt1626 (1568,656)，fb=false）。
- 载入 scene94：guide=`目标 第4章：客栈夜间剧情（前置）｜↑剩12格`（target evt1741 (784,856)）。
- boot exit0；槽1 只读；未开窗。

## tester 执行（先按 HUD）
1. scene87：按 HUD → evt1626 (1568,656) → **SPACE** → scene85；
2. scene85：跟 HUD 到 evt1574 (176,360) → SPACE → scene83；
3. scene83：跟 HUD 到 evt1548 (768,512) → SPACE → scene94；
4. scene94：跟 HUD 到 evt1741 (784,856) → **SPACE**（播夜间剧情/开启 scene98）；
5. scene94：跟 HUD 到 evt1728 (1248,704) → SPACE → scene98；
6. scene98：跟 HUD 到 evt1786 (400,504) → 触发（mode5 脚本13606）→ 开启 A33；
7. 按 HUD 返回：scene98 evt1780→94→83→85→87；到 scene87 后目标切 **evt1630 (1296,280)**；
8. 走近 evt1630 → 触发 **夜遇女飞贼（BATTLE team=29）**；准备战斗/可逃。
- 逐行 keyseq 每图一段随后补；HUD 当前已可走。
