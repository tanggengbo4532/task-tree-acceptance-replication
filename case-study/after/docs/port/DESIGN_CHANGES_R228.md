# R228 A40 塔顶后 A41 离开蜀山→苗疆·圣姑居（scene178）

## 原版数据
- scene156（塔顶）事件：
  - evt2518 auto22538、evt2519 mode8 脚本22546（塔顶剧情状态机）、evt2520 state2、evt2521 mode5 脚本22607→scene158；
- A41 代码常量 `A41_MIAO_SCENE=178`（圣姑居）；scene178 onEnter 脚本 **27955**（救治/救月如/灵儿剧情）；
- A40 后原版门链经 158/160 等中继，当前已通场景数据里没有直达 178 的普通 event 门（0x59 178 仅在非事件子脚本中）。

## 实现（R228-A41-1）
- scene156 且 `a40_stage>=1 && a41_stage<1`：
  - 提示 **「按空格离开蜀山（前往苗疆·第 6 章）」**；
  - SPACE → `a41_stage=1`、`_a41_entered=true`、`loaded_from_save=false`、
    真实 `load_scene(178)`，由原版 **scene178 onEnter 27955** 播苗疆剧情；
  - `_show_a41_goal("已离开蜀山，到苗疆·圣姑居（第6章）")`。
- 不伪造路/场景，使用原版 scene178/onEnter。

## headless
- scene156：prompt「按空格离开蜀山（前往苗疆·第6章）」；
- SPACE → **scene178 (1408,704)**，`a41_stage=1`，**dlg=true（onEnter 27955 剧情开始）**；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene156_top_anchor`（scene156 1024,1600，a40_stage=1）
- `round78/slot4_scene178_miao_anchor`（scene178 1408,704，a41_stage=1）

## tester
- 从槽2 到 scene156 塔顶剧情后：SPACE → scene178 苗疆剧情；
- 下一步：scene178 onEnter 27955 内的 A42/A43 后续（圣姑/灵儿线）接线。
