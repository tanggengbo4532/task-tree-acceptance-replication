# R189 scene68 石地面/石阶白名单（map73）

## 现场
- 团队槽2：scene68 (816,1704)，HUD target **evt1343 (1344,1040)**，N=154；
- map73 是**古墓室内石地面/石阶**（含熔岩池/墙）；无草。
- 整图渲染：`_playtest_regress_dev/round78/map73_bottom.png`
- 路线图：`_playtest_regress_dev/round78/map73_route.png`（绿入口/红 evt1343）

## 人工逐格采样（入口→evt1343，154步）
- 路线 bottom tile id 统计：**id1 127格**；id4/6/8/10/13/171 少量（石阶/边缘）；
- 可走集合：**1,4,6,8,10,13,171**；墙/熔岩/void 不在集内。

## 实现（R189-S68STONE-1）
- scene68 进图 prepare：从入口落点 native 建 evt1343 场 → ±48px 走廊；
- 可走 =（地面 id 集 **或** 走廊内）且 native 非墙/熔岩；
- 非法落点 ground rescue 到最近走廊格；
- HUD/N 同源；N=0 evt1343；未改地图 tile（before=after）。

## headless（团队槽2 scene68）
- 载入后 HUD target evt1343 **N=154**，场 has=true；
- 静态沿场走 **154步** 到 (1280,1024)，**N=0、bad=0**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 从 scene77 evt1428 进 scene68，或读团队槽2 scene68；
- HUD 应指 evt1343 N=154；石地面/石阶可走，墙/熔岩不可走；走到 N=0 → 土灵珠剧情 → scene78。
- 下一批 scene78/79。
