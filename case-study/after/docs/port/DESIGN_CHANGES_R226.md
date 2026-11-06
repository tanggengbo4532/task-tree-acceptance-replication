# R226 scene141 剑圣/锁妖塔交互接线（测试员卡点修复）

## 问题
- 测试员 scene141 锚点（a36_stage=1）载入后 HUD 提示「蜀山：按空格拜见剑圣（查锁妖塔线索）」，但 SPACE/走近无任何反应：scene141 没有任何剑圣交互/入口接线。

## 修复（R226-A37A38-1）
1) scene141（a36_stage>=1）新增两段真实交互：
   - `a37_stage<1`：提示 **「按空格拜见剑圣（查锁妖塔线索）」**；
     SPACE → 写 `a37_stage=1`，调用**真实剑圣脚本23623（evt2405）**；
   - `a37_stage>=1 && a38_stage<1`：提示 **「按空格前往锁妖塔（第 5 章 E2）」**；
     SPACE → 写 `a38_stage=1`，`loaded_from_save=false` 后真实 `load_scene(154)`，
     由原版 **scene154 onEnter 脚本24148** 播锁妖塔剧情；
2) 不硬编码假路/假场景：剑圣与锁妖塔均使用原版脚本/onEnter；
3) HUD 右上地点文案已有分支：a37_stage=1 →「蜀山：按空格前往锁妖塔（E2）」；a38_stage=1 →「锁妖塔：按空格进塔…」，与交互同源。

## headless（团队槽2 + scene141 锚点状态）
- scene141：prompt **「按空格拜见剑圣」**；
- SPACE → dlg=true，`a37_stage=1`（真实剑圣对白）；
- 对白关闭后 prompt **「按空格前往锁妖塔（第5章 E2）」**；
- SPACE → **scene154 (1680,408)**，`a38_stage=1`，dlg=true（原版onEnter 24148 剧情开始）；
- boot exit0；槽1/槽2 未写、未开窗。

## 交付
- 锚点：`round78/slot4_scene141_shushan_anchor`（scene141 1344,1328，a35_stage2/a36_stage1/a37/a38 清空）；
- 测试员用团队槽2 备份/恢复方式载入后即可 SPACE 验剑圣→锁妖塔；
- 下一步：scene154 onEnter 24148 剧情内 A39/A40（上塔顶/月如塔倒）接线；
- team42 战斗仍为原版脚本桩（敌方回合 script41533 `0x89 0` 自动结束），无需打赢。
