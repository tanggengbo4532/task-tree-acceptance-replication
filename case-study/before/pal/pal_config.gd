class_name PalConfig
extends RefCounted
## PAL98 数据目录定位。
##
## 证据：目标游戏的原始数据文件（Sss.mkf / Map.mkf / Mgo.mkf / M.msg ...）
## 属于运行期外部资源，不复制进工程；工程只保存由 tools/ 预处理出来的
## UTF-8 文本（msg_zh.json）。目录按优先级探测，第一个包含 Sss.mkf 的目录生效。

const CANDIDATES: Array[String] = [
	"<LOCAL_PATH>",
	"<LOCAL_PATH>",
	"res://data/game/",
]

const REQUIRED_FILES: Array[String] = ["Sss.mkf", "Map.mkf", "Mgo.mkf", "Gop.mkf", "Pat.mkf", "M.msg"]

static var _resolved: String = ""


## 返回数据目录（带结尾斜杠），找不到返回空串。
static func data_dir() -> String:
	if _resolved != "":
		return _resolved
	for dir in CANDIDATES:
		if _has_all(dir):
			_resolved = dir
			return dir
	return ""


static func _has_all(dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		return false
	for f in REQUIRED_FILES:
		if not FileAccess.file_exists(dir + f):
			return false
	return true


static func require_data_dir() -> String:
	var dir := data_dir()
	if dir == "":
		push_error("PalConfig: 未找到仙剑98数据目录，候选: %s" % [CANDIDATES])
	return dir
