# R232 A47 南诏（scene206→247 真实入口）

## 数据
- A47 常量：`A47_NANZHAO_SCENE=247`、`A47_ARRIVE_SCRIPT=32455`（scene247 onEnter 到达剧情）；
- scene206 当前可走出口 evt3441→211，但 211 只有回206门，无直达247门；
- scene247 只由非事件子脚本（地址30646，`0x59 247`）加载，当前可达场景链没有普通 evt 门；
- 因此沿用本移植已确认方式：A46 完成后从白苗族大厅调用 **真实 scene247/onEnter32455**，不伪造路。

## 实现（R232-A47-1）
- scene206 且 `a46_stage>=1 && a47_stage<1`：
  - 提示 **「按空格去大理/南诏（第 7 章 G1）」**；
  - SPACE → `a47_stage=1`、`loaded_from_save=false`、`load_scene(247)`，
    原版 **onEnter 32455** 播南诏到达剧情；`_show_a47_goal("已到南诏（第7章 G1）：去黑苗王宫（找灵儿）")`；
- c3 scene206：A46 完成后返回空，避免继续指「与族长交谈」；
- HUD 场景列表加入247。

## headless
- scene206（a46=1）：prompt「按空格去大理/南诏」；
- SPACE → **scene247 (1568,1696)**，`a47_stage=1`，HUD「已到南诏（第7章 G1）：去黑苗王宫（找灵儿）」；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene206_hall_posttalk_anchor`：scene206 (864,1280)，a46=1（族长对话后）
- `round78/slot4_scene247_nanzhao_anchor`：scene247 (1568,1696)，a47=1

## tester
- 白苗族大厅对话完成后 SPACE → scene247 南诏；
- 下一步：A48 黑苗王宫（找灵儿）真实门接线。
