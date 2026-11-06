# R309 wave 行更新 API 修正（set_data→blit_rect）

## 实机新错误
`_apply_wave` 仍 stderr 17MB：
`Expected Image data size of 1xNx1 (Lum8...) got 1280 bytes @world.gd:11185`
- 上一版 `_img.set_data(1, y, SCREEN_W, 0, merged)` 仍错：Godot4 `Image.set_data(width,height,mipmaps,format,data)` 是整图 API，不是按行；`set_region` 在 Godot4 Image 也不存在

## 正确 API（R309）
- `_img` = `Image.create_empty(SCREEN_W,SCREEN_H,false,FORMAT_RGBA8)`
- 每行构造同格式行 Image：
```gdscript
var row := Image.create_from_data(SCREEN_W, 1, false, _img.get_format(), merged)
_img.blit_rect(row, Rect2i(0, 0, SCREEN_W, 1), Vector2i(0, y))
```
- 不再使用 `set_data` 按行，也不使用不存在的 `set_region`
- 保留 R308 guard/边界检查/读档 wave 重置

## headless 验证（用户档 scene253）
q2181：强制 `screen_wave=128, progression=0`，连续1009帧（≥600帧 wave 非0）：
```
[qa] scene=253 pos=(336,376) battle=true frame=389
[wave] cycle=0..5 wave=128 prog=0 frame=489..989 battle=true
[qb] final wave=0 prog=0 frame=1009
exit=0 stderr_len=0
```
- **stderr 0B**；无 `Expected Image data size`、无 SCRIPT ERROR
- scene253 正常进入战斗，帧号持续前进

## tester 复跑
A：
1. 重启确认 `[BUILD] R309-wave-row`
2. 载用户档8880副本：scene253 不冻结、输入正常、**stderr 0B**
B：
3. 战斗→仙术：10项分2页，第2页可见/选中
4. 场外 Esc→仙术→巫后：梦蛇/夺魂亮白说明行

## 状态
- 槽1只读8880；槽2=该档副本；开发未开窗
- marker **`[BUILD] R309-wave-row`**
