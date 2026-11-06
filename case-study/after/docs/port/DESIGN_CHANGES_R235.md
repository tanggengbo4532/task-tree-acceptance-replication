# R235 A49 最终战 battle 触发修复（真实事件脚本33673）

## 根因
- scene253 onEnter 33561 会设置事件4442/4441，但移植读档/加载路径下 **evt4441 state 仍为0**，事件4441 mode7 的触发脚本 **33673** 不会自动执行；
- 33673 才是真正 battle 入口：`0x24 65535 33644` → `0x45 38` → **`0x7 battle team=315`** → `0x45 39`；
- 因此之前只到 scene253、事件4441/4442=0、无战斗。

## 修复（R235-A49BATTLE-1）
- scene253 且 `a49_stage>=1 && a50_stage<1 && !in_battle`：
  - 提示 **「按空格决战（拜月教主/水魔兽）」**；
  - SPACE → `_a49_talk_started=true`，调用**真实事件4441触发脚本33673**（不是伪造战斗）；
- 战斗 team315 = object547 enemy150「八头蛇」HP7800/lv40/atk20（原版 Data）。

## headless
- scene253：prompt「按空格决战」；
- SPACE → **in_battle=true，busy=true**（战斗已进入，team315 八头蛇）；
- 不再出现“到 scene253 但无战斗”；
- boot exit0；槽1/槽2 未写、未开窗。

## A50 二段战/结局（下一步）
- 二段战真实脚本 **33570（evt4443 mode6 at 480,448）**，同样 battle team315；
- 结局 scene267 onEnter **34335**；
- 当前先保证 A49 真战斗可进入/可打；A50 需在战斗结束后按真实 evt4443 门再接 33570→267/34335。
