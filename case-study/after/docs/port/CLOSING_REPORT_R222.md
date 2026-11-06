# R222 收尾报告：A34 完成 / 当前 HEAD / 各节点 sanity / 下一章需新数据

## 当前版本
- 代码 HEAD：**`ab926b7950292ddff0e14c1937b8899b366b2470`**（R221 文档提交；实际代码行为 = R220 `b7f7505` R220-TAISHOU2-1）；
- boot exit0（`--headless --quit-after 3` 无 SCRIPT ERROR）。

## A34 完成说明（从数据挖出的真实链）
1. scene83 红衣路人 clue1（脚本15149，真实对白）；
2. scene83 红衣路人处真实 evt1548 门脚本12982 → scene94 夜链；
3. A33 夜链→scene98→女飞贼战→scene85；
4. scene85 evt1579→scene90→evt1650 婢女对白→evt1661→scene91→evt1664→scene93→evt1692 进屋→evt1691 审案脚本14318；
5. 审案后 scene85 evt1594/1599 复命 NPC（脚本15031，真实对白，a34_done=1）；
6. 复命后 scene85 **evt1608/1609 六婆/三姑街坊**（脚本14180/14191，真实对白，a35_talked=1）；
7. 之后 evt1574→scene83 返回街道。
- 原版数据中**没有可触发的太守/新章门**：太守文本4832/4851 无事件脚本引用；evt1592/1593 是衙役；scene100 是居民住宅；scene83 evt1562 脚本13339 只是夜间演出（设置1630/1631、动画/对白4536+），不切场景。
- 结论：**A34 主线完成；A35/下一章需要新的原版数据或用户指示，团队不伪造路/不硬加传送。**

## 各节点 headless sanity（团队槽2 当前 vars，仅验证 HUD 生成/不崩）
| scene | HUD/target | N | 备注 |
|---|---|---|---|
| 83 | evt1546(1744,424) 返回衙门 | 230 | 有方向/N，正常 |
| 85 | evt1574(176,360) 返回街道(A34完成) | 146 | 正常 |
| 87 | evt1630(1296,280) 夜遇女飞贼 | 108 | 正常 |
| 94 | evt1724(768,928) 返回衙门 | 20 | 正常 |
| 98 | evt1780(352,528) | 0 | 当前合成位置(1024,1024)不可达→等待；需真实入口/锚点再判 |

## 锚点/测试材料
- `slot4_scene85_a34done_anchor`（scene85 544,304，HUD evt1608 N46 六婆/三姑）
- `slot4_scene93_room_npc_anchor`（scene93 832,1536，HUD evt1691 N0）
- `slot4_scene94_night_entry_anchor`（scene94 816,904，HUD evt1741 N50）
- `slot4_scene100_taishou_anchor`（scene100 544,464，居民可选，HUD evt1797 N24）
- scene70/map62 用户蓝线图：`map62_team_walkable_*`、`map62_before_after.png`；
- scene81/map77 蓝线图：`map77_newblue_walkable_*`、`map77_purewalk_*`、`map77_gap_top_composite.png`。

## 槽位
- 槽1 用户 `21277806…`（scene85 240,376）**只读**；
- 团队槽2 最后读取 `D4FBDEFF…`（scene83 状态；团队可写，测试前后备份/恢复）；
- 用户槽5 原档已丢失（团队确认无法找回）；后续测试仅用团队槽2，不碰槽3/4/5/9。

## 下一步（需要用户/Lead）
- A35/新章：等新原版数据/用户指示；
- scene98 需真实入口锚点后再做 HUD/可达性；
- 各图白名单（83/87/94/98）可按之前“渲染+逐格表”流程继续，但当前无路/无门的节点不伪造。
