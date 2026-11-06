# R266 scene178 苗疆锚点 + A42 读档续接

## 锚点
- `round78/slot2_scene178_miao_anchor.sav/.json`
  - sav SHA256 **F7174C5B7A809A4477824257C74CD87F6D6461A4DE7C414FE67530442ED0E297**
  - 来源用户最新槽1 14B5CFBD 只读副本；scene178 (1408,704)，李290/290、林339/339，maxidx1
  - a34_done=1/a35=2/a36..a41=1；a42=0
  - HUD「按空格找圣姑（救月如/灵儿）」
- 说明：`slot2_scene178_miao_anchor_README.md`
- 用户槽1未写；槽2恢复用户最新档

## 代码修复 R266-A42RESUME-1
- 读档抑制 scene178 onEnter 后，原版脚本27955 无入口；新增真实 SPACE 续接：
  - scene178 + a41_stage>=1 + a42_stage<1 → interact id2946 / script27955 / prompt「按空格找圣姑」
  - handler：`a42_talk_started=true`、`loaded_from_save=false`、`_start_script(27955,2946)`
- 不传送/不跳场景/不 auto-win；仍走原版27955→0x59 175

## headless（q2041，从 scene178 锚点）
- 178 (1408,704) SPACE → A42 圣姑剧情 → **175 (912,504)** a42=1
- A42长剧情 194→195→196→197→198→199→200→175（原版分段，正常）
- 175 N24 → **177 (1424,712)** N124 → **187 (1808,1160)** N174
- 场景187 HUD target evt3135(224,1376)→188；headless HUD自动路径中途触发真实侧门 **evt3134(1168,1080)→179**
  - side event 为真实地图门；179 evt2948(1728,1728)→187 可返回
  - 非伪造/非卡死；tester 实机可从187绕开 evt3134 触发圈走 evt3135→188→185
- 未改地图/难度；未 auto-win/传送

## 场景序列/N
178(SPACE) →175（A42剧情/长对白）→177 N124 →187 N174 →（headless误触侧门179；可返回）
- 下一目标：187 evt3135→188→185 神木林
