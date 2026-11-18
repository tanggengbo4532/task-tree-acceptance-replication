# examples 索引

| 文件 | 用途 | 推荐 |
|---|---|---|
| `pal98-godot.json` | Godot 项目脱敏样例（引擎无关契约 + Godot 可观测性） | ✅ 推荐 |
| `generic-desktop.json` | 任意 Windows 桌面应用通用样例 | ✅ 推荐 |
| `godot-project.md` | Godot 项目侧可观测性钩子清单（开发者配合项） | 参考 |
| `web-app.json` | Web 后端配置示例 | 参考 |
| `quickstart.py` | 使用本地 Web 页面演示失败取证、复测和三重确认 | 首次体验 |

说明：
- 旧版 `pal-godot.json` 已在 v3 迁移为脱敏的 `pal98-godot.json`（内容等价、路径占位、去掉内部信息）；**新项目请直接复制 `pal98-godot.json` 或 `generic-desktop.json`**。
- 所有样例中的 `launch`/`args`/`shot_dir` 均为占位，请改为你自己的绝对路径；`title_pattern` 要足够精确，避免误杀编辑器窗口。
- 配置字段见[后端契约](../scripts/backends/CONTRACT.md)。从插件根目录运行 `python -B examples/quickstart.py` 可体验完整流程。
