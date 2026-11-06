# 探针与量化度量（probes & metrics）

> 目的：把"感觉卡/走不动/引导乱"变成**可复核的数字**，并保证结论不是靠感觉。
> 工具：`tools/probes/*`（walkprobe / holdprobe / fps_probe）、`tools/screen/*`、`tools/evidence/manifest.py`；后端：`scripts/windows/PlaytestKit.ps1` + `Capture.ps1`（或等价 backend 实现）。
> 依赖：Python ≥3.10 + Pillow；所有 live 模式要求**单实例、你是被测窗口的 owner**。

---

## 1. 工具总览

| 工具 | 回答什么问题 | 模式 |
|---|---|---|
| `tools/probes/walkprobe.py` | 每次轻按是否真的产生了移动？吞键率多少？ | offline（截图序列）/ live（驱动后端） |
| `tools/probes/holdprobe.py` | 长按期间画面更新是否连续？最长冻结多久？变化帧多少？ | offline / live |
| `tools/probes/fps_probe.py` | 给定采样间隔下画面更新率/停顿分布（不发送输入） | offline / live |
| `tools/screen/crop_region.py` | 裁剪提示条/数字区域，便于人工读数 | 任意 PNG |
| `tools/screen/image_ops.py` | 两图差异、空白检测、哈希、像素统计 | 任意 PNG |
| `tools/evidence/manifest.py` | 证据清单（sha256/大小/时间/分组），只增归档 | 证据目录 |

**通用约定**：
- 所有 probe 输出 JSON（stdout）+ 人工摘要；建议 `--json <file>` 落盘；
- live 模式需要 `--config playtest.json`，且必须显式加 `--yes-i-am-the-owner-of-this-test`；
- 判定阈值默认 `--threshold 0.0005`（差异像素比例），可按分辨率/素材调整，但**同一轮内保持一致**；
- 探针失败/缺失 → **降级为人工测量并在报告标注"人工测量"**，不得用估算数据冒充验收证据（`README.md` 同款纪律）。

---

## 2. walkprobe（逐键移动/吞键率）

### 2.1 用法

```powershell
# live：按 15 次 DOWN（每键 hold 60ms，键后等 200ms 再截下一帧）
python tools\probes\walkprobe.py --config playtest.json --key DOWN --taps 15 `
    --hold-ms 60 --gap-ms 200 --prefix walk_s2 --json walk_s2.json `
    --yes-i-am-the-owner-of-this-test

# offline：已有"每键一帧"的序列目录（文件名有序；相邻两帧=一次按键前后）
python tools\probes\walkprobe.py --dir .\roundNN\walk_frames `
    --threshold 0.0005 --json walk_offline.json
```

### 2.2 输出解读

| 字段 | 含义 |
|---|---|
| `keys`/`taps` | 采样键数 |
| `moved` / `swallowed` | 有明显画面变化的键数 / 无变化键数 |
| `swallow_rate` | 吞键率 = swallowed / keys |
| `rows[].diff` | 相邻帧差异比例（可用于定位"哪一键没动"） |

### 2.3 阈值建议

| 轻按成功率 | 判定 | 处理 |
|---|---|---|
| ≥90%（吞键 ≤10%） | 通过 | 继续节点 |
| 70~90% | 警告 | 记录案例；确认是否被墙挡/对白中/低帧率，再复测 1 次 |
| <70% | **不通过（输入丢失）** | 停手取证，报"轻按吞键"，附 walkprobe JSON；建议开发加输入缓冲/调整 hold-gap |

> 注意：**被墙挡住/等待对白/菜单未关**也会表现为"无变化"，不是吞键。判定前先确认：当前不在对话/过场、该方向确实可走（先单次试探 1~2 步）、窗口在前台。

### 2.4 真实案例（本项目）

| 阶段 | 场景 | 结果 | 来源 |
|---|---|---|---|
| 修复前 | 场景2 房间 | 15 键中 5 键无位移（吞键 33%） | `_playtest_regress/round76/tester-report.md` §B |
| 修复前 | 走廊 | 15 键中 **12 键**无变化（仅移动 1 格） | 同上 |
| 修复前 | 一楼大厅 | 10 键中 8 键无变化 | 同上 |
| 修复后 | 场景2 直段 | **7 键 = 7 格**（N 15→8） | `_playtest_regress/round76/tester-report.md` §G1/#6、§H1/#7 |
| 修复后 | 走廊（UP/LEFT 组合） | **16 键 ≈ 15 格** | `_playtest_regress/round76/tester-report.md` §G1/#6 |
| 修复后 | 街道 | 8 键 → N -11 | `_playtest_regress/round76/tester-report.md` §H1/#7 |

> 同一场景的直观对比：入口房间**15 键只前进 7 格**（修复前，`tester-report.md` §B）→ **7 键前进 7 格**（修复后，§G1/#6）。
> 即：修复前"看起来按了 15 次"实际只走 7 格；修复后达到"每键 1 格"。

---

## 3. holdprobe（长按帧采样/冻结）

### 3.1 用法

```powershell
# live：按住 DOWN 800ms，期间每 90ms 采样一帧（共 2 轮；--settle-ms 为结束后等待）
python tools\probes\holdprobe.py --config playtest.json --key DOWN --ms 800 --interval-ms 90 `
    --settle-ms 300 --prefix hold_s2 --json hold_s2.json `
    --yes-i-am-the-owner-of-this-test

# offline：分析已有长按采样帧目录
python tools\probes\holdprobe.py --dir .\roundNN\hold_frames --interval-ms 90 --json hold_offline.json
```

### 3.2 输出解读

| 字段 | 含义 |
|---|---|
| `samples` | 采样帧对的样本数（≈ hold_ms / interval_ms） |
| `changed_samples` / `change_rate` | 有画面变化的样本数 / 比例 |
| `longest_freeze_ms` | 最长"连续无变化"时长（= 停顿时间） |
| `longest_freeze_samples` | 对应样本数（×(interval_ms) 估算） |
| `max_diff` / `avg_diff` | 最大/平均帧差比例（辅助判断"变化是否显著"） |

### 3.3 阈值建议（hold 800ms、interval 90ms 的标定）

| 指标 | 通过 | 警告 | 不通过 |
|---|---|---|---|
| 变化帧 | **≥8/10** | 6~7/10 | **<6/10**（低帧率/停顿） |
| 最长冻结 | **<100ms** | 100~150ms | **>150ms**（>300ms 严重卡顿） |
| 长按位移（可选） | 800ms ≥2 格（按住连走语义） | 1 格 | 0 格（输入/状态问题） |

> 前提：**该方向必须真的可走**。被墙挡/到达交互点/对白中时画面本就不变，此时 `freeze` 大是"停走"而非卡顿——先做 1~2 次单键试探确认可走，再采样。

### 3.4 真实案例（本项目）

| 阶段 | 场景 | 结果 | 来源 |
|---|---|---|---|
| 修复前 | 场景2 房间 | 变化 3/10、3/10；**冻结 344ms / 348ms**（≈3~4fps） | `_playtest_regress/round76/tester-report.md` §B |
| 修复前 | 走廊 | 变化 2~4；**冻结 297ms / 361ms** | 同上 |
| 修复前 | 一楼大厅 | 一次 10/10 流畅、一次 3/10 **冻结 269ms**（间歇性） | 同上 |
| 修复后 | 街道长直路 | 变化 **9/9、8/9**；**冻结 0ms / 83ms** | `_playtest_regress/round76/tester-report.md` §H1/#12 |
| 开发侧根因（白盒补充） | 场景4 `_update_route_hint` 单次 | **2,090,491.9µs（≈2.09s）** → 修复后 **3.5µs** | `_playtest_regress_dev/round76/perf_before.log`、`_playtest_regress_dev/round76/ROUND76_FIX_REPORT.md` §2 |

---

## 4. fps_probe（画面更新率/停顿）

```powershell
# offline：对一段定间隔采样帧估算更新率与停顿
python tools\probes\fps_probe.py --dir .\roundNN\fps_frames --interval-ms 90 --stall-ms 250 --json fps.json

# live：只采样、不发输入（阅读界面/观察卡顿用）
python tools\probes\fps_probe.py --config playtest.json --frames 30 --interval-ms 100 `
    --prefix fps_s2 --json fps_s2.json --yes-i-am-the-owner-of-this-test
```

输出关键字段：`update_rate_hz`（按采样间隔估算的画面更新率）、`stalls_over_ms` / `stall_count` / `stall_ms_list` / `max_stall_ms`、`blank_frames`（空白帧 → 截图抗伪检查）。

阈值建议（仅作"是否明显低帧/停顿"的辅助，不作唯一结论）：

| 指标 | 通过 | 警告 | 不通过 |
|---|---|---|---|
| 移动中 `update_rate_hz` | ≥15Hz | 8~15Hz | **<8Hz** |
| `max_stall_ms`（stall-ms=250） | 0 | 1 次 250~300ms | **≥300ms 或多次** |
| `blank_frames` | 0 | 偶发（截图方法问题） | 连续空白（截图/渲染异常，需换取证方法） |

> 采样间隔 > 帧周期时，`update_rate_hz` 只是上限估计；用于**横向对比同一轮前后**最可靠。

---

## 5. 屏幕工具（提示读数/差异）

```powershell
# 裁剪提示条区域（先 info 拿 client 尺寸，再用一帧试坐标）
python tools\screen\crop_region.py in.png out_hint.png --region 60,145,1160,110

# 两图差异/空白/哈希/像素统计
python tools\screen\image_ops.py --help
```

- 关键读数（"剩余 N 格"、目标文本）从裁剪图人工读，避免整图缩放看不清；
- 对比类问题（修前/修后）保留**同位置**两帧，写进验收对照；
- 截图空白/全黑：`Capture.ps1` 默认 `auto`（PrintWindow 空白回退屏幕拷贝）；仍异常时多方法交叉，**不要直接用空白帧下结论**。

---

## 6. 证据命名、日志重定向、manifest

### 6.1 目录与命名

```text
roundNN/
├─ tester-report.md / EXPERIENCE.md
├─ rNN_<序号>_<语义>.png           # 例：r76d_09_stair_prompt.png
├─ rNN_hold_*/  rNN_walk_*/        # 探针采样帧（前缀体现工具）
├─ rNN_run.log                     # stdout
└─ rNN.err.log                     # stderr，期望 0B（非 0 需解释）
```

- **轮次前缀唯一**，绝不覆盖历史轮次；关键帧后缀 `_before/_after/_blocked/_pass/_hint`；
- 探针 JSON 与截图同轮保存（`walk_s2.json`、`hold_s2.json`、`fps_s2.json`）。

### 6.2 日志重定向

```powershell
$exe = (Get-Content .\playtest.json -Raw | ConvertFrom-Json).launch
Start-Process -FilePath $exe -ArgumentList $args `
  -RedirectStandardOutput .\roundNN\rNN_run.log `
  -RedirectStandardError  .\roundNN\rNN.err.log -PassThru
```

- 崩溃/异常类问题必须保留 `err.log`；期望 0B，非 0 时把原文与含义写进报告（允许说"警告不阻塞"）。

### 6.3 证据清单（只增）

```powershell
python tools\evidence\manifest.py init --index .\roundNN\manifest.json --round roundNN
python tools\evidence\manifest.py add  --index .\roundNN\manifest.json --dir .\roundNN --tag evidence
python tools\evidence\manifest.py verify --index .\roundNN\manifest.json
python tools\evidence\manifest.py list  --index .\roundNN\manifest.json
```

- manifest 记录 sha256/大小/时间，**只增不覆盖**；复核时 `verify` 检查漂移（文件被改/被替换会报出）。

---

## 7. 真实项目引用数据表（可追溯）

> 以下均为真实项目的黑盒/白盒记录，用于说明阈值来源；路径相对项目根。**不虚构数字**，引用时保留路径。

| 数据 | 数值 | 来源路径 |
|---|---|---|
| 修复前走路冻结 | 344/348ms（房间）、297/361ms（走廊）、269ms（大厅） | `_playtest_regress/round76/tester-report.md` §B |
| 修复前吞键 | 5/15、12/15、8/10 | 同上 §B |
| 修复后轻按 | 7 键 7 格；16 键≈15 格；8 键 -11 | 同上 §G1、§H1 |
| 修复后长直路 | 变化 9/9、8/9；冻结 0/83ms | 同上 §H1/#12 |
| 根因微基准 | scene4 `_update_route_hint` **2,090,491.9µs**；scene5 430,425.8µs；scene6 74,978.5µs；scene2 9,141.9µs | `_playtest_regress_dev/round76/perf_before.log`、`ROUND76_FIX_REPORT.md` §2 |
| 修复后微基准 | scene4 **3.5µs**（缓存命中）；scene2 4.7µs；scene5 7.1µs；scene6 3.4µs | `_playtest_regress_dev/round76/ROUND76_FIX_REPORT.md` §2 |
| 引导可走性（白盒补充） | `scene2 checked=3 violations=0`；`scene4-2F checked=61 violations_total=0`（修复后）；修复前曾出现 `violations_total=4` | `_playtest_regress_dev/round76/guide_step_final.log`、`guide_step.log` |
| 回放节奏失配 | 193 键回放仅走 ≈12 步（187→175；实机 ≈1 步/0.9~1.0s） | `_playtest_regress/round75/tester-report.md` §21 |
| 录制过快丢键 | 330ms/键执行 86 键，N 88→80（应到 0） | 同上 §27 |
| 自动走位不可靠 | "按移动反馈选向"被场景门带回上一场景并卡角落 | `_playtest_regress/round76/tester-report.md` §I2 |

> 白盒微基准与黑盒帧采样是**不同口径**：前者证明"代码路径耗时"，后者证明"玩家看到的卡顿"；两者都记录、都引用，不互相替代。

---

## 8. 判读决策树（卡顿/吞键/低帧）

```text
玩家反馈"走路卡/走不动"
├─ 先确认：前台焦点正确？单实例？不在对白/过场？── 否→ 修正环境后复测
├─ 轻按成功率（walkprobe live, 15 键）
│   ├─ ≥90% → 输入基本正常，转"卡顿"分支
│   └─ <90% → 记录吞键率；再测 hold：长按 800ms 位移
│         ├─ 0 格 → 报"输入/状态问题"（附 walkprobe JSON）
│         └─ ≥1 格 → 报"轻按吞键"（建议输入缓冲/加大 hold-gap）
└─ 卡顿分支：holdprobe live（800ms ×2，方向先确认可走）
    ├─ 变化帧 ≥8/10 且冻结 <100ms → 未复现卡顿（记录场景/构建，换场景再测）
    ├─ 变化帧 6~7/10 或冻结 100~150ms → 轻微/间歇，扩大采样（≥3 次）与场景
    └─ 变化帧 <6/10 或冻结 >150ms → **判定卡顿**；附 JSON+截图+场景/位置，报开发排查
```

---

## 9. 使用边界（写死，防误判）

1. **被挡/停走 ≠ 卡顿**：先单键试探 1~2 步确认可走再采样；
2. **角色动画/转身**也会造成小差异：小 diff 不等于"移动"，结合位置/数字/场景语义判断；
3. **长按语义因应用/场景而异**：先验证"按住连走"还是"单次触发"，再定阈值；
4. **间歇性卡顿必须 ≥2 次采样**（同场景可一次流畅一次冻结）；
5. **采样间隔限制**：`update_rate_hz` 是估计值；跨构建比较同一 interval 才有意义；
6. **探针不是验收**：工具只给数字；节点结论仍需"真实操作 + 证据 + 双重确认"；
7. **不得用基线数据凑结论**：任何"通过"必须来自本轮实测（构建 hash、场景、时间一致）。
