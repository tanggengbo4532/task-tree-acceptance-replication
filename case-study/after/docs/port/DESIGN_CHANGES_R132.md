# R132 tester4 路线：scene58 出门 → scene55 回白河村

## 文件与 SHA256（`_playtest_regress_dev/round82/`）
| 文件 | 起点 | 终点 | 步数 | SHA256 |
|---|---|---|---|---|
| keys_r132_51_scene58_exit.txt | scene58 (1504,1848) N0 | scene55 (416,544) N268 | SPACE×1 | `BC576F4953538A08B6207DD6EB07D6F44169D34B5FE0F22731920A2C2D05568A` |
| keys_r132_52_scene55_evt924_chunk1.txt | (416,544) N268 | (176,928) N183 | 85 | `FED132DB9FCF4899F3BA9FEA44720E941E8A8D0FDD6AA65B9B90A9F6AA6A8233` |
| keys_r132_53_scene55_evt924_chunk2.txt | (176,928) N183 | (496,1416) N98 | 85 | `04209857CC4E3A554C2AA614178572B66B522B330A14D8C7E51CE1E67F4D4FDF` |
| keys_r132_54_scene55_evt924_chunk3.txt | (496,1416) N98 | (976,1752) N0 + SPACE | 98 | `A77C6563B7617810A18C3C396D7B8DBB76E017AB30AFE62615FAD6568F1B02D9` |

## 执行顺序 / 存档点
1. tester4 只读用户槽1 → scene58；按 **SPACE×1**（evt945 出口脚本11114）→ scene55 (416,544) N268。
2. 依次执行 chunk1 → 终点 (176,928) N183 **存槽2**（A28 锚点之后可覆盖）。
3. chunk2 → 终点 (496,1416) N98 **存槽2**；末段 chunk3 最后一行 **SPACE** → scene50 白河村。
4. 每键 keydown+keyup、按后等坐标变化或 >=220ms；每10步 OCR 核对坐标；N 每步应 −1。

## 途中遇怪 STOP（真实随机/触碰战）
- chunk2 的 **第6步（全局第90步）**：从 (176,960) 往下走会触发真实怪物 **evt929**（script41151）。
- 处理：正常打赢或逃跑；**战斗结束位置不变**，继续按该步按键（第90步）及后续行，不要回段首/不要读回 chunk1。
- 探针生成路线时仅临时关闭了 scene55 的怪物事件（928-931）以取得确定性 268 步；真实走时由 tester 打/逃跑，坐标与 N 与文件一致。

## 后续节点（真实数据核对）
- evt924 脚本9683：scene55 → **scene50** 白河村（落点由脚本 0x46 指定）。
- A30 后续剧情节点：**scene68 evt1343**（脚本12655 → scene78 扬州）；从 scene50 到 scene68 的外围路线尚未出 keyseq；
  tester 到 scene50 后先存槽2/报告，我再补 A30 后续分段。
- 全部文件由 headless 真实按键逐段回放 **3/3 PASS**（chunk1/2/3 起点/终点/N 全匹配；战斗事件仅探针内临时关闭）。
