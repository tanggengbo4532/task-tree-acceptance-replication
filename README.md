# Game Playtest — 通用应用黑盒验收框架

本仓库是一个 **DSH 插件（skill）**，实现一套**通用应用/游戏黑盒验收架构**：由固定 **4 个 Agent**（Lead / 开发 / 测试 / 记录）协作，把「像真实用户一样把应用用通」拆成**四要素任务树节点**逐节点验收，全程真实输入、禁作弊、证据留痕。

> **架构是主角。** 本仓库的核心是这套多智能体循环验收框架（详见 [`SKILL.md`](SKILL.md)）。`case-study/` 里的游戏源码只是验证该架构的一个压力测试案例，不是本仓库的目标。

适用于**任意带界面的应用**：桌面软件、Web/Electron、游戏。

## 一句话

把验收拆成「线路 → 四要素任务树 → 节点」，由 4 个 Agent 闭环：Lead 协调、开发白盒修、测试黑盒验、记录只读归档；**节点全部通过才算整体通过**。

## 核心组成

- **四要素任务树**：每个节点记录人、地点、要达到的状态和唯一标识 `t_node`。JSON 校验器检查任务树结构、状态迁移和验收记录。
- **四角色**：Lead 协调、开发白盒修复、测试黑盒取证、记录归档。需要按操作系统账户限制判定写入时，见[角色权限部署](references/standards/role-permissions.md)。
- **三重确认**：测试自判、开发复核和 Lead 宣布绑定同一构建、同一轮和同一组证据 SHA-256。重开保留旧记录，复测重新取证和确认。
- **禁作弊红线**：只走用户可达的界面路径；禁止直接改状态/数据库/内部接口、跳过必经流程、自动判定成功、用调试模式取证。
- **数据隔离**：用户数据（账号/数据库/配置/存档）只读；自动化只操作测试数据或临时实例；破坏性操作需显式目标与归属校验。
- **双进度协议**：进度一=用户专用（只读）、进度二=团队专用（可覆盖），人机进度严格分离。
- **输入门禁**：注入输入前确认界面状态可接收输入；后端拒绝点击隐藏/禁用/被遮挡的元素。
- **可观测性不变量**：引导-交互同源、提示单源、目标单调、等待有界。
- **backend 契约**：引擎无关、可插拔，按 `playtest.json` 的 `backend` 字段分发：
  - `windows`：桌面应用/游戏（键、鼠标点击、文本、滚动、截图；PostMessage 或 SendInput）；
  - `web`：网页/Electron 渲染层（Edge/Chrome CDP，零依赖；元素定位只用于确定点击位置，真实鼠标事件；只读 `state`/`read_text`）。

完整说明见 [`SKILL.md`](SKILL.md)，后端契约见 [`scripts/backends/CONTRACT.md`](scripts/backends/CONTRACT.md)。

## 目录

- `SKILL.md` / `plugin.json` — 框架主体与插件清单
- `references/` — 角色 prompt、标准（禁作弊/数据隔离/证据/经验库/可观测性）、测试方法论
- `templates/` — 任务树、步骤文件、验收报告、经验日志、锚点台账等 17 个模板
- `scripts/` — backend 契约、Windows 参考实现、Web 后端
- `tools/` — 统一分发 `backendlib.py`；步骤执行器、走位器、锚点检查；量化探针、截图工具、证据清单
- `tests/` — 打包自检、Windows 后端真机测试（fixture 窗口）、Web 后端端到端测试（headless）
- `examples/` — 接入示例（Web、桌面、Godot）
- `PAPER.md` — **论文材料索引**：论文引用的固定路径、数据版本、复现边界（论文只有本仓库，材料不拆分，统一从这里链接）
- `case-study/` — **案例**：PAL98 Godot 移植源码，含 `before/`（修复前 bug 版）与 `after/`（修复后）对比
- `experiments/` — **实验数据与可复现包**：HUD 54 runs、经验消融 24 runs、repro 清单与审计

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

`-Force` 只会替换已有的本插件安装目录；目标不是本插件或包含源目录时安装会拒绝执行。

## 五分钟体验

安装 Python 3.8 或以上版本，并准备 Edge 或 Chrome。在插件目录运行：

```powershell
python -B examples/quickstart.py
```

示例用本地便签页面演示一次错误密码导致的验收失败，输出失败截图和日志位置，再用正确密码复测。
复测通过后只有测试自判。脚本会验证 Lead 提前确认被拒绝，然后依次写入演示用的开发复核和 Lead 确认。
任务树、取证文件和操作轨迹保存在命令打印的临时目录。接入真实项目时，请各角色阅读证据后执行自己的确认。
完整命令和旧任务树迁移说明见[任务树模板](templates/task-tree.md)。

## 自检

```powershell
python -B tools/verify/task_tree.py check --tree examples/task-tree.json         # 历史任务树示例
python -B tools/verify/task_tree.py --selfcheck                                  # 判定、复测和权限回归
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Plugin.ps1    # 打包 + 安装 + Web 端到端
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Backend.ps1   # Windows 后端真机（会开一个测试窗口）
python -B tests/Test-WebBackend.py                                           # Web 后端真机（headless）
```

## 许可

MIT（见 [`LICENSE`](LICENSE)）。
