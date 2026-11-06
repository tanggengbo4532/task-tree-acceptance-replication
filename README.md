# Game Playtest — 多智能体循环验收框架

本仓库是一个 **DSH 插件（skill）**，实现一套**通用游戏/应用黑盒验收架构**：由固定 **4 个 Agent**（Lead / 开发 / 测试 / 记录）协作，把「像真实用户一样把游戏玩通」拆成**四要素任务树节点**逐节点验收，全程真实输入、禁作弊、证据留痕。

> **架构是主角。** 本仓库的核心是这套多智能体循环验收框架（详见 [`README.md`](README.md) 和 [`SKILL.md`](SKILL.md)）。`case-study/` 里的游戏源码只是验证该架构的一个压力测试案例，不是本仓库的目标。

## 一句话

把验收拆成「线路 → 四要素任务树 → 节点」，由 4 个 Agent 闭环：Lead 协调、开发白盒修、测试黑盒验、记录只读归档；**节点全部通过才算整体通过**。

## 核心组成

- **四要素任务树**：每个节点 = 人（谁）/ 地点（在哪）/ 做到什么（事）/ 时间（节点唯一标识 `t_node`）。
- **四角色**：Lead（协调）/ 开发（白盒）/ 测试（黑盒）/ 记录（只读），权限隔离、禁止越权。
- **三重确认**：测试自判 → 开发复核 → Lead 宣布，任一方未完成则继续。
- **禁作弊红线**：真实输入/真实战斗/真实对白，禁止传送、跳场景、自动胜、伪造状态。
- **双进度协议**：进度一=用户专用（只读）、进度二=团队专用（可覆盖），人机进度严格分离。
- **槽安全铁律**：任何情况不写用户槽，自动化输入前必须确认 UI 状态。
- **可观测性不变量**：引导-移动-触发同源、提示单源、目标单调、等待有界。
- **backend 契约**：引擎无关、可插拔（Windows 参考实现 + headless 探针）。

完整说明见 [`README.md`](README.md)，架构细节与角色边界见 [`SKILL.md`](SKILL.md)。

## 目录

- `SKILL.md` / `README.md` / `plugin.json` — 框架主体与插件清单
- `references/` — 角色 prompt、标准（禁作弊/槽安全/证据/经验库/可观测性）、测试方法论
- `templates/` — 任务树、验收报告、经验日志、锚点台账等 16 个模板
- `scripts/` — backend 契约与 Windows 参考实现（PlaytestKit/Capture）
- `tools/` — 量化探针、截图工具、证据清单、验证自动化（hud_walker 等）
- `examples/` — 接入示例（脱敏）
- `case-study/` — **案例**：PAL98 Godot 移植的**初始 bug 版**源码（用于复现验收过程）

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

## 许可

MIT（见 `plugin.json` 的 `license` 字段）。
