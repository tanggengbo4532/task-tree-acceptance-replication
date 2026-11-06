# R308 scene253 冻结/ERROR洪水修复（wave + battle编译）

## 实机现象
- 载入用户档 scene253：画面冻结/输入无响应；stderr 29MB：
  `ERROR: Image height specified (0) ... _apply_wave world.gd:11176 ← _render 8740 ← _process 6989`
- 两次复现

## 根因（两处叠加）
1. **wave set_data 参数顺序错误**
   - 旧：`_img.set_data(y, 0, SCREEN_W, 1, merged)`
   - Godot `Image.set_data(height, y, width, x, data)`；第一参=y，y=0 时 height=0 → 每帧 ERROR 洪水
   - 修：`_img.set_data(1, y, SCREEN_W, 0, merged)`；加 `_img` 未初始化/尺寸不足 guard；y/merged.size 边界检查
2. **battle.gd 编译失败**
   - R307 `_magic_menu_text` 使用了未声明变量 `mtype` → battle.gd 编译失败
   - `request_battle()` 每帧 `load("battle.gd").new()` 抛 `Nonexistent function 'new'`；战斗节点无法创建 → 输入落在 world/无战斗，表现为冻结
   - 修：声明 `mtype`；TRANCE 行不再追加“效果见脚本”；战斗脚本恢复编译
3. **读档屏幕波动状态**
   - `_reset_after_save_load()` 重置 `PALState.screen_wave=0 / wave_progression=0`，避免旧档水波状态在首帧图像执行

## 验证（headless，用户档只读副本）
q2179（载入 scene253 + 强制 wave）：
```
[qa] scene=253 pos=(336,376) battle=true busy=false frame=689
[qb] wave=0 prog=0 frame=779
[qc] input_alive frame=789
exit=0 stderr_len=0
```
- 无 `Image height specified`、无 `Nonexistent function 'new'`、无 SCRIPT ERROR；帧号持续前进
- q2178 实际战斗仙术行：
```
梦蛇 99MP 变身/强化（TRANCE） 全体
夺魂 83MP 附加「乱」0回合，即死 敌方单体
雷神 68MP 威460 雷 伤害 全体
```
- q2176 场上菜单 Label：`梦蛇/夺魂/第1/1页 共10项/效果…` 均实际存在

## tester 复跑（用户要求）
1. 完全关闭旧进程重启，控制台确认 **`[BUILD] R308-waveguard`**
2. 载入用户档8880副本/团队槽2：scene253 应正常进入终战/可响应，不应冻结；stderr 应 0
3. 终战战斗→仙术：10项分2页，第2页可选中；逐项截图
4. 若有战斗外机会：Esc→仙术→巫后，选梦蛇/夺魂截图亮白说明行
5. 若仍冻结：立即停止，抓 `stderr` 前 50 行 + `[BUILD]` 行 + 截图

## marker/状态
- **`[BUILD] R308-waveguard`**
- 槽1只读8880；槽2=该档副本；开发未开窗
- 文档本文件
