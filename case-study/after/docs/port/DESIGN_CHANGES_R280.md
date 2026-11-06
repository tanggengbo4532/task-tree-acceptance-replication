# R280 蜀山链 SPACE/换图点审计 + 路线规划图

## 数据审计（原版 event 数据）
- 85 evt1583(1824,384) mode5 脚本15459→106：**原版真实门**（走到门环SPACE）
- 106 evt1966(160,1104) mode5 脚本13219 **原版→85**；代码 `_start_script` 特殊改写 **→scene109**（team新增桥门/空格跳）
- 109 evt1996(1168,1048) mode5 脚本15587→118：原版真实门；代码落点强制 snap(640,1672)（team救援）
- 118 evt2152(576,1664) mode5 脚本21651→140：原版真实门；代码在代理锚点(640,1672) SPACE触发（team近似跳）
- 140 evt2346(528,744) mode5 脚本21655→139：原版真实门
- 139 evt2342(1376,1360) mode6 脚本21692→141：原版真实门

## 结论：必须改的team点
1. scene106 evt1966 改线→109：改回原版→85，或用户画真实106→109路/门
2. scene109→118 落点救援 snap(640,1672)：去掉snap，需用户画真实落点/通路或修地图
3. scene118 出口在代理锚点(640,1672)触发：把真实门 evt2152画进可走集/路径，或用户明确允许门口代理
4. scene106↔109 新桥门整体是team新增，需用户重新确认/画
- scene85/109/140/139的原版真实门，走得到门环后SPACE属原版交互，不算作弊

## 给用户的路线图
- `round78/route_plan_scene85_clean.png`
- `route_plan_scene106_clean.png`
- `route_plan_scene109_clean.png`
- `route_plan_scene118_clean.png`
- `route_plan_scene140_clean.png`
- `route_plan_scene139_clean.png`
- `route_plan_蜀山链_composite.png`
- 说明 `route_plan_蜀山链_README.md`：蓝=入口，黄=真实门，红/橙=team改动/救援
- 用户可在图上直接画路线；画好交回按标注改，不自补通道

## 状态
- 本轮未改代码；HEAD 见回执；槽1只读、未开窗、未实机。
