# M.msg 文本 + 消息偏移表 + 控制码 → msg_zh.json

> 导出器：`新建游戏项目/tools/gen_msg_json.py`
> 产物：`_rea_runtime/out/assets/msg_zh.json`（1,531,852 B，UTF-8，13513 条）
> 样例：`_rea_runtime/out/assets/msg_sample.txt`

## 1. 文件结构 [observation]

| 项 | 值 |
|---|---|
| M.msg | 224455 B，sha256 `b8c37694665ff857…56a0f5d` |
| 偏移表 | SSS.MKF 块 3：54056 B = **13514 个 uint32** |
| 偏移性质 | 字节偏移，`offs[0]=0`，单调不减，`offs[13513]=224455`=M.msg 长度 ✔ |
| 消息条数 | **13513**（= 13514 - 1） |
| 编码 | **GBK/cp936**（简体）；少量条目的符号字节需 GB18030 才能解 |
| 结尾符 | **无 NUL**，第 i 条 = `M.msg[offs[i] : offs[i+1]]` |
| 文件头 | 无（第一条消息从偏移 0 开始） |

GBK 证据：消息 #1 字节 `c0 ee e5 d0 d2 a3 3a` → "李逍遥:"；#3 `bcd 2...` → "既然落在你的手里，"
（1285 条消息中 928 条出现全角"～"，属正常正文符号，不是控制码）。

### 1.1 少数条目含 PUA 自定义符号 [observation]

7 条消息（#2171, #2667, #3448, #7782, #12726, #12861, #13215）含 GBK 严格模式非法的
双字节码（如 `ad f4`、`aa b1`、`a1 41`）。用 **gb18030**（GBK 超集）解码可得到
私用区字符 U+E010/U+E16D/U+E47E/U+E4C7/U+E4C9/U+E790 等，说明它们是游戏自定义
符号字形（可能是特殊标点/图标），不是文本损坏。导出器优先 `gbk`、失败回退 `gb18030`，
结果 **0 个替换字符**；Godot 侧遇到 U+E0xx..U+F8FF 时可显示空白或映射到自制符号。

## 2. 内嵌控制码（sdlpal text.c `PAL_DrawTextUnescape` [inference]）

| 序列 | 消耗字节 | 语义 |
|---|---|---|
| `$` + 2 位十进制 | 3 | 设置打字延时 = `atoi(后两位) * 10 / 7`（帧） |
| `~` + 数字 | 2..3 | 延时 `atoi(后随) * 80 / 7` 后暂停/结束本行（对话等待） |
| `@` | 1 | 切换红色字体 |
| `"` | 1 | 切换黄色字体（对话中） |
| `)` | 1 | 等待图标 1 |
| `(` | 1 | 等待图标 2 |
| `\` | 1 | 转义（下一字符按字面） |

实测统计（13513 条）：
`$` 113 次（111 条）、`~` 136 次（135 条）、`"` 305 次、`(` 18 次、`)` 10 次。
`$`/`~` 总在行首或行尾，例：
```
#0  "$10李～逍～遥，李～逍～遥！~30"
#2  "$02哇哇！作恶多端的罗刹鬼婆~40"
#4  "  要杀要剐不用多说！~60"
#11 "\"双手抱胸，物品无法送出去\""
```

## 3. msg_zh.json 结构（Godot 可直接 JSON.parse_string）

```json
{
  "encoding": "gbk", "source": "M.msg + Sss.mkf#3", "count": 13513,
  "offsets_count": 13514,
  "messages": [
    {"i":0,"off":0,"n":30,
     "text":"$10李～逍～遥，李～逍～遥！~30",
     "plain":"李～逍～遥，李～逍～遥！",
     "codes":[{"pos":0,"code":"$","arg":"10"},{"pos":15,"code":"~","arg":"3"}]},
    ...
  ]
}
```
- `i` = 消息号（脚本/SSS 引用的消息下标，0 基）；`off`/`n` = 在 M.msg 中的字节偏移/长度。
- `text` = GBK 解码后的**原文**（保留 `$`/`~` 控制码），Godot 按 §2 自行解释。
- `plain` = 去掉控制码后的纯文本（方便检索/预览）。
- `codes` = 控制码出现位置（`pos` 为字符下标，`arg` 为参数数字或空）。

Godot 解释示例（GDScript 伪代码）：
```gdscript
func parse_line(s: String) -> Dictionary:
    var out := ""; var delay := 3; var i := 0
    while i < s.length():
        var c := s[i]
        if c == "$" and i+2 < s.length() and s.substr(i+1,2).is_valid_int():
            delay = int(s.substr(i+1,2)) * 10 / 7; i += 3
        elif c == "~" and i+1 < s.length() and s[i+1].is_valid_int():
            out += "\n"; i += 2                  # 行结束/等待
        elif c == "\"" or c == "@": i += 1       # 颜色切换
        elif c == "(" or c == ")": i += 1        # 图标
        else: out += c; i += 1
    return {"text": out, "delay": delay}
```

## 4. Word.dat（词条表，与 M.msg 配套）

`Word.dat` 5650 B = **565 × 10 B**，GBK，右补空格(0x20)，每个词条定长 10 字节。
索引与 OBJECT 编号对齐（0..564）：#0 空、#1 空、#2 "Exp"、#3 状态、#4 仙术、#5 物品、
#10 文钱、#36 李逍遥、#37 赵灵儿、#38 林月如、#40 巫后、#41 盖罗娇 …
完整 565 条见 `_rea_runtime/out/assets/misc_index.json` 的 `word.words`（工具 `tools/misc_decode.py`）。

## 5. 验证方式与产物

| 产物 | 路径 |
|---|---|
| JSON（13513 条，含 offset/原文/plain/控制码位置） | `_rea_runtime/out/assets/msg_zh.json` |
| 人眼校验样例（前 40 条） | `_rea_runtime/out/assets/msg_sample.txt` |
| Word.dat 词条 | `_rea_runtime/out/assets/misc_index.json` → `word` |
| 复跑 | `python tools/gen_msg_json.py` |

校验要点（脚本内 assert/打印）：
- `offsets[-1] == 224455 == os.path.getsize('M.msg')` ✔
- 13513 条全部解出，0 替换字符（修复后）✔
- 控制码计数与人工抽样（$ = 延时、~ = 等待）一致 ✔
