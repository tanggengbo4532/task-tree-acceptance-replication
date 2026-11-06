class_name PalData
extends RefCounted
## SSS.MKF 数据表 + 预处理后的对白文本。
##
## SSS 五块（[observation]，块长与结构逐一吻合）：
##   0  EVENTOBJECT[5077]   32B/条，16 个 WORD
##   1  SCENE[295]           8B/条：wMapNum / wScriptOnEnter / wScriptOnTeleport / wEventObjectIndex
##   2  OBJECT[]            14B/条（物品/魔法/敌人/毒/玩家描述符；WIN95 版 7 words）
##   3  消息偏移表          13514 × DWORD，指向 M.msg
##   4  SCRIPTENTRY[43557]   8B/条：wOperation + 3 个 WORD 操作数
##
## 注意：scenes / events 用 Array[int]（引用语义，可变、可跨模块共享），
## 因为脚本会原地修改事件对象（sdlpal 中 gpGlobals->g.lprgEventObject 就是活表）。

const SC_MAP := 0
const SC_SCRIPT_ON_ENTER := 1
const SC_SCRIPT_ON_TELEPORT := 2
const SC_EVENT_START := 3

const EO_VANISH := 0
const EO_X := 1
const EO_Y := 2
const EO_LAYER := 3
const EO_TRIGGER_SCRIPT := 4
const EO_AUTO_SCRIPT := 5
const EO_STATE := 6
const EO_TRIGGER_MODE := 7
const EO_SPRITE := 8
const EO_FRAMES := 9
const EO_DIRECTION := 10
const EO_CUR_FRAME := 11
const EO_IDLE_FRAME := 12
const EO_SPRITE_OFFSET := 13
const EO_FRAMES_AUTO := 14
const EO_IDLE_AUTO := 15

const SCENE_COUNT := 295
const EVENT_COUNT := 5077
const SCRIPT_COUNT := 43557
const MSG_COUNT := 13513

var scenes: Array = []            # Array[Array[int]]，每项 4 个 int
var events: Array = []            # Array[Array[int]]，每项 16 个 int（活表）
var objects_raw: PackedByteArray = PackedByteArray()
var scripts: PackedInt32Array = PackedInt32Array()
var msg_offsets: PackedInt32Array = PackedInt32Array()
var msgs: PackedStringArray = PackedStringArray()


func load_all(dir: String) -> bool:
	var sss := MkfFile.open_asset(dir, "Sss.mkf")
	if sss == null:
		return false
	if sss.chunk_count < 5:
		push_error("PalData: Sss.mkf 块数异常 %d" % sss.chunk_count)
		return false
	var b0 := sss.chunk(0)
	var b1 := sss.chunk(1)
	objects_raw = sss.chunk(2)
	var b3 := sss.chunk(3)
	var b4 := sss.chunk(4)

	if b0.size() != EVENT_COUNT * 32:
		push_warning("PalData: EVENTOBJECT 块长 %d（期望 %d）" % [b0.size(), EVENT_COUNT * 32])
	var ev_count := b0.size() / 32
	events = []
	for i in range(ev_count):
		var o := i * 32
		var a: Array = []
		a.resize(16)
		for k in range(16):
			a[k] = b0[o + k * 2] | (b0[o + k * 2 + 1] << 8)
		events.append(a)

	var sc_count := b1.size() / 8
	scenes = []
	for i in range(sc_count):
		var o := i * 8
		var a: Array = []
		a.resize(4)
		for k in range(4):
			a[k] = b1[o + k * 2] | (b1[o + k * 2 + 1] << 8)
		scenes.append(a)

	scripts.resize(b4.size() / 2)
	for i in range(scripts.size()):
		scripts[i] = b4[i * 2] | (b4[i * 2 + 1] << 8)

	msg_offsets.resize(b3.size() / 4)
	for i in range(msg_offsets.size()):
		var o := i * 4
		msg_offsets[i] = b3[o] | (b3[o + 1] << 8) | (b3[o + 2] << 16) | (b3[o + 3] << 24)

	_load_msgs()
	return true


func _load_msgs() -> void:
	var p := "res://data/msg_zh.json"
	if not FileAccess.file_exists(p):
		push_warning("PalData: 缺少 %s（先运行 tools/extract_msg.py）" % p)
		return
	var fa := FileAccess.open(p, FileAccess.READ)
	var txt := fa.get_as_text()
	fa.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("PalData: msg_zh.json 解析失败")
		return
	msgs = PackedStringArray(parsed)


## 场景表（1-based）；返回引用数组，可直接改。
func scene(index_1based: int) -> Array:
	var i := index_1based - 1
	if i < 0 or i >= scenes.size():
		return [0, 0, 0, 0]
	return scenes[i]


## 事件对象（1-based）；返回引用数组（活表）。
func event(index_1based: int) -> Array:
	var i := index_1based - 1
	if i < 0 or i >= events.size():
		return []
	return events[i]


func script_entry(entry: int) -> PackedInt32Array:
	var o := entry * 4
	var a := PackedInt32Array()
	a.resize(4)
	if o < 0 or o + 3 >= scripts.size():
		return a
	a[0] = scripts[o]
	a[1] = scripts[o + 1]
	a[2] = scripts[o + 2]
	a[3] = scripts[o + 3]
	return a


func msg(index: int) -> String:
	if index < 0 or index >= msgs.size():
		return ""
	return msgs[index]


## 去掉对白里的内嵌控制码：$nn 颜色、~nn 延时。
static func strip_control_codes(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "$" or ch == "~":
			i += 1
			while i < s.length() and s[i] >= "0" and s[i] <= "9":
				i += 1
			continue
		out += ch
		i += 1
	return out
