# examples 索引

| 文件 | 用途 | 推荐 |
|---|---|---|
| `pal98-godot.json` | Godot 项目脱敏样例（引擎无关契约 + Godot 可观测性） | ✅ 推荐 |
| `generic-desktop.json` | 任意 Windows 桌面应用通用样例 | ✅ 推荐 |
| `godot-project.md` | Godot 项目侧可观测性钩子清单（开发者配合项） | 参考 |

说明：
- 旧版 `pal-godot.json` 已在 v3 迁移为脱敏的 `pal98-godot.json`（内容等价、路径占位、去掉内部信息）；**新项目请直接复制 `pal98-godot.json` 或 `generic-desktop.json`**。
- 所有样例中的 `launch`/`args`/`shot_dir` 均为占位，请改为你自己的绝对路径；`title_pattern` 要足够精确，避免误杀编辑器窗口。
- 配置字段以 `scripts/backends/CONTRACT.md §2`（playtest.json v2）为准。
