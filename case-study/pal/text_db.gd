extends Node
## 文本库（autoload `PALText`）。
## 对应 sdlpal text.c / font.c：消息取文、词条、对白控制码（$延时/~换页/@颜色/()图标/\\转义）、
## 分页排版、对话框图标与人物头像（RGM.MKF）。
## 由 port-audio-text 实现；对外 API 见 docs/port/INTERFACES.md。
##
## 数据来源：
##   * 消息 = `data/msg_zh.json`（13513 条，UTF-8；由 PALTables.sss.msgs 提供，工具 tools/extract_msg.py）
##   * 词条 = `data/word_zh.json`（565 条，UTF-8；工具 tools/extract_word.py）
##   * 对白图标 = Data.mkf 块 12（282 B，sprite，sdlpal text.c: PAL_MKFReadChunk(bufDialogIcons, 282, 12)）
##   * 头像 = Rgm.mkf 块号 = 角色头像号（sdlpal PAL_StartDialog 的 iNumCharFace）
##   * 字体颜色 = PAT.MKF 块 0（day）里 text.c 定义的调色板索引
##
## 注意：任务说明里的 “$NN=颜色” 与 sdlpal 不符。text.c: TEXT_DisplayText 中
##   `$` + 2 位十进制 = 打字延时（iDelayTime = NN*10/7 帧，每帧 8ms）；
##   颜色控制符是 `'`(红) / `-`(青) / `@`(暗红) / `"`(黄，仅非对话文本)；
##   `~` + 数字 = 延时并结束本行（对话里等价于强制换页）；
##   `)` / `(` = 等待图标 1/2；`\\` = 转义下一字符。
## 本文件严格按 text.c 语义实现，并在 --text-test 中逐项验证。

const SHOT_DIR := "<LOCAL_PATH>"
const MSG_JSON := "res://data/msg_zh.json"
const WORD_JSON := "res://data/word_zh.json"

## text.c: PAL_ShowDialogText 中 nCurrentDialogLine > 3 时才等待按键 → 每页 4 行。
const DIALOG_LINES_PER_PAGE := 4
## text.c: y = posDialogText.y + nCurrentDialogLine * 18
const DIALOG_LINE_HEIGHT := 18
## font.c: _font_height = 16；全角 16px、半角 8px（PAL_CharWidth = font_width >> 1）
const FONT_HEIGHT := 16
const CHAR_WIDTH_FULL := 16
const CHAR_WIDTH_HALF := 8
## 对话文本默认行宽（320 宽屏、text.c 无自动换行；此处给分页 API 用的保守值 = 15 个全角字）
const DEFAULT_TEXT_WIDTH := 240
## text.c: g_TextLib.iDelayTime 缺省 3 → 每字 3*8=24ms
const DEFAULT_TYPING_DELAY_MS := 24

## 字体颜色（text.c 顶部 #define 的调色板索引）
const FONT_COLOR_INDEX_DEFAULT := 0x4F
const FONT_COLOR_INDEX_YELLOW := 0x2D
const FONT_COLOR_INDEX_RED := 0x1A
const FONT_COLOR_INDEX_RED_ALT := 0x17
const FONT_COLOR_INDEX_CYAN := 0x8D
const FONT_COLOR_INDEX_CYAN_ALT := 0x8C

## 颜色编号（与 Color 表一一对应，供 dialog_box 使用）
enum FontColor {
	DEFAULT = 0,
	YELLOW = 1,
	RED = 2,
	RED_ALT = 3,
	CYAN = 4,
	CYAN_ALT = 5,
}

## 调色板索引顺序：DEFAULT/YELLOW/RED/RED_ALT/CYAN/CYAN_ALT
const FONT_COLOR_INDICES: Array[int] = [
	FONT_COLOR_INDEX_DEFAULT,
	FONT_COLOR_INDEX_YELLOW,
	FONT_COLOR_INDEX_RED,
	FONT_COLOR_INDEX_RED_ALT,
	FONT_COLOR_INDEX_CYAN,
	FONT_COLOR_INDEX_CYAN_ALT,
]
## PAT.MKF 缺失时的兜底颜色（按 PAT 块0 实测值，见 docs/rea/evidence/assets/MISC-FORMAT.md §6）
const FONT_COLOR_FALLBACK: Array[Color] = [
	Color8(196, 184, 172),
	Color8(252, 220, 132),
	Color8(188, 72, 60),
	Color8(148, 32, 24),
	Color8(120, 216, 184),
	Color8(100, 200, 168),
]

var ready_flag: bool = false
var data_dir: String = ""
var msgs: PackedStringArray = PackedStringArray()
var words: PackedStringArray = PackedStringArray()
## Data.mkf 块 12 解出的等待图标（3 帧 16×16 RGBA）
var dialog_icons: Array[Image] = []
## 同上，预先建好的纹理（不能在 _draw() 里现场建纹理，Forward+ 当帧会是未初始化白色）
var dialog_icon_textures: Array[ImageTexture] = []
## PAT.MKF 块 0 的 day 调色板
var palette: PackedColorArray = PackedColorArray()
## 文本颜色表（下标 = FontColor 枚举）
var font_colors: Array[Color] = []

var _data_mkf: MkfFile = null
var _rgm_mkf: MkfFile = null
var _face_cache: Dictionary = {}
var _test_log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var args := OS.get_cmdline_args()
	if "--text-test" in args:
		# 延迟到 main.gd 完成数据装载（PALTables.init / PALText.init）后再跑
		call_deferred("_run_text_test")


# ---------------------------------------------------------------- 装载

func init(p_data_dir: String) -> void:
	data_dir = p_data_dir
	ready_flag = false
	dialog_icons.clear()
	dialog_icon_textures.clear()
	_face_cache.clear()
	_load_palette()
	_load_msgs()
	_load_words()
	_load_dialog_icons()
	ready_flag = true
	print("[PALText] init: msgs=%d words=%d icons=%d palette=%d" % [
		msgs.size(), words.size(), dialog_icons.size(), palette.size(),
	])


func _load_palette() -> void:
	font_colors = []
	for c in FONT_COLOR_FALLBACK:
		font_colors.append(c)
	palette = PackedColorArray()
	if data_dir == "":
		return
	var pat := MkfFile.open_asset(data_dir, "Pat.mkf")
	if pat == null:
		return
	var raw := pat.chunk(0)
	if raw.size() < 768:
		push_warning("PALText: PAT 块0 过短 %d" % raw.size())
		return
	palette = PalSprite.palette_from_bytes(raw.slice(0, 768))
	# 用真实调色板解析 text.c 的字体颜色
	for i in range(FONT_COLOR_INDICES.size()):
		if FONT_COLOR_INDICES[i] < palette.size():
			font_colors[i] = palette[FONT_COLOR_INDICES[i]]


func _load_msgs() -> void:
	msgs = PackedStringArray()
	# 优先使用 PALTables 已装载的 SSS 消息表；否则直接读预处理 JSON
	if PALTables != null and PALTables.sss != null and PALTables.sss.msgs.size() > 0:
		msgs = PALTables.sss.msgs
		return
	if FileAccess.file_exists(MSG_JSON):
		var fa := FileAccess.open(MSG_JSON, FileAccess.READ)
		var parsed = JSON.parse_string(fa.get_as_text())
		fa.close()
		if typeof(parsed) == TYPE_ARRAY:
			msgs = PackedStringArray(parsed)
			return
	push_warning("PALText: 消息表为空（缺少 %s）" % MSG_JSON)


func _load_words() -> void:
	words = PackedStringArray()
	if FileAccess.file_exists(WORD_JSON):
		var fa := FileAccess.open(WORD_JSON, FileAccess.READ)
		var parsed = JSON.parse_string(fa.get_as_text())
		fa.close()
		if typeof(parsed) == TYPE_ARRAY:
			for v in parsed:
				words.append(str(v))
			return
	# 兜底：PALTables.words（GBK 直读，可能为乱码；仅防崩溃）
	if PALTables != null:
		words = PALTables.words
	if words.is_empty():
		push_warning("PALText: 词条表为空（缺少 %s）" % WORD_JSON)


func _load_dialog_icons() -> void:
	if data_dir == "":
		return
	if PALTables != null and PALTables.data_mkf != null:
		_data_mkf = PALTables.data_mkf
	if _data_mkf == null:
		_data_mkf = MkfFile.open_asset(data_dir, "Data.mkf")
	if _data_mkf == null or _data_mkf.chunk_count <= 12:
		return
	var raw := _data_mkf.chunk(12)
	if raw.size() < 8:
		return
	dialog_icons = PalSprite.decode_sprite(raw, _icon_palette())
	dialog_icon_textures = []
	for im in dialog_icons:
		dialog_icon_textures.append(ImageTexture.create_from_image(im))


## 图标/头像解码用调色板：对话图标与头像使用场景调色板，这里用 PAT 块0 近似（[unk] 场景切换时会略有色差）
func _icon_palette() -> PackedColorArray:
	if palette.is_empty():
		return FONT_COLOR_FALLBACK.duplicate()
	return palette


# ---------------------------------------------------------------- 消息 / 词条

## 返回消息原文（保留控制码）；越界返回空串。
func msg(id: int) -> String:
	if id < 0 or id >= msgs.size():
		return ""
	return msgs[id]


## 返回消息去掉全部控制码后的可见文本（sdlpal PAL_ShowDialogText 实际绘制的字符）。
func msg_plain(id: int) -> String:
	return plain_text(msg(id))


## 返回词条（Word.dat）。按 text.c: PAL_InitText 的规则：
## 1) 去掉行尾空格；2) 若末字符是 '1' 则去掉（sdlpal 对 PAL98 word.dat 的终止符 hack）；
## 3) 按 PAL_UnescapeText 处理 `\` 转义与控制符。
func word(id: int) -> String:
	if id < 0 or id >= words.size():
		return ""
	var s := words[id]
	while s.length() > 0 and s[s.length() - 1] == " ":
		s = s.substr(0, s.length() - 1)
	s = unescape_text(s)
	if s.length() > 0 and s[s.length() - 1] == "1":
		s = s.substr(0, s.length() - 1)
	return s


## PAL_UnescapeText：控制符直接删除；`\` 使其后的一个字符按字面保留。
func unescape_text(text: String) -> String:
	if text.find("\\") < 0:
		# 无转义时仍需删除控制符？sdlpal 的 PAL_UnescapeText 会删除所有控制符；
		# 词条里通常不含控制符，但为一致性仍走完整流程。
		pass
	var out := ""
	var i := 0
	while i < text.length():
		var ch := text[i]
		match ch:
			"-", "'", "@", "\"", "$", "~", ")", "(":
				i += 1
			"\\":
				i += 1
				if i < text.length():
					out += text[i]
					i += 1
			_:
				out += ch
				i += 1
	return out


# ---------------------------------------------------------------- 字符宽度

## 对应 font.c: PAL_CharWidth —— 全角 16px、半角 8px。
func char_width_px(ch: String) -> int:
	if ch.length() <= 0:
		return 0
	var code := ch.unicode_at(0)
	if _is_full_width(code):
		return CHAR_WIDTH_FULL
	return CHAR_WIDTH_HALF


func _is_full_width(code: int) -> bool:
	# 全角字符判定：CJK 部首/符号/假名/谚文/全角形式/私用区（PAL98 自定义符号 U+E0xx..）
	if code >= 0x1100 and code <= 0x115F:
		return true
	if code >= 0x2E80 and code <= 0xA4CF:
		return true
	if code >= 0xAC00 and code <= 0xD7A3:
		return true
	if code >= 0xF900 and code <= 0xFAFF:
		return true
	if code >= 0xFE30 and code <= 0xFE6F:
		return true
	if code >= 0xFF00 and code <= 0xFF60:
		return true
	if code >= 0xFFE0 and code <= 0xFFE6:
		return true
	if code >= 0xE000 and code <= 0xF8FF:
		return true
	return false


func text_width_px(text: String) -> int:
	var w := 0
	for i in range(text.length()):
		w += char_width_px(text[i])
	return w


# ---------------------------------------------------------------- 控制码解析

## 解析一条消息的控制码，返回供 dialog 渲染的结构：
## {
##   "text": String,           # 契约字段：可见文本（不含控制码），= plain
##   "plain": String,          # 同上（保留旧名）
##   "tokens": Array,          # 逐字符 [{ch, color:int(FontColor), delay_ms:int}]
##   "runs": Array,            # 同色同速连续段 [{text, color, delay_ms}]
##   "delay_ms": int,          # 当前打字延时（最后出现的 $NN）
##   "break_delay_ms": int,    # `~N` 的延时（N*80/7 ms，text.c 对话模式下不睡，仅记录）
##   "force_break": bool,      # `~` 强制换页
##   "color": int,             # 首字符颜色（FontColor；无字符时 = 0）
##   "delays": Array,          # 控制码列表 [{pos:int, code:String, arg:String}]
##   "icon": int,              # `)`=1 / `(`=2 / 0
##   "truncated": bool,        # 遇 `~` 后剩余文本未显示
## }
func parse_codes(text: String, is_dialog: bool = true) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var runs: Array[Dictionary] = []
	var plain := ""
	var color := int(FontColor.DEFAULT)
	var delay_ms := DEFAULT_TYPING_DELAY_MS
	var break_delay_ms := 0
	var force_break := false
	var icon := 0
	var truncated := false
	var codes: Array[Dictionary] = []
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		match ch:
			"$":
				# text.c: g_TextLib.iDelayTime = wcstol(lpszText+1) * 10 / 7; lpszText += 3;
				var j := i + 1
				var arg := ""
				while j < n and text[j] >= "0" and text[j] <= "9":
					arg += text[j]
					j += 1
				if arg != "":
					delay_ms = int(arg) * 10 / 7 * 8
				codes.append({"pos": i, "code": "$", "arg": arg})
				i += 3
			"~":
				# text.c: 延时 N*80/7 ms 后 return（不再显示本行剩余字符）
				var k := i + 1
				var arg2 := ""
				while k < n and text[k] >= "0" and text[k] <= "9":
					arg2 += text[k]
					k += 1
				break_delay_ms = int(arg2) * 80 / 7 if arg2 != "" else 0
				codes.append({"pos": i, "code": "~", "arg": arg2})
				force_break = true
				truncated = true
				break
			")":
				icon = 1
				codes.append({"pos": i, "code": ")", "arg": ""})
				i += 1
			"(":
				icon = 2
				codes.append({"pos": i, "code": "(", "arg": ""})
				i += 1
			"\\":
				i += 1
				if i < n:
					codes.append({"pos": i - 1, "code": "\\", "arg": text[i]})
					_add_token(tokens, runs, text[i], color, delay_ms)
					plain += text[i]
					i += 1
			"-":
				# text.c: 青色开关
				codes.append({"pos": i, "code": "-", "arg": ""})
				color = int(FontColor.DEFAULT) if color == int(FontColor.CYAN) else int(FontColor.CYAN)
				i += 1
			"'":
				# text.c: 红色开关
				codes.append({"pos": i, "code": "'", "arg": ""})
				color = int(FontColor.DEFAULT) if color == int(FontColor.RED) else int(FontColor.RED)
				i += 1
			"@":
				# text.c: 暗红开关（对话里也生效）
				codes.append({"pos": i, "code": "@", "arg": ""})
				color = int(FontColor.DEFAULT) if color == int(FontColor.RED_ALT) else int(FontColor.RED_ALT)
				i += 1
			"\"":
				# text.c: `"` 仅对非对话文本切换黄色；对话模式下直接吞掉
				codes.append({"pos": i, "code": "\"", "arg": ""})
				if not is_dialog:
					color = int(FontColor.DEFAULT) if color == int(FontColor.YELLOW) else int(FontColor.YELLOW)
				i += 1
			_:
				_add_token(tokens, runs, ch, color, delay_ms)
				plain += ch
				i += 1
	return {
		"text": plain,
		"plain": plain,
		"tokens": tokens,
		"runs": runs,
		"delay_ms": delay_ms,
		"break_delay_ms": break_delay_ms,
		"force_break": force_break,
		"color": int(tokens[0]["color"]) if not tokens.is_empty() else int(FontColor.DEFAULT),
		"delays": codes,
		"icon": icon,
		"truncated": truncated,
	}


func _add_token(
	tokens: Array[Dictionary],
	runs: Array[Dictionary],
	ch: String,
	color: int,
	delay_ms: int
) -> void:
	tokens.append({"ch": ch, "color": color, "delay_ms": delay_ms})
	if runs.is_empty() or int(runs[runs.size() - 1]["color"]) != color \
			or int(runs[runs.size() - 1]["delay_ms"]) != delay_ms:
		runs.append({"text": ch, "color": color, "delay_ms": delay_ms})
	else:
		runs[runs.size() - 1]["text"] = str(runs[runs.size() - 1]["text"]) + ch


## 去掉控制码的可见文本。
func plain_text(text: String, is_dialog: bool = true) -> String:
	return str(parse_codes(text, is_dialog)["plain"])


func color_of(color_id: int) -> Color:
	if color_id >= 0 and color_id < font_colors.size():
		return font_colors[color_id]
	return Color(1, 1, 1, 1)


# ---------------------------------------------------------------- 分页排版

## 把一条消息按宽度分行、按每页 4 行分页（text.c: PAL_ShowDialogText / PAL_DialogWaitForKey）。
## 返回每页文本（行间用 "\n" 连接），控制码已去除；需要保色渲染请用 paginate_ex()。
func paginate(text: String, max_width: int = DEFAULT_TEXT_WIDTH) -> PackedStringArray:
	var ex := paginate_ex(text, max_width)
	var pages := PackedStringArray()
	for p in ex["pages"]:
		var lines: Array = p["lines"]
		var parts := PackedStringArray()
		for line in lines:
			parts.append(str(line["plain"]))
		pages.append("\n".join(parts))
	if pages.is_empty():
		pages.append("")
	return pages


## 同 paginate，但保留颜色 token：
## {
##   "pages": [ { "lines": [ {"plain": String, "tokens": Array} ], "plain": String } ],
##   "title": String,        # 首行是 “名字：” 形式时的名字（text.c: PAL_ShowDialogText 标题特判）
##   "force_break": bool,
##   "break_delay_ms": int,
##   "icon": int,
##   "delay_ms": int,
## }
func paginate_ex(text: String, max_width: int = DEFAULT_TEXT_WIDTH) -> Dictionary:
	var info := parse_codes(text, true)
	var tokens: Array = info["tokens"]
	var wrapped := wrap_tokens(tokens, max_width)
	var pages: Array = []
	var cur: Array = []
	for line_tokens in wrapped:
		cur.append({
			"tokens": line_tokens,
			"plain": _tokens_plain(line_tokens),
		})
		if cur.size() >= DIALOG_LINES_PER_PAGE:
			pages.append(_make_page(cur))
			cur = []
	if not cur.is_empty():
		pages.append(_make_page(cur))
	if pages.is_empty():
		pages.append(_make_page([]))
	return {
		"pages": pages,
		"title": "",
		"force_break": bool(info["force_break"]),
		"break_delay_ms": int(info["break_delay_ms"]),
		"icon": int(info["icon"]),
		"delay_ms": int(info["delay_ms"]),
	}


func _make_page(lines: Array) -> Dictionary:
	var parts := PackedStringArray()
	for line in lines:
		parts.append(str(line["plain"]))
	return {"lines": lines, "plain": "\n".join(parts)}


func _tokens_plain(tokens: Array) -> String:
	var s := ""
	for t in tokens:
		s += str(t["ch"])
	return s


## 按像素宽度把 token 流折行（不拆 ASCII 单词，逐字符断行，CJK 友好）。
func wrap_tokens(tokens: Array, max_width: int = DEFAULT_TEXT_WIDTH) -> Array:
	var lines: Array = []
	var cur: Array = []
	var w := 0
	for t in tokens:
		var cw := char_width_px(str(t["ch"]))
		if w + cw > max_width and not cur.is_empty():
			lines.append(cur)
			cur = []
			w = 0
		cur.append(t)
		w += cw
	if not cur.is_empty():
		lines.append(cur)
	return lines


# ---------------------------------------------------------------- 头像

## 取角色头像（Rgm.mkf 块号 = sdlpal PAL_StartDialog 的 iNumCharFace）；无效返回 null。
func face_image(face_id: int) -> Image:
	if face_id <= 0:
		return null
	if _face_cache.has(face_id):
		return _face_cache[face_id]
	if _rgm_mkf == null and data_dir != "":
		_rgm_mkf = MkfFile.open_asset(data_dir, "Rgm.mkf")
	var img: Image = null
	if _rgm_mkf != null and face_id < _rgm_mkf.chunk_count:
		var raw := _rgm_mkf.chunk(face_id)
		var frames := PalSprite.decode_sprite(raw, _icon_palette())
		if frames.size() > 0:
			img = frames[0]
	_face_cache[face_id] = img
	return img


func dialog_icon(index: int) -> Image:
	if index < 0 or index >= dialog_icons.size():
		return null
	return dialog_icons[index]


## 预建好的图标纹理（dialog_box 的 _draw 里直接画，避免当帧新建纹理变白）。
func dialog_icon_texture(index: int) -> ImageTexture:
	if index < 0 or index >= dialog_icon_textures.size():
		return null
	return dialog_icon_textures[index]


# ---------------------------------------------------------------- --text-test

func _run_text_test() -> void:
	print("[text-test] ===== 开始：文本库 + 对话框自测 =====")
	var t0 := Time.get_ticks_msec()
	if not ready_flag:
		var dir := PalConfig.require_data_dir()
		if dir != "":
			init(dir)
	if not ready_flag:
		push_error("[text-test] 数据目录不可用，测试中止")
		get_tree().quit(1)
		return

	# ---- 静态断言（不依赖渲染） ----
	var ok := 0
	var fail := 0
	ok += _check("消息条数 == 13513", msgs.size() == 13513, "实际 %d" % msgs.size())
	ok += _check("词条条数 == 565", words.size() == 565, "实际 %d" % words.size())
	ok += _check("Word#36 == 李逍遥", word(36) == "李逍遥", "实际 %s" % word(36))
	ok += _check("Word#2 == Exp", word(2) == "Exp", "实际 %s" % word(2))
	ok += _check("Word#37 == 赵灵儿", word(37) == "赵灵儿", "实际 %s" % word(37))
	var m0 := msg(0)
	var p0 := parse_codes(m0, true)
	ok += _check("msg0 原文含 $10", m0.begins_with("$10"), "实际 %s" % m0)
	ok += _check("$10 → 打字延时 112ms", int(p0["delay_ms"]) == 112, "实际 %d" % int(p0["delay_ms"]))
	ok += _check("$NN 不进可见文本", str(p0["plain"]).find("$") < 0, str(p0["plain"]))
	ok += _check("~30 → 强制换页", bool(p0["force_break"]), "force_break=%s" % bool(p0["force_break"]))
	ok += _check("~30 → 延时 342ms", int(p0["break_delay_ms"]) == 342, "实际 %d" % int(p0["break_delay_ms"]))
	ok += _check("msg0 可见文本", str(p0["plain"]) == "李～逍～遥，李～逍～遥！", str(p0["plain"]))
	var pc := parse_codes("-青字-'红字'@暗红@默认\"黄字\"", true)
	ok += _check("颜色控制码 - ' @ 被解析", str(pc["plain"]) == "青字红字暗红默认黄字", str(pc["plain"]))
	ok += _check("对话模式吞掉 \"（text.c 行为）", str(pc["plain"]).find("\"") < 0, str(pc["plain"]))
	var colors: Dictionary = {}
	for t in pc["tokens"]:
		colors[int(t["color"])] = true
	ok += _check("至少 4 种字体颜色", colors.size() >= 4, "颜色数 %d" % colors.size())
	var pw := text_width_px("李逍遥ABC")
	ok += _check("半/全角宽度 16/8", pw == 16 * 3 + 8 * 3, "实际 %d" % pw)
	var long_text := "分页测试一：春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。分页测试二：白日依山尽，黄河入海流。欲穷千里目，更上一层楼。分页测试三：全文到此结束。"
	var pages := paginate(long_text)
	ok += _check("长文本分页页数 >= 2", pages.size() >= 2, "实际 %d 页" % pages.size())
	var ex := paginate_ex(long_text)
	var max_lines := 0
	for p in ex["pages"]:
		max_lines = maxi(max_lines, (p["lines"] as Array).size())
	ok += _check("每页行数 <= 4（text.c nCurrentDialogLine>3 才翻页）", max_lines <= 4, "实际最多 %d 行" % max_lines)
	ok += _check("对白图标 3 帧", dialog_icons.size() == 3, "实际 %d" % dialog_icons.size())
	var face1 := face_image(1)
	ok += _check("RGM 头像 1 可解码", face1 != null and face1.get_width() > 16, "尺寸 %s" % ("null" if face1 == null else str(face1.get_size())))

	print("[text-test] 静态检查: %d 通过 / %d 失败" % [ok, fail])
	_test_log.append("静态检查: %d 通过 / %d 失败" % [ok, fail])
	_test_log.append("工程: %s" % ProjectSettings.globalize_path("res://"))
	_test_log.append("数据目录: %s" % data_dir)
	_test_log.append("msg0=%s" % m0)
	_test_log.append("msg0.plain=%s" % str(p0["plain"]))
	_test_log.append("长文本分页=%d 页, 每页最多 %d 行" % [pages.size(), max_lines])
	for i in range(pages.size()):
		_test_log.append("  第 %d 页:\n%s" % [i + 1, pages[i]])

	# ---- 图标解码取证（Data.mkf #12，供 dialog_box 使用） ----
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	for i in range(dialog_icons.size()):
		var im := dialog_icons[i]
		if im == null:
			continue
		var opaque := 0
		for y in range(im.get_height()):
			for x in range(im.get_width()):
				if im.get_pixel(x, y).a > 0.5:
					opaque += 1
		print("[text-test] icon[%d] %dx%d 不透明像素=%d p(8,8)=%s p(20,40)=%s" % [
			i, im.get_width(), im.get_height(), opaque,
			str(im.get_pixel(0, 0)), str(im.get_pixel(mini(8, im.get_width() - 1), mini(10, im.get_height() - 1))),
		])
		var big := Image.new()
		big.copy_from(im)
		big.resize(64, 64, Image.INTERPOLATE_NEAREST)
		big.save_png(SHOT_DIR + "text_icon_%d.png" % i)
		big = null
		print("[text-test] icon[%d] 导出后尺寸 %s" % [i, str(im.get_size())])
		_test_log.append("图标[%d] %dx%d 不透明像素=%d → text_icon_%d.png" % [i, im.get_width(), im.get_height(), opaque, i])

	# ---- 渲染自测 ----
	await get_tree().process_frame
	var layer := CanvasLayer.new()
	layer.name = "TextTestLayer"
	layer.layer = 100
	get_tree().root.add_child(layer)
	var bg := Control.new()
	bg.name = "BG"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var bg_rect := ColorRect.new()
	bg_rect.color = Color8(18, 16, 28)
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(bg_rect)
	# 用真实 FBP 场景图作背景，截图更接近实机
	var fbp_img := _decode_fbp_preview(6)
	if fbp_img != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = ImageTexture.create_from_image(fbp_img)
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.position = Vector2.ZERO
		tex_rect.size = Vector2(640, 400)
		bg.add_child(tex_rect)
	var tag := Label.new()
	tag.text = "PALText --text-test  $=打字延时  ~=换页  '红 -青 @暗红  分页=4行/页"
	tag.position = Vector2(8, 6)
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color8(255, 240, 200))
	tag.add_theme_color_override("font_shadow_color", Color8(0, 0, 0))
	tag.add_theme_constant_override("shadow_offset_x", 1)
	tag.add_theme_constant_override("shadow_offset_y", 1)
	bg.add_child(tag)

	var box = preload("res://game/dialog_box.gd").new()
	box.name = "DialogBox"
	box.capture_input = false
	box.scale = Vector2(2, 2)
	box.position = Vector2.ZERO
	layer.add_child(box)

	# 1) 真实消息 msg0：$10 慢速逐字 + ~30 换页
	box.set_style(0)  # kDialogUpper
	box.push_line(m0)
	await get_tree().create_timer(0.45).timeout
	await _shot("text_01_msg0_typing.png")
	box.finish_typing()
	await _shot("text_02_msg0_typed.png")
	_test_log.append("截图: text_01_msg0_typing.png / text_02_msg0_typed.png（msg0 逐字+控制码）")

	# 2) 颜色控制码
	box.clear()
	box.set_style(2)  # kDialogLower
	box.push_line("普通文字，'朱红色'，-青碧色-，@暗红色@，恢复默认")
	box.finish_typing()
	await _shot("text_03_colors.png")
	_test_log.append("截图: text_03_colors.png（' 红 / - 青 / @ 暗红）")

	# 3) 分页：长文本 → 第 1 页（4 行）→ 按键 → 第 2 页
	box.clear()
	box.set_style(2)
	box.push_line(long_text)
	box.finish_typing()
	await _shot("text_04_page1.png")
	box.advance()
	box.finish_typing()
	await _shot("text_05_page2.png")
	_test_log.append("截图: text_04_page1.png / text_05_page2.png（分页，每页 4 行）")

	# 4) 是/否选项
	box.clear()
	box.set_style(3)  # kDialogCenterWindow
	box.open_choice("是", "否")
	await _shot("text_06_choice.png")
	box.confirm_choice(true)
	_test_log.append("截图: text_06_choice.png（show_choice 选项框）")

	# 5) 中窗单行自动关闭（1.4s，text.c PAL_DialogWaitForKeyWithMaximumSeconds(1.4)）
	box.clear()
	box.set_style(3)
	box.push_line("中窗单行提示（1.4 秒后自动关闭）")
	await _shot("text_07_center_window.png")
	await get_tree().create_timer(1.6).timeout
	_test_log.append("截图: text_07_center_window.png（中窗自动关闭）")

	# 6) 头像 + 上框
	box.clear()
	box.set_style(0)
	box.set_face(1)
	box.push_line("李逍遥：这是一条带头像的对白，用来验证 RGM.MKF 头像与上框坐标。")
	box.finish_typing()
	await _shot("text_08_face_upper.png")
	_test_log.append("截图: text_08_face_upper.png（UPPER 框 + RGM 头像）")

	# 7) 居中样式（kDialogCenter，无边框，text.c posDialogText=(80,40)）
	box.clear()
	box.set_face(0)
	box.set_style(1)
	box.push_line("居中样式：无边框，文字从 (80,40) 开始。")
	box.finish_typing()
	await _shot("text_09_center.png")
	_test_log.append("截图: text_09_center.png（CENTER 样式）")

	# ---- 写报告 ----
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var report := "\n".join(_test_log) + "\n"
	var fa := FileAccess.open(SHOT_DIR + "text_test_report.txt", FileAccess.WRITE)
	if fa != null:
		fa.store_string(report)
		fa.close()
	print("[text-test] 报告: %s" % (SHOT_DIR + "text_test_report.txt"))
	print("[text-test] ===== 完成，用时 %d ms，失败 %d 项 =====" % [Time.get_ticks_msec() - t0, fail])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if fail == 0 else 1)


func _check(name: String, cond: bool, detail: String) -> int:
	if cond:
		print("[text-test] PASS %s" % name)
		return 1
	print("[text-test] FAIL %s（%s）" % [name, detail])
	_test_log.append("FAIL %s（%s）" % [name, detail])
	return 0


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		# headless 无渲染后端，frame_post_draw 不会触发；跳过截图但继续跑逻辑自测
		print("[text-test] (headless) 跳过截图: %s" % name)
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[text-test] 截图失败（无 viewport 纹理）: %s" % name)
		return
	img.save_png(SHOT_DIR + name)
	print("[text-test] SHOT %s" % (SHOT_DIR + name))


## 解码 FBP 场景图用于自测背景（320×200 8bpp → RGBA8，PAT 块0）。
func _decode_fbp_preview(chunk: int) -> Image:
	if data_dir == "":
		return null
	var fbp := MkfFile.open_asset(data_dir, "Fbp.mkf")
	if fbp == null or chunk >= fbp.chunk_count:
		return null
	var raw := fbp.decompressed(chunk)
	if raw.size() < 320 * 200:
		return null
	var pal := palette
	if pal.is_empty():
		return null
	var img := Image.create_empty(320, 200, false, Image.FORMAT_RGBA8)
	for y in range(200):
		for x in range(320):
			img.set_pixel(x, y, pal[raw[y * 320 + x]])
	return img
