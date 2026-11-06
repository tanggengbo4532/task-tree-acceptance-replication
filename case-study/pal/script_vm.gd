class_name ScriptVM
extends RefCounted
## SSS 事件脚本虚拟机 —— 移植 sdlpal `script.c`：
##   PAL_RunTriggerScript（0x0000-0x000A / 0x003B-0x003E / 0x008E / 0xFFFF）
## + PAL_InterpretInstruction 的完整 switch（0x000B-0x00A6）。
##
## 指令 = 4 个 WORD：wOperation + rgwOperand[0..2]（0 与 0xFFFF 在多数指令里表示“无”）。
## 运行模型：world 每帧调用 tick()，VM 连续执行指令直到遇到等待点
## （对白按键 / 等待帧 / NPC·队伍移动 / 战斗 / 菜单 / RNG / 是·否选择 / 等按键）后返回，
## 由 world 的每帧 tick 与回调继续推进。渲染、输入、音频全部通过 world / PALState / PALAudio。
##
## ============================ 操作码实现表 ============================
## 依据：sdlpal script.c（`[sd]`）；本移植的推断/近似（`[inf]`）；需要战斗系统协作（`[bt]`）；
## 需要 UI 系统协作（`[ui]`）。
##
## 控制流：
##   0x0000 [sd] 停止（不返回入口）           0x0001 [sd] 停止并设下一入口=下一行
##   0x0002 [sd] 空闲帧计数未到→下一入口=op0   0x0003 [sd] 无条件跳转（受 op1 空闲帧计数）
##   0x0004 [sd] 调用子脚本（op0 入口，op1 事件对象，0=沿用）   0x0005 [sd] 重绘（op1×60ms 等待）
##   0x0006 [sd] 按百分比随机跳转 op1          0x0007 [bt+ui] 战斗（结果分支 op1 失败/op2 逃跑）
##   0x0008 [sd] 设下一入口=下一行并继续       0x0009 [sd] 等待 op0 帧（op1 每帧更新队伍动画）
##   0x000A [ui] 是/否选择（“否”跳到 op0，默认“是”）
## 事件对象/队伍（NPC 移动见 pal/npc_move.gd）：
##   0x000B-0x000E [sd] 事件对象朝对应方向走一步（方向 = op-0xB）
##   0x000F [sd] 设事件对象朝向/手势（0xFFFF=不改）
##   0x0010 [sd] 事件对象直线走到 tile(op0,op1,h=op2)，speed 3，等待到达
##   0x0011 [sd] 同上 speed 2，隔帧移动，等待到达
##   0x0012 [sd] 事件对象位置设为「队伍位置 + (op1,op2)」
##   0x0013 [sd] 事件对象位置设为像素 (op1,op2)
##   0x0014 [sd] 事件对象手势 = op0（朝南）
##   0x0015 [sd] 队伍朝向/帧：dir=op0 frame=op1 partyIdx=op2
##   0x0016 [sd] op0 非 0 时设 pCurrent 朝向/手势 = op1/op2
##   0x006C [sd] 事件对象位移 (s16 op1, s16 op2) 后走一步（动画）
##   0x006E [sd] 队伍平移 (s16 op0, s16 op1)，层级 op2*8
##   0x006F [sd] pCurrent 状态 == s16 op1 时同步 pEvtObj 状态
##   0x0070 [sd] 队伍走到 tile(op0,op1,op2)，speed 2，等待到达
##   0x007A/0x007B [sd] 同上 speed 4 / 8
##   0x007C [sd] 事件对象走到 tile，speed 4 隔帧，等待
##   0x007D [sd] 事件对象位移 (s16 op1, s16 op2)
##   0x007E [sd] 事件对象层级 = s16 op1
##   0x007F [sd] 视口：全 0 → 恢复正常；op2==0xFFFF → 瞬移到 tile(op0,op1)；否则逐帧平移 op2 次
##   0x0082 [sd] 事件对象走到 tile，speed 8，等待
##   0x0084 [sd] 把物品作为事件对象放到队伍前方（op1=状态；失败跳 op2）
##   0x0087 [sd] 事件对象动画走一步（speed 0）
##   0x003F/0x0044/0x0097 [sd] 队伍骑事件对象走到 tile，speed 2 / 4 / 8，等待
##   0x0040 [sd] 事件对象触发方式 = op1
##   0x004B [sd] 事件对象短暂消失（sVanishTime=-15）
##   0x0052 [sd] 隐藏事件对象 op0 帧（默认 800），状态取反
##   0x0098 [sd] 设置跟随者（op0/op1 为角色号；0=无）
##   0x009A [sd] 批量设置事件对象 [op0..op1] 状态 = op2
##   0x00A1 [sd] 所有队员位置归到队长位置
##   0x004C [sd] 怪物追击玩家（op0 距离默认 8 / op1 速度默认 4 / op2 穿墙），每帧一步
##   0x0062 [sd] 暂停追击 op0 帧（chase_range=0）   0x0063 [sd] 加速追击（chase_range=3）
##   0x0081 [sd] 玩家未面向事件对象 op0 则跳 op2（op1>0 时设置触发方式）
##   0x0083 [sd] 事件对象不在 pCurrent 的 op1 格范围内则跳 op2
##   0x008F [sd] 金钱减半
## 属性/背包/仙术（全部通过 PALState，含 Lead 未实现方法的等价兜底）：
##   0x0017 [sd] 装备效果属性表 [op0-0xB][op1*6+事件对象] = s16 op2
##   0x0018 [sd] 装备物品（op0-0xB 部位，op1 物品；自动换下旧物）
##   0x0019 [sd] 玩家属性 op0 += s16 op1（op2=0 用事件对象当角色，否则 op2-1）
##   0x001A [sd] 玩家属性 op0 = s16 op1（装备过程中写入装备效果表）
##   0x001B/0x001C/0x001D [sd] HP / MP / HP+MP 增减（op0!=0 全队）
##   0x001E [sd] 金钱 += s16 op0；不足时跳 op1
##   0x001F [sd] 加物品 op0 × s16 op1
##   0x0020 [sd] 减物品 op0 × op1；不足时跳 op2（并尝试卸下已装备的）
##   0x0022 [sd] 复活：HP=0 者 HP=MaxHP*op1/10，清毒清状态
##   0x0023 [sd] 卸下装备：角色 op0，全部或部位 op1-1
##   0x0025 [sd] 设事件对象触发脚本 = op1
##   0x002B/0x002C [sd] 按种类/等级为玩家解毒
##   0x002D [sd] 设置玩家状态 op0 × op1 回合
##   0x002F [sd] 移除玩家状态 op0
##   0x0030 [sd] 临时属性（装备效果表 kBodyPartExtra）= 基础值×s16 op1/100
##   0x0031 [sd] 临时战斗精灵（装备效果表 kBodyPartExtra.sprite_in_battle）
##   0x0055/0x0056 [sd] 学习/移除仙术（op1=0 用事件对象当角色，否则 op1-1）
##   0x0058 [sd] 物品 op0 数量 < s16 op1 → 跳 op2
##   0x005A [sd] 玩家 HP 减半（事件对象=角色）  0x005F [sd] 玩家 HP 归零
##   0x005D [sd] 玩家未中 op0 毒 → 跳 op1        0x0061 [sd] 玩家未中毒（等级≥0）→ 跳 op0
##   0x0074 [sd] 队伍未满血 → 跳 op0             0x0079 [sd] 队伍里有名字 op0 → 跳 op1
##   0x0086 [sd] 装备中物品 op0 数量 < op1(默认1) → 跳 op2
##   0x008D [sd] 玩家升级 op0 级
##   0x008B [sd] 更换调色板号 op0
##   0x0090 [sd] 写对象数据 rgObject[op0].rgwData[2+op2] = op1（补丁 SSS 块 2）
##   0x0057/0x0088 [bt] 按 MP/金钱设置仙术基础伤害
## 场景/画面/音频/系统：
##   0x0024 [sd] 设事件对象自动脚本 = op1
##   0x0026/0x0027 [ui] 商店 买/卖（op0=商店号）
##   0x0035 [ui] 屏幕震动（op0 次数，op1 强度默认 4）
##   0x0036 [sd] 记录当前 RNG 编号 = op0
##   0x0037 [ui] 播放 RNG 动画（op0 起始帧, op1 帧数/(-1), op2 速度/(16)）
##   0x0038 [sd] 离场：跑当前场景 onTeleport 脚本，失败跳 op0
##   0x0041 [sd] 标记脚本失败
##   0x0043 [sd] 设置 BGM（op0 曲号，op1 模式）
##   0x0045 [sd] 设置战斗音乐 op0          0x004A [sd] 设置战场 op0
##   0x0046 [sd] 队伍出生点 tile(op0,op1,h=op2)
##   0x0047 [sd] 播放音效 op0
##   0x0049 [sd] 设置事件对象状态 = op1
##   0x004D [ui] 等待任意键
##   0x004E [ui] 读取最近存档（跳回标题/读档流程）
##   0x004F [ui] 画面淡入红色（Game Over）
##   0x0050/0x0051 [sd] 淡出/淡入
##   0x0053/0x0054 [sd] 使用白天/夜晚调色板   0x0080 [sd] 切换昼夜调色板
##   0x0059 [sd] 切换场景 op0                   0x006D [sd] 设置场景进场/离场脚本
##   0x0065 [sd] 设置玩家精灵：角色 op0，精灵 op1，op2!=0 立即刷新
##   0x0068/0x0074 等条件跳转见上
##   0x006D/0x0099 [sd] 场景→地图改写
##   0x0071 [sd] 屏幕波动：等级 op0，进程 s16 op1
##   0x0073/0x009B [inf] 淡入当前场景（重绘 + 短等待）
##   0x0075 [sd] 设置队伍成员（op0..2 为角色号+1，0=空）
##   0x0076 [inf] 显示 FBP 图（WIN95 版行为=清屏；本移植经 world hook）
##   0x0077 [sd] 停止音乐
##   0x0078 [sd] 空操作（sdlpal 原样 FIXME）
##   0x0085 [sd] 延时 op0×80ms（折算为帧）
##   0x008C [ui] 颜色淡入淡出
##   0x0093 [sd] 场景淡入淡出（s16 op0 < 0 → 淡入）
##   0x0094 [sd] 事件对象状态 == s16 op1 → 跳 op2
##   0x0095 [sd] 当前场景 == op0 → 跳 op1
##   0x0096 [ui] 播放结局动画
##   0x009C-0x009F [bt] 敌人分裂/召唤/变身
##   0x00A0 [ui] 结束游戏（结局画面 + 制作名单 + 退出）
##   0x00A2 [sd] 向前随机跳 0..op0-1 条指令
##   0x00A3 [sd] CD 音乐（无 CD 时回落 op1 的 MUS 曲目）
##   0x00A4/0x00A5 [ui] FBP 滚动/精灵特效显示（本数据集未出现）
##   0x00A6 [sd] 备份画面（供 0x008E 恢复；本移植为 world hook）
##   0x00A7 [sd] 空操作（sdlpal 只在 PAL_RunAutoScript 里作为 no-op；SSS 中出现 295 次）
##   0xFFFF [sd] 显示消息 op0，等待按键
##
## ============================ World 接口（与 Lead 重构后的 world.gd 对齐） ============
## 已存在、VM 直接调用（缺失时用 has_method 兜底）：
##   script_dialog(text,msg) / script_dialog_closed / script_dialog_clear / script_dialog_style
##   script_refresh / script_change_scene(n) / script_party_position(gx,gy,half)
##   script_party_gesture(dir,frame,idx) / script_player_sprite(role,sprite,refresh)
##   script_set_party(r0,r1,r2) / script_event_state(which,state,last_id) / script_music
##   script_sound / script_fade_out / script_fade_in / script_use_day_palette /
##   script_use_night_palette / script_set_palette(num,night) / script_screen_wave(level,prog)
##   script_shop(store_id) / script_change_battlefield(id) / script_end_game /
##   script_confirm_menu()（简化：自动选是） / request_battle(team,flee_disabled,force_win)
##   → 战斗结束 world.on_battle_finished(result:String) → vm.resume_battle(result)
##   → RNG world.request_rng(rng_id)（当前无完成回调 → VM 不等待，播放后继续）
##   → 商店 world.script_shop(store_id)（当前无关闭回调 → VM 不等待）
## 尚未提供（VM 记录 _missing_hooks 并按默认分支继续，见 get_report()）：
##   confirm_menu() -> bool（同步是/否）              request_confirm()（异步 → vm.resume_choice）
##   request_wait_key() → vm.resume_key()             request_load_game() → vm.resume_menu()
##   request_rng_full(rng_id,start,frames,speed) → vm.resume_rng()
##   shake_screen/script_shake_screen(times,level)    script_scene_fade(palette,night,speed)
##   script_color_fade(color,speed,unknown)           script_backup_screen()
##   request_picture/request_scroll_picture/request_picture_sprite/request_fade_red
##   request_quit_game()；reload_map()（0x0099 改图后立即重载）
## 另：run_auto(entry, evt_id) -> int 是 World 每帧驱动的自动脚本入口（PAL_RunAutoScript）。
## 战斗代理由 port-battle 通过 vm.set_battle_proxy(obj) 注入，VM 用 has_method 调用：
##     damage_all(dmg) / damage_one(id,dmg) / poison_one/all(id) / cure_poison_one/all(id)
##     set_enemy_status(id,status,rounds) / halve_enemy_hp(id,limit) / kill_enemy(id)
##     drain_enemy_hp(id,dmg) / flee() / set_result(r) / set_auto_battle()
##     simulate_magic(role,magic,dmg) / steal(id,item) / blow(dmg) / collect_get(id) -> int
##     divide(...) / summon(...) / transform(...) / enemy_is_first(id) -> bool
##     is_enemy_turn() -> bool / enemy_hp_percent_gt(id,pct) -> bool / enemy_poisoned(id,poison)
##     pre_magic_anim(role) / spin_in_place() ...
##
## ============================ 统计（tools/scan_opcodes.py 生成） ============================
## 全量 SSS 数据（43557 条）实际出现 160 种 opcode（含 0xFFFF），本 VM 全部有分支：
##   完整实现(full) 128 种 / 依赖战斗代理(battle) 26 种 / 依赖 UI·画面 hook(hook) 6 种。
##   出现频次前 90% 的 32 种 opcode 全部完整实现。
##   工具输出：_rea_runtime/out/opcodes.json（频次表 / 前 100 场景可达性 / 覆盖率 / 静态校验）。
## battle: 0x0021 0x0028 0x002A 0x002E 0x0033 0x0039 0x003A 0x0042 0x005B 0x005C 0x005E
##         0x0060 0x0064 0x0066 0x0067 0x0068 0x0069 0x006A 0x006B 0x0089 0x008A 0x0091
##         0x0092 0x009C 0x009E 0x009F
## hook:   0x0035 0x0037 0x004D 0x004E 0x004F 0x0076 0x008C 0x00A4 0x00A5 0x00A6
##
## 兼容性：保留旧字段/方法（setup/start/is_active/tick/advance_dialog/waiting_dialog/wait_frames/
## next_entry/last_event_object_id/entry/ip），world.gd 现有调用不变。
## 等待状态：waiting_dialog / wait_frames（帧）/ _waiting_move（NPC·队伍·骑乘·视口移动，可用
## is_waiting_move()/waiting_move_kind() 查询）/ waiting_battle / waiting_menu / waiting_choice /
## waiting_rng / waiting_key，各自在 world 的回调里 resume_* 清除。

const MAX_PLAYER_ROLES := 6
const MAX_PLAYABLE_PLAYER_ROLES := 5
const MAX_PLAYERS_IN_PARTY := 3
const MAX_PLAYER_EQUIPMENTS := 6
const MAX_INVENTORY := 256
const MAX_POISONS := 16
const MAX_PLAYER_MAGICS := 32
const STATUS_ALL := 9
const MAX_LEVELS := 99

# PLAYERROLES 字段名（* 6 + role 的线性下标 → 字段/子表行）
const PR_EQUIP_ROW := 11
const PR_ATK := 17
const PR_MAG := 18
const PR_DEF := 19
const PR_DEX := 20
const PR_FLEE := 21
const PR_POISON_RES := 22
const PR_WALK_FRAMES := 64

# 方向
const DIR_SOUTH := 0
const DIR_WEST := 1
const DIR_NORTH := 2
const DIR_EAST := 3

const TRIGGER_TOUCH_NEAR := 4

# 战斗结果（battle.h BATTLERESULT）
const BATTLE_LOST := 1
const BATTLE_WON := 3
const BATTLE_FLEED := 0xFFFF
const BATTLE_TERMINATED := 0

# ---------------------------------------------------------------- 公共状态（保持旧字段名）

var data: PalData
var world: Node = null

var entry: int = 0
var ip: int = 0
var next_entry: int = 0
var ended: bool = true
var waiting_dialog: bool = false
var wait_frames: int = 0
var last_event_object_id: int = 0
var script_success: bool = true

## 新增等待状态（世界需在对应回调里清理；未注入回调时 VM 不会进入这些状态）
var waiting_battle: bool = false
var waiting_menu: bool = false
var waiting_rng: bool = false
var waiting_choice: bool = false
var waiting_key: bool = false

## 由 port-battle 注入的战斗代理（见文件头）
var battle_proxy: Object = null

## 调试输出（--auto 时由 world 置 true 可打印更多）
var debug: bool = false

## 调用栈帧：[返回地址, 返回后恢复的事件对象 id]（sdlpal 的 wEventObjectID 是每次调用的局部参数）
var _stack: Array = []
var _dialog_style: int = 0
var _unknown_ops: Dictionary = {}
var _missing_hooks: Dictionary = {}
var _idle_counter: int = 0
var _frame_num: int = 0
var _last_event_object: int = 0
var _cur_equip_part: int = -1
var _waiting_move: Dictionary = {}
var _pending_battle: PackedInt32Array = PackedInt32Array()
var _pending_choice: int = 0
var _pending_menu_finish: bool = false
var _pr_index: Array = []
var _pending_rng: int = 0
var _last_unequipped_item: int = 0
var _auto_frame: int = 0

## 调试口：`--vm-sweep` 时在完整游戏上下文（autoload 可用）里运行
## `tools/vm_scene_sweep.gd` 做 295 场景全量压测。
## 之所以放在这里：`--script` 模式不注册 autoload，而本文件直接引用 PALState/PALTables，
## 无法在 `--script` 模式编译，只能在正常启动（main.tscn → world → ScriptVM）时进入。
static var _sweep_launched: bool = false


func _init() -> void:
	_build_pr_index()


# ---------------------------------------------------------------- 公共 API

func setup(p_data: PalData, p_world: Node) -> void:
	data = p_data
	world = p_world
	if not _sweep_launched and "--vm-sweep" in OS.get_cmdline_args():
		_sweep_launched = true
		_run_vm_sweep()


func _run_vm_sweep() -> void:
	if not ResourceLoader.exists("res://tools/vm_scene_sweep.gd"):
		push_error("ScriptVM: 缺少 res://tools/vm_scene_sweep.gd")
		return
	var sweep = load("res://tools/vm_scene_sweep.gd").new()
	sweep.run_all()


func set_battle_proxy(p: Object) -> void:
	battle_proxy = p


func start(entry_point: int, event_object_id: int = 0) -> void:
	entry = entry_point
	ip = entry_point
	next_entry = entry_point
	ended = entry_point == 0
	waiting_dialog = false
	wait_frames = 0
	# sdlpal: 传入 0xFFFF 表示“沿用上一次的事件对象”
	var eid := event_object_id
	if eid == 0xFFFF:
		eid = _last_event_object
	else:
		_last_event_object = eid
	last_event_object_id = eid
	_stack.clear()
	_idle_counter = 0
	_frame_num = 0
	script_success = true
	_cur_equip_part = -1
	_waiting_move.clear()
	_pending_battle = PackedInt32Array()
	_pending_choice = 0
	_pending_menu_finish = false
	waiting_battle = false
	waiting_menu = false
	waiting_rng = false
	waiting_choice = false
	waiting_key = false


func is_active() -> bool:
	return not ended


## 是否处于“等待外部事件”的状态（world 可据此判断输入锁）。
func is_waiting() -> bool:
	return _is_blocked()


## 是否在等待 NPC/队伍/骑乘/视口移动完成（对应任务书的 waiting_npc_move 状态）。
func is_waiting_move() -> bool:
	return not _waiting_move.is_empty()


## 当前移动等待的类型："npc" / "party" / "ride" / "viewport" / ""。
func waiting_move_kind() -> String:
	return str(_waiting_move.get("kind", ""))


## 玩家按下确认键；返回是否被消费（保留旧语义：对白推进）。
func advance_dialog() -> bool:
	if waiting_dialog:
		waiting_dialog = false
		ip += 1
		if world != null:
			world.call("script_dialog_closed")
		return true
	return false


## 战斗结束回调（port-battle → world → VM）。
## result 支持 int（battle.h BATTLERESULT）或 String（"won"/"lost"/"fled"/"terminated"）。
func resume_battle(result: Variant) -> void:
	if not waiting_battle:
		return
	waiting_battle = false
	var a1: int = _pending_battle[1]
	var a2: int = _pending_battle[2]
	var r := _normalize_battle_result(result)
	if r == BATTLE_LOST and a1 != 0:
		_jump(a1)
	elif r == BATTLE_FLEED and a2 != 0:
		_jump(a2)
	else:
		ip += 1
	_pending_battle = PackedInt32Array()


## 菜单/商店结束回调。
func resume_menu() -> void:
	if not waiting_menu:
		return
	waiting_menu = false
	if _pending_menu_finish:
		_pending_menu_finish = false
		ip = 0
		_finish()
	else:
		ip += 1


## RNG 动画播放结束回调。
func resume_rng() -> void:
	if not waiting_rng:
		return
	waiting_rng = false
	ip += 1


## 是/否选择回调。
func resume_choice(result: bool) -> void:
	if not waiting_choice:
		return
	waiting_choice = false
	if result:
		ip += 1
	else:
		_jump(_pending_choice)


## 等待任意键回调。
func resume_key() -> void:
	if not waiting_key:
		return
	waiting_key = false
	ip += 1


## 外部强制结束（如读档后重载场景）。
func cancel() -> void:
	ended = true
	_stack.clear()
	_waiting_move.clear()


# ---------------------------------------------------------------- 自动脚本（PAL_RunAutoScript）
## World 每帧对每个 sState>0 && sVanishTime==0 && wAutoScript!=0 的事件对象调用一次；
## 返回值写回事件对象的 wAutoScript（0 = 停止）。语义同 sdlpal script.c:3484+：
## 每帧只跑一条指令（0x0003 无条件跳转链不耗帧），0x0004 同步调用子脚本，
## 需要等待的移动类指令改为「一帧一步，未到达则返回原入口」。
func run_auto(auto_entry: int, evt_id: int) -> int:
	if auto_entry <= 0 or auto_entry >= _script_count():
		return 0
	var e := auto_entry
	for guard in range(64):
		var s := data.script_entry(e)
		var op: int = s[0]
		var a0: int = s[1]
		var a1: int = s[2]
		var a2: int = s[3]
		_auto_frame += 1
		match op:
			0x0000:
				return 0
			0x0001:
				return e + 1
			0x0002:
				# 空闲帧计数在事件对象 EO_IDLE_AUTO 上累计（sdlpal wScriptIdleFrameCountAuto）
				var idle := _evt_idle_inc(evt_id, PalData.EO_IDLE_AUTO)
				if a1 == 0 or idle < a1:
					return a0
				_set_event_word(evt_id, PalData.EO_IDLE_AUTO, 0)
				e += 1
				continue
			0x0003:
				var idle3 := _evt_idle_inc(evt_id, PalData.EO_IDLE_AUTO)
				if a1 == 0 or idle3 < a1:
					e = a0
					if e <= 0 or e >= _script_count():
						return 0
					continue
				_set_event_word(evt_id, PalData.EO_IDLE_AUTO, 0)
				e += 1
				continue
			0x0004:
				# 同步调用子脚本（与 PAL_RunAutoScript 一致）
				_run_script_sync(a0, a1 if a1 != 0 else evt_id)
				e += 1
				return e
			0x0006:
				if randi_range(1, 100) >= a0:
					if a1 != 0:
						e = a1
						continue
				e += 1
				return e
			0x0009:
				# 等待 a0 帧：用事件对象 EO_IDLE_AUTO 计数
				var cnt := _evt_idle_inc(evt_id, PalData.EO_IDLE_AUTO)
				if cnt >= a0:
					_set_event_word(evt_id, PalData.EO_IDLE_AUTO, 0)
					e += 1
					return e
				return e
			0xFFFF:
				# 描述文本（WIN95 版由 UI 直接绘制）；不推进多页，按单条处理
				e += 1
				return e
			0x00A7:
				e += 1
				return e
			0x0038:
				# 离场脚本：同步跑当前场景 onTeleport（PAL_RunTriggerScript）
				var tele := 0
				if data != null:
					var sc := data.scene(int(PALState.scene))
					if sc.size() > PalData.SC_SCRIPT_ON_TELEPORT:
						tele = int(sc[PalData.SC_SCRIPT_ON_TELEPORT])
				if tele != 0:
					_run_script_sync(tele, 0xFFFF)
					e += 1
					return e
				if a0 != 0:
					e = a0
					continue
				return 0
			0x000B, 0x000C, 0x000D, 0x000E:
				var ev := NpcMove.get_event(world, evt_id)
				if not ev.is_empty():
					ev[NpcMove.EO_DIRECTION] = op - 0x000B
					NpcMove._walk_one_step_in(ev, 2)
				return e + 1
			0x0010:
				if NpcMove.walk_to_step(world, evt_id, a0, a1, a2, 3):
					return e + 1
				return e
			0x0011:
				if (evt_id & 1) ^ (_auto_frame & 1):
					if NpcMove.walk_to_step(world, evt_id, a0, a1, a2, 2):
						return e + 1
				return e
			0x007C:
				if (evt_id & 1) ^ (_auto_frame & 1):
					if NpcMove.walk_to_step(world, evt_id, a0, a1, a2, 4):
						return e + 1
				return e
			0x0082:
				if NpcMove.walk_to_step(world, evt_id, a0, a1, a2, 8):
					return e + 1
				return e
			0x0070:
				if NpcMove.party_walk_step(world, a0, a1, a2, 2):
					return e + 1
				return e
			0x007A:
				if NpcMove.party_walk_step(world, a0, a1, a2, 4):
					return e + 1
				return e
			0x007B:
				if NpcMove.party_walk_step(world, a0, a1, a2, 8):
					return e + 1
				return e
			0x0087:
				NpcMove.walk_one_step(world, evt_id, 0)
				return e + 1
			_:
				var nxt := _exec_one_isolated(e, evt_id)
				if nxt <= 0:
					return 0
				return nxt
	return 0


## 自动脚本用的孤立指令执行：临时借用 ip/等待状态执行一条 PAL_InterpretInstruction
## 分支后恢复现场，返回下一条入口地址。
func _exec_one_isolated(e: int, evt_id: int) -> int:
	var saved_ip := ip
	var saved_entry := entry
	var saved_next := next_entry
	var saved_ended := ended
	var saved_dialog := waiting_dialog
	var saved_frames := wait_frames
	var saved_battle := waiting_battle
	var saved_menu := waiting_menu
	var saved_rng := waiting_rng
	var saved_choice := waiting_choice
	var saved_key := waiting_key
	var saved_evt := last_event_object_id
	var saved_move := _waiting_move
	var saved_choice_entry := _pending_choice
	var saved_stack := _stack
	var saved_equip := _cur_equip_part
	var saved_pending_battle := _pending_battle
	var saved_menu_finish := _pending_menu_finish
	ip = e
	entry = e
	ended = false
	waiting_dialog = false
	wait_frames = 0
	waiting_battle = false
	waiting_menu = false
	waiting_rng = false
	waiting_choice = false
	waiting_key = false
	last_event_object_id = evt_id
	_waiting_move = {}
	_stack = []
	_cur_equip_part = -1
	_execute_one()
	var nxt := ip
	if ended:
		nxt = 0
	elif waiting_dialog or waiting_battle or waiting_menu or waiting_rng \
			or waiting_choice or waiting_key or not _waiting_move.is_empty():
		# 自动脚本里不能阻塞（sdlpal 的阻塞调用在这里按“已执行”跳过）[inf]
		nxt = e + 1
	# 恢复现场
	ip = saved_ip
	entry = saved_entry
	next_entry = saved_next
	ended = saved_ended
	waiting_dialog = saved_dialog
	wait_frames = saved_frames
	waiting_battle = saved_battle
	waiting_menu = saved_menu
	waiting_rng = saved_rng
	waiting_choice = saved_choice
	waiting_key = saved_key
	last_event_object_id = saved_evt
	_waiting_move = saved_move
	_pending_choice = saved_choice_entry
	_stack = saved_stack
	_cur_equip_part = saved_equip
	_pending_battle = saved_pending_battle
	_pending_menu_finish = saved_menu_finish
	return nxt


func _script_count() -> int:
	if data != null:
		return data.scripts.size() / 4
	return 0


func _evt_idle_inc(evt_id: int, field: int) -> int:
	var v := _get_event_word(evt_id, field) + 1
	_set_event_word(evt_id, field, v)
	return v


func _run_script_sync(entry_idx: int, evt: int) -> void:
	if entry_idx == 0:
		return
	if PALState.script_runner.is_valid():
		PALState.script_runner.call(entry_idx, evt)


func get_report() -> Dictionary:
	return {
		"entry": entry,
		"ip": ip,
		"ended": ended,
		"script_success": script_success,
		"unknown_ops": _unknown_ops.duplicate(),
		"missing_hooks": _missing_hooks.duplicate(),
		"stack_depth": _stack.size(),
	}


# ---------------------------------------------------------------- 每帧驱动

func tick() -> void:
	if ended:
		return
	_frame_num += 1
	if waiting_dialog or waiting_battle or waiting_menu or waiting_rng or waiting_choice or waiting_key:
		return
	if wait_frames > 0:
		wait_frames -= 1
		return
	if not _waiting_move.is_empty():
		if not _advance_move():
			return
		_waiting_move.clear()
		ip += 1
	var steps := 0
	while not ended and not _is_blocked() and steps < 400:
		steps += 1
		_execute_one()


func _is_blocked() -> bool:
	return waiting_dialog or waiting_battle or waiting_menu or waiting_rng \
		or waiting_choice or waiting_key or wait_frames > 0 or not _waiting_move.is_empty()


## 推进一帧移动；返回是否完成。
func _advance_move() -> bool:
	var kind: String = _waiting_move.get("kind", "")
	if world == null:
		return true
	match kind:
		"npc":
			var id: int = int(_waiting_move.get("id", 0))
			var parity: bool = bool(_waiting_move.get("parity", false))
			if parity and ((id & 1) ^ (_frame_num & 1)) == 0:
				return false
			return NpcMove.walk_to_step(world, id,
				int(_waiting_move.get("x", 0)), int(_waiting_move.get("y", 0)),
				int(_waiting_move.get("h", 0)), int(_waiting_move.get("speed", 3)))
		"party":
			return NpcMove.party_walk_step(world,
				int(_waiting_move.get("x", 0)), int(_waiting_move.get("y", 0)),
				int(_waiting_move.get("h", 0)), int(_waiting_move.get("speed", 2)))
		"ride":
			return NpcMove.party_ride_step(world, int(_waiting_move.get("id", 0)),
				int(_waiting_move.get("x", 0)), int(_waiting_move.get("y", 0)),
				int(_waiting_move.get("h", 0)), int(_waiting_move.get("speed", 2)))
		"viewport":
			# 0x007F 逐帧平移：sdlpal 同时反向移动 partyoffset/party[i].x，
			# 使队伍绝对坐标不变（纯镜头平移）。本移植用 party[0] 屏幕坐标承担 partyoffset。
			var dx: int = int(_waiting_move.get("dx", 0))
			var dy: int = int(_waiting_move.get("dy", 0))
			PALState.viewport += Vector2i(dx, dy)
			if not PALState.party.is_empty():
				var p: Dictionary = PALState.party[0]
				p["x"] = int(p["x"]) - dx
				p["y"] = int(p["y"]) - dy
			var left: int = int(_waiting_move.get("left", 1)) - 1
			_waiting_move["left"] = left
			return left <= 0
	return true


## 开始一个移动指令：立即尝试一步，未完成则挂起等待（ip 不前进）。
func _start_move(kind: String, params: Dictionary) -> void:
	if world == null:
		ip += 1
		return
	params["kind"] = kind
	_waiting_move = params
	if _advance_move():
		_waiting_move.clear()
		ip += 1


# ---------------------------------------------------------------- 指令执行

func _execute_one() -> void:
	var s := data.script_entry(ip)
	var op: int = s[0]
	var a0: int = s[1]
	var a1: int = s[2]
	var a2: int = s[3]
	var cur_id := _target_id(a0)
	var evt_id := last_event_object_id
	match op:
		# ---------------------------------------------------------- 控制流
		0x0000:
			_finish()
		0x0001:
			_finish(ip + 1)
		0x0002:
			# 空闲帧计数未到 → 下一入口 = op0 并结束；否则清计数继续
			if a1 == 0 or _idle_inc(evt_id) < a1:
				_finish(a0)
			else:
				_idle_reset(evt_id)
				ip += 1
		0x0003:
			# 无条件跳转（受 op1 空闲帧计数限制）
			if a1 == 0 or _idle_inc(evt_id) < a1:
				_jump(a0)
			else:
				_idle_reset(evt_id)
				ip += 1
		0x0004:
			# 调用子脚本（op1 指定事件对象，0=沿用；返回时恢复外层事件对象）
			if a0 != 0 and _stack.size() < 64:
				_stack.append([ip + 1, last_event_object_id])
				ip = a0
				if a1 != 0:
					last_event_object_id = a1
					_last_event_object = a1
			else:
				ip += 1
		0x0005:
			# 重绘（op1×60ms 近似为 op1×4 帧）
			if world != null:
				world.call("script_refresh", a2 != 0)
			if a1 > 0 and a1 < 200:
				wait_frames = a1 * 4
			ip += 1
		0x0006:
			if randi_range(1, 100) >= a0:
				_jump(a1)
			else:
				ip += 1
		0x0007:
			# 战斗（op0 敌队，op1 失败分支，op2 逃跑分支；op2==0 视为 Boss 不可逃）
			_start_battle(a0, a1, a2)
		0x0008:
			next_entry = ip + 1
			ip += 1
		0x0009:
			# 等待 op0 帧；op2 时每帧更新队伍手势
			if world != null and a2 != 0:
				world.call("script_party_gesture", int(PALState.party_dir), 0, 0)
			wait_frames = a0 if a0 > 0 else 1
			ip += 1
		0x000A:
			# 是/否选择；“否”跳到 op0
			_start_confirm(a0)
		# ---------------------------------------------------------- NPC/队伍
		0x000B, 0x000C, 0x000D, 0x000E:
			# 触发脚本的事件对象朝 op-0xB 方向走一步（speed 2）；操作数 0 不参与选对象
			if evt_id > 0:
				var e := NpcMove.get_event(world, evt_id)
				if not e.is_empty():
					e[NpcMove.EO_DIRECTION] = op - 0x000B
					NpcMove._walk_one_step_in(e, 2)
			ip += 1
		0x000F:
			# 设触发脚本事件对象的朝向/手势（0xFFFF = 不改）
			if evt_id > 0:
				var e := NpcMove.get_event(world, evt_id)
				if not e.is_empty():
					if a0 != 0xFFFF:
						e[NpcMove.EO_DIRECTION] = a0
					if a1 != 0xFFFF:
						e[NpcMove.EO_CUR_FRAME] = a1
			ip += 1
		0x0010:
			_start_move("npc", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 3})
		0x0011:
			_start_move("npc", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 2, "parity": true})
		0x0012:
			# 事件对象位置 = 队伍位置 + (op1, op2)
			if cur_id > 0:
				var e := NpcMove.get_event(world, cur_id)
				if not e.is_empty():
					e[NpcMove.EO_X] = NpcMove._pos16(NpcMove.party_x(world) + a1)
					e[NpcMove.EO_Y] = NpcMove._pos16(NpcMove.party_y(world) + a2)
					NpcMove.set_event(world, cur_id, e)
			ip += 1
		0x0013:
			if cur_id > 0:
				_set_event_word(cur_id, NpcMove.EO_X, a1)
				_set_event_word(cur_id, NpcMove.EO_Y, a2)
			ip += 1
		0x0014:
			if evt_id > 0:
				var e := NpcMove.get_event(world, evt_id)
				if not e.is_empty():
					e[NpcMove.EO_CUR_FRAME] = a0
					e[NpcMove.EO_DIRECTION] = DIR_SOUTH
					NpcMove.set_event(world, evt_id, e)
			ip += 1
		0x0015:
			if world != null:
				world.call("script_party_gesture", a0, a1, a2)
			else:
				PALState.party_dir = a0
			ip += 1
		0x0016:
			if a0 != 0:
				var e := NpcMove.get_event(world, cur_id)
				if not e.is_empty():
					e[NpcMove.EO_DIRECTION] = a1
					e[NpcMove.EO_CUR_FRAME] = a2
					NpcMove.set_event(world, cur_id, e)
			ip += 1
		0x003B, 0x003C, 0x003D, 0x003E:
			# 对话框分区（中/上/下/居中窗口）：清对话框并设置样式
			# sdlpal PAL_StartDialog：0x003C/0x003D 的 op0=iNumCharFace、op1=bFontColor；
			# 0x003B/0x003E 的 op0=bFontColor（无头像参数，face 传 0 只改字色）。
			_dialog_style = op - 0x003B
			if world != null:
				world.call("script_dialog_clear")
				world.call("script_dialog_style", _dialog_style)
				if world.has_method("script_dialog_face"):
					if op == 0x003C or op == 0x003D:
						world.call("script_dialog_face", a0, a1)
					else:
						world.call("script_dialog_face", 0, a0)
				else:
					_note_missing_hook("script_dialog_face")
			ip += 1
		0x003F:
			_start_move("ride", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 2})
		0x0040:
			if a0 != 0:
				_set_event_word(cur_id, NpcMove.EO_TRIGGER_MODE, a1)
			ip += 1
		0x0044:
			_start_move("ride", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 4})
		0x004B:
			if evt_id > 0:
				_set_event_word(evt_id, NpcMove.EO_VANISH, _s16(0x10000 - 15))
			ip += 1
		0x004C:
			# 怪物追击：op0 距离（默认 8），op1 速度（默认 4），op2 穿墙
			var dist := a0 if a0 > 0 else 8
			var spd := a1 if a1 > 0 else 4
			if world != null and evt_id > 0:
				NpcMove.monster_chase_step(world, evt_id, spd, dist, a2 != 0, _frame_num)
			ip += 1
		0x0052:
			if evt_id > 0:
				var e := NpcMove.get_event(world, evt_id)
				if not e.is_empty():
					var dur := a0 if a0 > 0 else 800
					e[NpcMove.EO_STATE] = -e[NpcMove.EO_STATE]
					e[NpcMove.EO_VANISH] = dur
					NpcMove.set_event(world, evt_id, e)
			ip += 1
		0x0062:
			PALState.chase_speed_cycles = a0
			PALState.chase_range = 0
			ip += 1
		0x0063:
			PALState.chase_speed_cycles = a0
			PALState.chase_range = 3
			ip += 1
		0x006C:
			# 事件对象位移后走一步（动画）
			if cur_id > 0:
				var e := NpcMove.get_event(world, cur_id)
				if not e.is_empty():
					e[NpcMove.EO_X] = NpcMove._pos16(e[NpcMove.EO_X] + _s16(a1))
					e[NpcMove.EO_Y] = NpcMove._pos16(e[NpcMove.EO_Y] + _s16(a2))
					NpcMove._walk_one_step_in(e, 0)
					NpcMove.set_event(world, cur_id, e)
			ip += 1
		0x006E:
			# 队伍平移一步（原版改 viewport，这里同步改队伍绝对坐标）
			if world != null:
				NpcMove.party_offset_step(world, _s16(a0), _s16(a1), a2 * 8)
			ip += 1
		0x006F:
			var target := _s16(a1)
			if _get_event_word(cur_id, NpcMove.EO_STATE) == target:
				_set_event_word(evt_id, NpcMove.EO_STATE, target)
			ip += 1
		0x0070:
			_start_move("party", {"x": a0, "y": a1, "h": a2, "speed": 2})
		0x007A:
			_start_move("party", {"x": a0, "y": a1, "h": a2, "speed": 4})
		0x007B:
			_start_move("party", {"x": a0, "y": a1, "h": a2, "speed": 8})
		0x007C:
			_start_move("npc", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 4, "parity": true})
		0x007D:
			if cur_id > 0:
				_set_event_word(cur_id, NpcMove.EO_X,
					NpcMove._pos16(_get_event_word(cur_id, NpcMove.EO_X) + _s16(a1)))
				_set_event_word(cur_id, NpcMove.EO_Y,
					NpcMove._pos16(_get_event_word(cur_id, NpcMove.EO_Y) + _s16(a2)))
			ip += 1
		0x007E:
			_set_event_word(cur_id, NpcMove.EO_LAYER, _s16(a1))
			ip += 1
		0x007F:
			_do_viewport(a0, a1, a2)
		0x0080:
			# 切换昼夜调色板（PAL_PaletteFade；op0==0 时立即切换）
			PALState.night_palette = not PALState.night_palette
			if world != null:
				if PALState.night_palette and world.has_method("script_use_night_palette"):
					world.call("script_use_night_palette")
				elif not PALState.night_palette and world.has_method("script_use_day_palette"):
					world.call("script_use_day_palette")
			ip += 1
		0x0081:
			# 玩家未面向事件对象 op0 → 跳 op2
			if not _in_current_scene(a0):
				script_success = false
				_jump(a2)
			else:
				var ex := _get_event_word(cur_id, NpcMove.EO_X)
				var ey := _get_event_word(cur_id, NpcMove.EO_Y)
				var pdir: int = int(PALState.party_dir)
				var x := ex + (16 if (pdir == DIR_WEST or pdir == DIR_SOUTH) else -16)
				var y := ey + (8 if (pdir == DIR_WEST or pdir == DIR_NORTH) else -8)
				x -= NpcMove.party_x(world)
				y -= NpcMove.party_y(world)
				if absi(x) + absi(y * 2) < a1 * 32 + 16 and _get_event_word(a0, NpcMove.EO_STATE) > 0:
					if a1 > 0:
						_set_event_word(cur_id, NpcMove.EO_TRIGGER_MODE, TRIGGER_TOUCH_NEAR + a1)
					ip += 1
				else:
					script_success = false
					_jump(a2)
		0x0082:
			_start_move("npc", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 8})
		0x0083:
			if not _in_current_scene(a0):
				script_success = false
				_jump(a2)
			else:
				var x := _get_event_word(evt_id, NpcMove.EO_X) - _get_event_word(cur_id, NpcMove.EO_X)
				var y := _get_event_word(evt_id, NpcMove.EO_Y) - _get_event_word(cur_id, NpcMove.EO_Y)
				if absi(x) + absi(y * 2) >= a1 * 32 + 16:
					script_success = false
					_jump(a2)
				else:
					ip += 1
		0x0084:
			# 把物品作为事件对象放到队伍前方
			if not _in_current_scene(a0):
				script_success = false
				_jump(a2)
			else:
				var pdir: int = int(PALState.party_dir)
				var x := NpcMove.party_x(world) + (-16 if (pdir == DIR_WEST or pdir == DIR_SOUTH) else 16)
				var y := NpcMove.party_y(world) + (-8 if (pdir == DIR_WEST or pdir == DIR_NORTH) else 8)
				if NpcMove.check_obstacle(world, x, y, false, 0, false):
					script_success = false
					_jump(a2)
				else:
					_set_event_word(cur_id, NpcMove.EO_X, x)
					_set_event_word(cur_id, NpcMove.EO_Y, y)
					_set_event_word(cur_id, NpcMove.EO_STATE, a1)
					ip += 1
		0x0087:
			if cur_id > 0:
				NpcMove.walk_one_step(world, cur_id, 0)
			ip += 1
		0x0097:
			_start_move("ride", {"id": evt_id, "x": a0, "y": a1, "h": a2, "speed": 8})
		0x0098:
			# 跟随者（world 暂不渲染；写 PALState 供后续）
			var n := 0
			for i in range(2):
				var v: int = a0 if i == 0 else a1
				if v > 0:
					n = i + 1
			PALState.follower_count = n
			ip += 1
		0x009A:
			var lo := a0
			var hi := a1
			if lo > 0 and hi >= lo and hi - lo <= 1024:
				for i in range(lo, hi + 1):
					_set_event_word(i, NpcMove.EO_STATE, a2)
			ip += 1
		0x00A1:
			# 所有队员归位到队长位置（sdlpal: rgTrail 全指向队长，队员 x 同队长、y-1）
			var head := Vector2i(160, 112)
			if not PALState.party.is_empty():
				var p0: Dictionary = PALState.party[0]
				head = Vector2i(int(p0["x"]), int(p0["y"]))
			var abs_head := NpcMove.party_abs(world)
			for i in range(PALState.trail.size()):
				PALState.trail[i] = {"x": abs_head.x, "y": abs_head.y, "dir": int(PALState.party_dir)}
			for i in range(1, PALState.party.size()):
				var m = PALState.party[i]
				if m is Dictionary:
					m["x"] = head.x
					m["y"] = head.y - 1
			ip += 1
		# ---------------------------------------------------------- 属性/背包/仙术
		0x0017:
			# 装备效果表 [op0-0xB] 的第 op1 个字（op1*6 + 事件对象） = s16 op2
			_eq_set(a0 - 0x0B, a1, evt_id, _s16(a2))
			ip += 1
		0x0018:
			_equip_item(a0 - 0x0B, a1, evt_id)
			ip += 1
		0x0019:
			var role := evt_id if a2 == 0 else a2 - 1
			_pr_set(a0, role, _pr_get(a0, role) + _s16(a1))
			ip += 1
		0x001A:
			var role := evt_id if a2 == 0 else a2 - 1
			if _cur_equip_part != -1:
				_eq_set(_cur_equip_part, a0, role, _s16(a1))
			else:
				_pr_set(a0, role, _s16(a1))
			ip += 1
		0x001B:
			if not _hpmp_generic(a0, a1, 0):
				script_success = false
			ip += 1
		0x001C:
			if not _hpmp_generic(a0, 0, a1):
				script_success = false
			ip += 1
		0x001D:
			if not _hpmp_generic(a0, a1, a1):
				script_success = false
			ip += 1
		0x001E:
			var delta := _s16(a0)
			if delta < 0 and int(PALState.cash) < -delta:
				_jump(a1)
			else:
				PALState.cash = int(PALState.cash) + delta
				ip += 1
		0x001F:
			_add_item(a0, _s16(a1))
			ip += 1
		0x0020:
			var n := a1
			if n == 0:
				n = 1
			if n <= _count_item(a0) or a2 == 0:
				var removed := _add_item(a0, -n)
				if removed <= 0:
					var remain := -removed if removed < 0 else n
					# 尝试卸下已装备的同类物品
					var roles := _party_roles()
					for i in range(roles.size()):
						if remain <= 0:
							break
						var w: int = roles[i]
						for j in range(MAX_PLAYER_EQUIPMENTS):
							if _pr_get(PR_EQUIP_ROW + j, w) == a0:
								_remove_equipment_effect(w, j)
								_pr_set(PR_EQUIP_ROW + j, w, 0)
								remain -= 1
								if remain <= 0:
									break
				ip += 1
			else:
				_jump(a2)
		0x0022:
			_revive(a0, a1)
			ip += 1
		0x0023:
			_unequip_all(a0, a1)
			ip += 1
		0x0025:
			if a0 != 0:
				_set_event_word(cur_id, NpcMove.EO_TRIGGER_SCRIPT, a1)
			ip += 1
		0x0024:
			if a0 != 0:
				_set_event_word(cur_id, NpcMove.EO_AUTO_SCRIPT, a1)
			ip += 1
		0x0026:
			_open_shop(a0, true)
		0x0027:
			_open_shop(0, false)
		0x002B, 0x002C, 0x002D, 0x002F:
			_player_state_op(op, a0, a1)
			ip += 1
		0x0030:
			var role := evt_id if a2 == 0 else a2 - 1
			_eq_set(MAX_PLAYER_EQUIPMENTS, a0, role, _pr_get(a0, role) * _s16(a1) / 100)
			ip += 1
		0x0031:
			_eq_set(MAX_PLAYER_EQUIPMENTS, 1, evt_id, a0)
			ip += 1
		0x0055:
			var role := evt_id if a1 == 0 else a1 - 1
			_add_magic(role, a0)
			ip += 1
		0x0056:
			var role := evt_id if a1 == 0 else a1 - 1
			_remove_magic(role, a0)
			ip += 1
		0x0057:
			var role := evt_id
			var mult := a1 if a1 != 0 else 8
			var dmg := _pr_get(10, role) * mult
			_magic_damage_override(a0, dmg)
			_pr_set(10, role, 0)
			_battle_call("simulate_magic_damage", [a0, dmg], null)
			ip += 1
		0x0058:
			if _get_item_amount(a0) < _s16(a1):
				_jump(a2)
			else:
				ip += 1
		0x005A:
			_pr_set(9, evt_id, _pr_get(9, evt_id) / 2)
			ip += 1
		0x005D:
			if not _is_poisoned_kind(evt_id, a0):
				_jump(a1)
			else:
				ip += 1
		0x005F:
			_pr_set(9, evt_id, 0)
			ip += 1
		0x0061:
			if not _is_poisoned_level(evt_id, 0):
				_jump(a0)
			else:
				ip += 1
		0x0074:
			var jump74 := false
			for r in _party_roles():
				if _pr_get(9, int(r)) < _pr_get(7, int(r)):
					jump74 = true
					break
			if jump74:
				_jump(a0)
			else:
				ip += 1
		0x0079:
			var jump79 := false
			for r in _party_roles():
				if _pr_get(3, int(r)) == a0:
					jump79 = true
					break
			if jump79:
				_jump(a1)
			else:
				ip += 1
		0x0086:
			var equip_item := a0
			var need := 1 if a1 == 0 else a1
			var cnt := 0
			for r in _party_roles():
				for j in range(MAX_PLAYER_EQUIPMENTS):
					if _pr_get(PR_EQUIP_ROW + j, int(r)) == equip_item:
						cnt += 1
			if cnt < need:
				_jump(a2)
			else:
				ip += 1
		0x008D:
			_player_level_up(evt_id, a0)
			ip += 1
		0x008F:
			PALState.cash = int(PALState.cash) / 2
			ip += 1
		0x0090:
			_patch_object_word(a0, 2 + a2, a1)
			ip += 1
		# ---------------------------------------------------------- 场景/画面/音频/系统
		0x0035:
			var times := a1 if a1 != 0 else 4
			if world != null:
				if world.has_method("script_shake_screen"):
					world.call("script_shake_screen", a0, times)
				elif world.has_method("shake_screen"):
					world.call("shake_screen", times)
				else:
					_note_missing_hook("shake_screen")
			ip += 1
		0x0036:
			_pending_rng = a0
			PALState.vars["cur_playing_rng"] = a0
			ip += 1
		0x0037:
			_play_rng(a0, a1, a2)
		0x0038:
			# 离场：跑当前场景 onTeleport；没有则失败跳 op0
			var scene_entry := 0
			if data != null:
				var sc := data.scene(_scene_no())
				if sc.size() > PalData.SC_SCRIPT_ON_TELEPORT:
					scene_entry = sc[PalData.SC_SCRIPT_ON_TELEPORT]
			if scene_entry != 0:
				# sdlpal 用 PAL_RunTriggerScript(onTeleport, 0xFFFF)：事件对象沿用当前
				_stack.append([ip + 1, last_event_object_id])
				ip = scene_entry
			else:
				script_success = false
				if a0 != 0:
					_jump(a0)
				else:
					_finish()
		0x0041:
			script_success = false
			ip += 1
		0x0043:
			PALState.music = a0
			if world != null:
				world.call("script_music", a0, a1)
			ip += 1
		0x0045:
			PALState.battle_music = a0
			ip += 1
		0x0046:
			if world != null:
				world.call("script_party_position", a0, a1, a2)
			ip += 1
		0x0047:
			if world != null:
				world.call("script_sound", a0)
			ip += 1
		0x0049:
			if world != null:
				world.call("script_event_state", cur_id, a1, evt_id)
			_set_event_word(cur_id, NpcMove.EO_STATE, a1)
			ip += 1
		0x004A:
			PALState.battle_field = a0
			if world != null and world.has_method("script_change_battlefield"):
				world.call("script_change_battlefield", a0)
			ip += 1
		0x004D:
			_start_wait_key()
		0x004E:
			_start_load_game()
		0x004F:
			if world != null and world.has_method("request_fade_red"):
				world.call("request_fade_red")
			elif world != null and world.has_method("script_fade_out"):
				world.call("script_fade_out", 1)
			else:
				_note_missing_hook("request_fade_red")
			ip += 1
		0x0050:
			if world != null:
				world.call("script_fade_out", a0 if a0 > 0 else 1)
			PALState.need_fade_in = true
			ip += 1
		0x0051:
			if world != null:
				world.call("script_fade_in", a0)
			PALState.need_fade_in = false
			ip += 1
		0x0053:
			PALState.night_palette = false
			if world != null and world.has_method("script_use_day_palette"):
				world.call("script_use_day_palette")
			ip += 1
		0x0054:
			PALState.night_palette = true
			if world != null and world.has_method("script_use_night_palette"):
				world.call("script_use_night_palette")
			ip += 1
		0x0059:
			if a0 > 0 and _scene_no() != a0:
				PALState.scene = a0
				if world != null:
					world.call("script_change_scene", a0)
			_stack.clear()
			_finish()
		0x0065:
			if world != null:
				world.call("script_player_sprite", a0, a1, a2)
			ip += 1
		0x006D:
			# 设置场景进场/离场脚本
			if a0 > 0 and data != null and a0 - 1 < data.scenes.size():
				if a1 != 0:
					data.scenes[a0 - 1][PalData.SC_SCRIPT_ON_ENTER] = a1
				if a2 != 0:
					data.scenes[a0 - 1][PalData.SC_SCRIPT_ON_TELEPORT] = a2
				if a1 == 0 and a2 == 0:
					data.scenes[a0 - 1][PalData.SC_SCRIPT_ON_ENTER] = 0
					data.scenes[a0 - 1][PalData.SC_SCRIPT_ON_TELEPORT] = 0
			ip += 1
		0x0071:
			PALState.screen_wave = a0
			PALState.wave_progression = _s16(a1)
			if world != null and world.has_method("script_screen_wave"):
				world.call("script_screen_wave", a0, _s16(a1))
			elif world != null and world.has_method("set_screen_wave"):
				world.call("set_screen_wave", a0, _s16(a1))
			ip += 1
		0x0073, 0x009B:
			if world != null:
				world.call("script_refresh", true)
			wait_frames = 8
			ip += 1
		0x0075:
			_set_party(a0, a1, a2)
			ip += 1
		0x0076:
			# WIN95 版行为 = 清屏（原版不分页显示图片），保留 hook
			if world != null and world.has_method("request_picture"):
				world.call("request_picture", a0, a1)
			elif world != null and world.has_method("script_clear_screen"):
				world.call("script_clear_screen")
			else:
				_note_missing_hook("request_picture")
			ip += 1
		0x0077:
			if PALAudio != null and PALAudio.has_method("stop_music"):
				PALAudio.call("stop_music")
			if world != null and world.has_method("script_music"):
				world.call("script_music", 0, 0)
			PALState.music = 0
			ip += 1
		0x0078, 0x00A7:
			# sdlpal 原样 no-op（0x0078 FIXME；0x00A7 只在自动脚本里作为空操作）
			ip += 1
		0x0085:
			wait_frames = maxi(1, a0 * 5)
			ip += 1
		0x008B:
			PALState.palette = a0
			if world != null and world.has_method("script_set_palette"):
				world.call("script_set_palette", a0, PALState.night_palette)
			else:
				_note_missing_hook("script_set_palette")
			ip += 1
		0x008C:
			if world != null and world.has_method("script_color_fade"):
				world.call("script_color_fade", a0, a1, a2)
			else:
				_note_missing_hook("script_color_fade")
			PALState.need_fade_in = false
			ip += 1
		0x008E:
			if world != null:
				world.call("script_dialog_clear")
			ip += 1
		0x0093:
			var spd := _s16(a0)
			if world != null and world.has_method("script_scene_fade"):
				world.call("script_scene_fade", PALState.palette, PALState.night_palette, spd)
			elif world != null:
				if spd < 0:
					world.call("script_fade_in", -spd)
				else:
					world.call("script_fade_out", spd if spd > 0 else 1)
			PALState.need_fade_in = spd < 0
			ip += 1
		0x0094:
			if _get_event_word(cur_id, NpcMove.EO_STATE) == _s16(a1):
				_jump(a2)
			else:
				ip += 1
		0x0095:
			if _scene_no() == a0:
				_jump(a1)
			else:
				ip += 1
		0x0096:
			if world != null and world.has_method("script_end_game"):
				world.call("script_end_game")
			elif world != null and world.has_method("request_ending"):
				world.call("request_ending")
			else:
				_note_missing_hook("script_end_game")
			ip += 1
		0x0099:
			# 改场景对应地图；(0xFFFF) = 当前场景，改完需要重载地图
			if data != null:
				var target_scene := _scene_no() if a0 == 0xFFFF else a0
				if target_scene >= 1 and target_scene <= data.scenes.size():
					data.scenes[target_scene - 1][PalData.SC_MAP] = a1
					if world != null and world.has_method("reload_map"):
						world.call("reload_map")
					elif world != null and world.has_method("script_force_redraw"):
						world.call("script_force_redraw")
			ip += 1
		0x00A0:
			if world != null and world.has_method("script_end_game"):
				world.call("script_end_game")
			elif world != null and world.has_method("request_ending"):
				world.call("request_ending")
			else:
				_note_missing_hook("script_end_game")
			if world != null and world.has_method("request_quit_game"):
				world.call("request_quit_game")
			_stack.clear()
			_finish()
		0x00A2:
			# 向前随机跳 0..op0-1 条指令（sdlpal: entry += rand; 再 return entry+1）
			var span := a0 if a0 > 0 else 1
			_jump(ip + 1 + randi_range(0, span - 1))
		0x00A3:
			PALState.music = a1
			if world != null:
				world.call("script_music", a1, 0)
			ip += 1
		0x00A4:
			if world != null and world.has_method("request_scroll_picture"):
				world.call("request_scroll_picture", a0, a1, a2)
			else:
				_note_missing_hook("request_scroll_picture")
			ip += 1
		0x00A5:
			if world != null and world.has_method("request_picture_sprite"):
				world.call("request_picture_sprite", a0, a1, a2)
			else:
				_note_missing_hook("request_picture_sprite")
			ip += 1
		0x00A6:
			if world != null and world.has_method("script_backup_screen"):
				world.call("script_backup_screen")
			else:
				_note_missing_hook("script_backup_screen")
			ip += 1
		0xFFFF:
			var text := data.msg(a0) if data != null else ""
			if world != null:
				world.call("script_dialog", text, a0)
			waiting_dialog = true
		# ---------------------------------------------------------- 战斗专用（依赖 battle_proxy）
		0x0021:
			if a0 != 0:
				_battle_call("damage_all", [a1])
			else:
				_battle_call("damage_one", [evt_id, a1])
			ip += 1
		0x0028:
			if a0 != 0:
				_battle_call("poison_all", [a1])
			else:
				_battle_call("poison_one", [evt_id, a1])
			ip += 1
		0x0029:
			var pr := _player_poison_resist(evt_id)
			if randi_range(1, 100) > pr:
				_add_poison(evt_id, a1)
			ip += 1
		0x002A:
			if a0 != 0:
				_battle_call("cure_poison_all", [a1])
			else:
				_battle_call("cure_poison_one", [evt_id, a1])
			ip += 1
		0x002E:
			# 敌人状态：抗性判定失败跳 op2
			var ok: Variant = _battle_call("set_enemy_status", [evt_id, a0, a1], null)
			if ok == false and a2 != 0:
				_jump(a2)
			else:
				ip += 1
		0x0033:
			var collect: Variant = _battle_call("collect_get", [evt_id], 0)
			if int(collect) != 0:
				PALState.collect_value = int(PALState.collect_value) + int(collect)
				ip += 1
			else:
				_jump(a0)
		0x0034:
			if int(PALState.collect_value) > 0:
				var got: Variant = _battle_call("collect_to_item", [], null)
				if got == null:
					# 无战斗代理时的近似：按 sdlpal 从 store 0 抽一件物品
					var idx := clampi(randi_range(1, mini(9, int(PALState.collect_value))) - 1, 0, 8)
					var store_item := _store_item(0, idx)
					if store_item != 0:
						_add_item(store_item, 1)
					PALState.collect_value = int(PALState.collect_value) - (idx + 1)
				ip += 1
			else:
				_jump(a0)
		0x0039:
			_battle_call("drain_enemy_hp", [evt_id, a0])
			_pr_set(9, _moving_role(), mini(_pr_get(9, _moving_role()) + a0, _pr_get(7, _moving_role())))
			ip += 1
		0x003A:
			var is_boss: Variant = _battle_call("is_boss", [], false)
			if bool(is_boss):
				_jump(a0)
			else:
				_battle_call("flee", [])
				ip += 1
		0x0042:
			var role42 := evt_id if _s16(a2) <= 0 else _s16(a2) - 1
			_battle_call("simulate_magic", [role42, a0, a1])
			ip += 1
		0x005B:
			_battle_call("halve_enemy_hp", [evt_id, a0])
			ip += 1
		0x005C:
			_battle_call("set_hiding_time", [a0])
			ip += 1
		0x005E:
			var poisoned: Variant = _battle_call("enemy_poisoned", [evt_id, a0], false)
			if not bool(poisoned):
				_jump(a1)
			else:
				ip += 1
		0x0060:
			_battle_call("kill_enemy", [evt_id])
			ip += 1
		0x0064:
			var over: Variant = _battle_call("enemy_hp_percent_gt", [evt_id, a0], false)
			if bool(over):
				_jump(a1)
			else:
				ip += 1
		0x0066:
			_battle_call("simulate_magic", [evt_id, a0, a1 * 5])
			ip += 1
		0x0067:
			_battle_call("set_enemy_magic", [evt_id, a0, a1 if a1 != 0 else 10])
			ip += 1
		0x0068:
			var enemy_turn: Variant = _battle_call("is_enemy_turn", [], false)
			if bool(enemy_turn):
				_jump(a0)
			else:
				ip += 1
		0x0069:
			_battle_call("enemy_escape", [])
			ip += 1
		0x006A:
			_battle_call("steal", [evt_id, a0])
			ip += 1
		0x006B:
			_battle_call("blow", [_s16(a0)])
			ip += 1
		0x0088:
			var money := mini(int(PALState.cash), 5000)
			PALState.cash = int(PALState.cash) - money
			_magic_damage_override(a0, money * 2 / 5)
			ip += 1
		0x0089:
			_battle_call("set_result", [a0])
			PALState.vars["battle_result"] = a0
			ip += 1
		0x008A:
			_battle_call("set_auto_battle", [])
			PALState.vars["auto_battle"] = true
			ip += 1
		0x0091:
			var first: Variant = _battle_call("enemy_is_first", [evt_id], true)
			if not bool(first):
				_jump(a0)
			else:
				ip += 1
		0x0092:
			_battle_call("pre_magic_anim", [a0])
			ip += 1
		0x009C:
			var can: Variant = _battle_call("divide", [evt_id, a0], false)
			if not bool(can) and a1 != 0:
				_jump(a1)
			else:
				ip += 1
		0x009E:
			var summoned: Variant = _battle_call("summon", [evt_id, a0, a1], false)
			if not bool(summoned) and a2 != 0:
				_jump(a2)
			else:
				ip += 1
		0x009F:
			_battle_call("transform", [evt_id, a0])
			ip += 1
		_:
			_log_unknown(op)
			ip += 1


# ---------------------------------------------------------------- 结束/跳转

func _finish(next: int = -1) -> void:
	if next >= 0:
		next_entry = next
	if _stack.is_empty():
		ended = true
	else:
		var frame: Array = _stack.pop_back()
		ip = int(frame[0])
		last_event_object_id = int(frame[1])


func _jump(target: int) -> void:
	if target == 0:
		_finish()
	else:
		ip = target


func _s16(v: int) -> int:
	return v - 0x10000 if v >= 0x8000 else v


# ---------------------------------------------------------------- 目标/场景解析

## pCurrent 的解析：0 或 0xFFFF → 触发本脚本的事件对象；否则 op0（含 Dream 2.11 hack）。
func _target_id(a0: int) -> int:
	if a0 == 0 or a0 == 0xFFFF:
		return last_event_object_id
	var i := a0
	if i > 0x9000:
		i -= 0x9000
	return i


func _scene_no() -> int:
	return int(PALState.scene)


## 事件对象是否属于当前场景（0x0081/0x0083/0x0084 用）。
## sdlpal: id > Scene[n-1].wEventObjectIndex && id <= Scene[n].wEventObjectIndex；
## world.evt_start/evt_end 正是这两个 0-based 下标。
func _in_current_scene(id: int) -> bool:
	if id <= 0:
		return false
	if world != null:
		var start = world.get("evt_start")
		var end = world.get("evt_end")
		if start != null and end != null:
			return int(id) > int(start) and int(id) <= int(end)
	var sss := PALState.data
	if sss != null:
		var n := int(PALState.scene)
		var start_i := 0
		var end_i := sss.events.size()
		if n - 1 >= 0 and n - 1 < sss.scenes.size():
			start_i = int(sss.scenes[n - 1][PalData.SC_EVENT_START])
		if n >= 0 and n < sss.scenes.size():
			end_i = int(sss.scenes[n][PalData.SC_EVENT_START])
		return id > start_i and id <= end_i
	return true


# ---------------------------------------------------------------- 事件对象字段

func _get_event_word(id: int, field: int) -> int:
	var e := NpcMove.get_event(world, id)
	if e.size() <= field:
		return 0
	return e[field]


func _set_event_word(id: int, field: int, value: int) -> void:
	if id <= 0:
		return
	var e := NpcMove.get_event(world, id)
	if e.is_empty() or e.size() <= field:
		return
	e[field] = value
	NpcMove.set_event(world, id, e)


# ---------------------------------------------------------------- 空闲帧计数（0x0002/0x0003）

func _idle_inc(evt_id: int) -> int:
	if evt_id > 0:
		var e := NpcMove.get_event(world, evt_id)
		if not e.is_empty() and e.size() > NpcMove.EO_IDLE_FRAME:
			e[NpcMove.EO_IDLE_FRAME] = e[NpcMove.EO_IDLE_FRAME] + 1
			NpcMove.set_event(world, evt_id, e)
			return e[NpcMove.EO_IDLE_FRAME]
	_idle_counter += 1
	return _idle_counter


func _idle_reset(evt_id: int) -> void:
	if evt_id > 0:
		var e := NpcMove.get_event(world, evt_id)
		if not e.is_empty() and e.size() > NpcMove.EO_IDLE_FRAME:
			e[NpcMove.EO_IDLE_FRAME] = 0
			NpcMove.set_event(world, evt_id, e)
	_idle_counter = 0


# ---------------------------------------------------------------- 队伍

func _party_roles() -> Array[int]:
	var out: Array[int] = []
	var n := clampi(int(PALState.max_party_member_index), 0, MAX_PLAYABLE_PLAYER_ROLES - 1)
	for i in range(n + 1):
		if i < PALState.party.size():
			var m = PALState.party[i]
			if m is Dictionary:
				out.append(int(m.get("role", 0)))
	if out.is_empty():
		out.append(0)
	return out


func _max_party_index() -> int:
	return _party_roles().size() - 1


func _moving_role() -> int:
	return int(_party_roles()[0])


func _set_party(r0: int, r1: int, r2: int) -> void:
	# world 负责写 PALState.party / max_party_member_index
	if world != null and world.has_method("script_set_party"):
		world.call("script_set_party", r0, r1, r2)
	else:
		var party: Array = []
		for v in [r0, r1, r2]:
			if v != 0:
				party.append({"role": v - 1, "x": 160, "y": 112, "frame": 0, "image_offset": 0})
		if party.is_empty():
			party.append({"role": 0, "x": 160, "y": 112, "frame": 0, "image_offset": 0})
		PALState.party = party
		PALState.max_party_member_index = party.size() - 1


# ---------------------------------------------------------------- 视口（0x007F）

func _do_viewport(a0: int, a1: int, a2: int) -> void:
	if a0 == 0 and a1 == 0:
		# 恢复正常视口：viewport = 队伍绝对位置 − (160,112)，party[0] 回屏幕中心
		var abs_pos := PALState.viewport
		if not PALState.party.is_empty():
			var p: Dictionary = PALState.party[0]
			abs_pos += Vector2i(int(p["x"]), int(p["y"]))
			p["x"] = 160
			p["y"] = 112
		PALState.viewport = abs_pos - Vector2i(160, 112)
		ip += 1
		return
	if a2 == 0xFFFF:
		# 瞬移视口到 tile(a0,a1)（party[0] 回到 (160,112)）
		PALState.viewport = Vector2i(a0 * 32 - 160, a1 * 16 - 112)
		if not PALState.party.is_empty():
			var p: Dictionary = PALState.party[0]
			p["x"] = 160
			p["y"] = 112
		ip += 1
		return
	# 逐帧平移 a2 次（a2=0 按 1 次处理）
	_start_move("viewport", {"dx": _s16(a0), "dy": _s16(a1), "left": a2 if a2 > 0 else 1})


# ---------------------------------------------------------------- 战斗/菜单/RNG/选择

func _normalize_battle_result(result: Variant) -> int:
	if result is String:
		match result:
			"won", "win", "victory":
				return BATTLE_WON
			"lost", "lose", "defeat":
				return BATTLE_LOST
			"fled", "flee", "escaped", "escape":
				return BATTLE_FLEED
			_:
				return BATTLE_TERMINATED
	if result is int or result is float:
		return int(result)
	return BATTLE_TERMINATED


func _start_battle(team_id: int, lost_entry: int, flee_entry: int) -> void:
	PALState.in_battle = true
	PALState.vars["battle_team"] = team_id
	var flee_disabled := flee_entry == 0
	if world != null and world.has_method("request_battle"):
		_pending_battle = PackedInt32Array([team_id, lost_entry, flee_entry])
		waiting_battle = true
		world.call("request_battle", team_id, flee_disabled, false)
	else:
		# 尚无战斗系统：按“胜利”继续（记录缺失 hook）
		_note_missing_hook("request_battle")
		PALState.in_battle = false
		ip += 1


func _start_confirm(no_entry: int) -> void:
	if world != null and world.has_method("confirm_menu"):
		var yes = world.call("confirm_menu")
		if bool(yes):
			ip += 1
		else:
			_jump(no_entry)
		return
	if world != null and world.has_method("request_confirm"):
		_pending_choice = no_entry
		waiting_choice = true
		world.call("request_confirm")
		return
	# 旧行为：无 UI 时默认“是”
	if world != null and world.has_method("script_confirm_menu"):
		world.call("script_confirm_menu")
	else:
		_note_missing_hook("confirm_menu")
	ip += 1


func _start_wait_key() -> void:
	if world != null and world.has_method("request_wait_key"):
		waiting_key = true
		world.call("request_wait_key")
	else:
		_note_missing_hook("request_wait_key")
		wait_frames = 60
		ip += 1


func _start_load_game() -> void:
	if world != null and world.has_method("request_load_game"):
		_pending_menu_finish = true
		waiting_menu = true
		world.call("request_load_game")
	else:
		_note_missing_hook("request_load_game")
		_stack.clear()
		_finish()


func _open_shop(store_id: int, is_buy: bool) -> void:
	if world != null and world.has_method("request_shop"):
		# 异步商店（世界完成后需调用 vm.resume_menu()）
		waiting_menu = true
		world.call("request_shop", store_id, is_buy)
		return
	if world != null and is_buy and world.has_method("script_shop"):
		# Lead 提供的同步商店（内部模态，关闭后继续；VM 不等待）
		world.call("script_shop", store_id)
		ip += 1
		return
	if world != null and world.has_method("open_menu"):
		world.call("open_menu", "shop" if is_buy else "sell")
		ip += 1
		return
	_note_missing_hook("script_shop")
	ip += 1


func _play_rng(start_frame: int, frames: int, speed: int) -> void:
	var rng_id := _pending_rng
	if world != null and world.has_method("request_rng_full"):
		waiting_rng = true
		world.call("request_rng_full", rng_id, start_frame,
			frames if frames > 0 else -1, speed if speed > 0 else 16)
		return
	if world != null and world.has_method("request_rng"):
		# Lead 的 world.request_rng(rng_id) 是“播放后立即返回”，没有完成回调，
		# 因此这里不等帧（原版 PAL_RNGPlay 阻塞到播完）。帧数/速度参数丢弃。
		world.call("request_rng", rng_id)
		ip += 1
		return
	_note_missing_hook("request_rng")
	ip += 1


# ---------------------------------------------------------------- 战斗代理

func _battle_call(method: String, args: Array, fallback: Variant = null) -> Variant:
	if battle_proxy != null and is_instance_valid(battle_proxy) and battle_proxy.has_method(method):
		return battle_proxy.callv(method, args)
	_note_missing_hook("battle." + method)
	return fallback


# ---------------------------------------------------------------- PLAYERROLES 字寻址
# sdlpal 用 HACKHACK 把 PLAYERROLES 当 WORD 数组：p[field * 6 + role]。
# 这里按 global.h 字段顺序建立 field 下标 → (字段名, 子表行) 的映射；
# 二维字段（equipment[6]、elemental_resistance[5]、magic[32]）用行号。
# PALState.roles 由 Lead 从 DATA.MKF#3 装载；结构未定时兼容
# 「平铺 Array/PackedInt32Array(rows*6)」「嵌套 Array[row][role]」「Dictionary row→…」。

func _build_pr_index() -> void:
	_pr_index.clear()
	for k in ["avatar", "sprite_in_battle", "sprite_in_scene", "name", "attack_all", "unknown1",
			"level", "max_hp", "max_mp", "hp", "mp"]:
		_pr_index.append([k, -1])
	for r in range(MAX_PLAYER_EQUIPMENTS):
		_pr_index.append(["equipment", r])
	for k in ["attack_strength", "magic_strength", "defense", "dexterity", "flee_rate",
			"poison_resistance"]:
		_pr_index.append([k, -1])
	for r in range(5):
		_pr_index.append(["elemental_resistance", r])
	for k in ["unknown2", "unknown3", "unknown4", "covered_by"]:
		_pr_index.append([k, -1])
	for r in range(MAX_PLAYER_MAGICS):
		_pr_index.append(["magic", r])
	for k in ["walk_frames", "cooperative_magic", "unknown5", "unknown6", "death_sound",
			"attack_sound", "weapon_sound", "critical_sound", "magic_sound", "cover_sound",
			"dying_sound"]:
		_pr_index.append([k, -1])


func _roles_dict() -> Dictionary:
	var d = PALState.roles
	if d is Dictionary:
		return d
	return {}


func _pr_get(field: int, role: int) -> int:
	if field < 0 or field >= _pr_index.size():
		return 0
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return 0
	var spec: Array = _pr_index[field]
	var d := _roles_dict()
	return _nested_get_arr(d.get(spec[0]), int(spec[1]), role)


func _pr_set(field: int, role: int, value: int) -> void:
	if field < 0 or field >= _pr_index.size():
		return
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return
	var spec: Array = _pr_index[field]
	var key: String = spec[0]
	var d := _roles_dict()
	d[key] = _nested_set_arr(d.get(key), int(spec[1]), role, value)
	PALState.roles = d


func _eq_dict(part: int) -> Dictionary:
	var arr = PALState.equipment_effect
	if not (arr is Array):
		arr = []
	var a: Array = arr
	while a.size() <= part:
		a.append({})
	var v = a[part]
	if not (v is Dictionary):
		v = {}
		a[part] = v
	PALState.equipment_effect = a
	return v


func _eq_get(part: int, field: int, role: int) -> int:
	if field < 0 or field >= _pr_index.size() or part < 0 or part > MAX_PLAYER_EQUIPMENTS:
		return 0
	var spec: Array = _pr_index[field]
	var d := _eq_dict(part)
	return _nested_get_arr(d.get(spec[0]), int(spec[1]), role)


func _eq_set(part: int, field: int, role: int, value: int) -> void:
	if field < 0 or field >= _pr_index.size() or part < 0 or part > MAX_PLAYER_EQUIPMENTS:
		return
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return
	var spec: Array = _pr_index[field]
	var key: String = spec[0]
	var d := _eq_dict(part)
	d[key] = _nested_set_arr(d.get(key), int(spec[1]), role, value)


static func _index_get(v: Variant, i: int) -> int:
	if v == null:
		return 0
	if v is Array:
		var a: Array = v
		return int(a[i]) if i >= 0 and i < a.size() else 0
	if v is PackedInt32Array:
		var p: PackedInt32Array = v
		return p[i] if i >= 0 and i < p.size() else 0
	if v is Dictionary:
		var d: Dictionary = v
		return int(d.get(i, d.get(str(i), 0)))
	return int(v)


static func _index_set(v: Variant, i: int, value: int) -> Variant:
	if i < 0:
		return v
	if v is Array:
		var a: Array = v
		while a.size() <= i:
			a.append(0)
		a[i] = value
		return a
	if v is PackedInt32Array:
		var a: Array = []
		a.assign(v)
		while a.size() <= i:
			a.append(0)
		a[i] = value
		return a
	if v is Dictionary:
		var d: Dictionary = v
		d[i] = value
		return d
	var a2: Array = []
	while a2.size() <= i:
		a2.append(0)
	a2[i] = value
	return a2


static func _nested_get_arr(v: Variant, row: int, role: int) -> int:
	if v == null:
		return 0
	if row < 0:
		return _index_get(v, role)
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return 0
		var first = a[0]
		if first is Array or first is PackedInt32Array or first is Dictionary:
			return _index_get(a[row] if row < a.size() else null, role)
		return _index_get(a, row * MAX_PLAYER_ROLES + role)
	if v is Dictionary:
		var d: Dictionary = v
		var sub = d.get(row, d.get(str(row), null))
		return _index_get(sub, role)
	if v is PackedInt32Array:
		return _index_get(v, row * MAX_PLAYER_ROLES + role)
	return 0


static func _nested_set_arr(v: Variant, row: int, role: int, value: int) -> Variant:
	if row < 0:
		return _index_set(v, role, value)
	if v is Dictionary:
		var d: Dictionary = v
		var sub = d.get(row, d.get(str(row), null))
		d[row] = _index_set(sub, role, value)
		return d
	if v is Array:
		var a: Array = v
		if a.is_empty():
			var flat: Array = []
			while flat.size() <= row * MAX_PLAYER_ROLES + role:
				flat.append(0)
			flat[row * MAX_PLAYER_ROLES + role] = value
			return flat
		var first = a[0]
		if first is Array or first is PackedInt32Array or first is Dictionary:
			while a.size() <= row:
				a.append(null)
			a[row] = _index_set(a[row], role, value)
			return a
		while a.size() <= row * MAX_PLAYER_ROLES + role:
			a.append(0)
		a[row * MAX_PLAYER_ROLES + role] = value
		return a
	if v is PackedInt32Array:
		var arr: Array = []
		arr.assign(v)
		while arr.size() <= row * MAX_PLAYER_ROLES + role:
			arr.append(0)
		arr[row * MAX_PLAYER_ROLES + role] = value
		return arr
	var flat2: Array = []
	while flat2.size() <= row * MAX_PLAYER_ROLES + role:
		flat2.append(0)
	flat2[row * MAX_PLAYER_ROLES + role] = value
	return flat2


# ---------------------------------------------------------------- PALState 兼容层
# Lead 的 pal_state.gd 目前只有字段骨架（方法为 TODO）。这里优先调用 PALState 的方法，
# 方法不存在时用本文件内的等价实现，保证 VM 可独立跑通；Lead 补齐后自动切换。

func _st_has(method: String) -> bool:
	return PALState != null and PALState.has_method(method)


func _st_call(method: String, args: Array) -> Variant:
	return PALState.callv(method, args)


# ---- 背包 ----

func _inv_arr() -> Array:
	var inv = PALState.inventory
	if inv is Array:
		return inv
	return []


func _inv_item(slot: Variant) -> int:
	if slot is Dictionary:
		return int(slot.get("item", 0))
	return 0


func _inv_amount(slot: Variant) -> int:
	if slot is Dictionary:
		return int(slot.get("amount", 0))
	return 0


func _get_item_amount(item: int) -> int:
	if _st_has("get_item_amount"):
		return int(_st_call("get_item_amount", [item]))
	var inv := _inv_arr()
	for slot in inv:
		if _inv_item(slot) == 0:
			break
		if _inv_item(slot) == item:
			return _inv_amount(slot)
	return 0


func _count_item(item: int) -> int:
	if _st_has("count_item"):
		return int(_st_call("count_item", [item]))
	if item == 0:
		return 0
	var count := _get_item_amount(item)
	for r in _party_roles():
		for j in range(MAX_PLAYER_EQUIPMENTS):
			if _pr_get(PR_EQUIP_ROW + j, int(r)) == item:
				count += 1
	return count


func _add_item(item: int, num: int) -> int:
	if _st_has("add_item"):
		return int(_st_call("add_item", [item, num]))
	if item == 0:
		return 0
	if num == 0:
		num = 1
	var inv := _inv_arr()
	var idx := -1
	for i in range(inv.size()):
		if _inv_item(inv[i]) == item:
			idx = i
			break
		if _inv_item(inv[i]) == 0:
			break
	if num > 0:
		if idx >= 0:
			var slot = inv[idx]
			slot["amount"] = mini(99, _inv_amount(slot) + num)
		else:
			if inv.size() >= MAX_INVENTORY:
				return 0
			inv.append({"item": item, "amount": mini(num, 99), "in_use": 0})
		PALState.inventory = inv
		return 1
	if idx < 0:
		return 0
	var slot2 = inv[idx]
	var amount := _inv_amount(slot2)
	var need := -num
	if amount < need:
		var shortage := need - amount
		slot2["amount"] = 0
		return -shortage
	slot2["amount"] = amount - need
	return 1


# ---- HP/MP/状态/毒/仙术/升级 ----

func _hpmp_generic(all_flag: int, hp: int, mp: int) -> bool:
	var any := false
	if all_flag != 0:
		for r in _party_roles():
			if _increase_hpmp(int(r), _s16(hp), _s16(mp)):
				any = true
		return any
	return _increase_hpmp(last_event_object_id, _s16(hp), _s16(mp))


func _increase_hpmp(role: int, hp: int, mp: int) -> bool:
	if _st_has("increase_hpmp"):
		return bool(_st_call("increase_hpmp", [role, hp, mp]))
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return false
	var cur_hp := _pr_get(9, role)
	if cur_hp <= 0:
		return false
	var orig_hp := cur_hp
	var orig_mp := _pr_get(10, role)
	var max_hp := _pr_get(7, role)
	var max_mp := _pr_get(8, role)
	cur_hp = clampi(cur_hp + hp, 0, max_hp)
	var cur_mp := clampi(orig_mp + mp, 0, max_mp)
	_pr_set(9, role, cur_hp)
	_pr_set(10, role, cur_mp)
	return cur_hp != orig_hp or cur_mp != orig_mp


func _revive(all_flag: int, percent: int) -> void:
	var roles: Array[int] = []
	if all_flag != 0:
		roles = _party_roles()
		script_success = false
	else:
		roles = [last_event_object_id] as Array[int]
	for r in roles:
		var role := int(r)
		if _pr_get(9, role) == 0:
			_pr_set(9, role, _pr_get(7, role) * percent / 10)
			_cure_poison_level(role, 3)
			for st in range(STATUS_ALL):
				_remove_status(role, st)
			script_success = true
		elif all_flag == 0:
			script_success = false


func _unequip_all(role: int, part_1based: int) -> void:
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return
	if part_1based == 0:
		for j in range(MAX_PLAYER_EQUIPMENTS):
			var w := _pr_get(PR_EQUIP_ROW + j, role)
			if w != 0:
				_add_item(w, 1)
				_pr_set(PR_EQUIP_ROW + j, role, 0)
			_remove_equipment_effect(role, j)
	else:
		var j := part_1based - 1
		var w := _pr_get(PR_EQUIP_ROW + j, role)
		if w != 0:
			_remove_equipment_effect(role, j)
			_add_item(w, 1)
			_pr_set(PR_EQUIP_ROW + j, role, 0)


func _equip_item(part: int, item: int, role: int) -> void:
	_cur_equip_part = part
	_remove_equipment_effect(role, part)
	if _pr_get(PR_EQUIP_ROW + part, role) == item:
		return
	var old := _pr_get(PR_EQUIP_ROW + part, role)
	_pr_set(PR_EQUIP_ROW + part, role, item)
	# 背包中该物品仅 1 件且旧装备不在背包里 → 直接替换（与 sdlpal 一致）
	var idx := -1
	var inv := _inv_arr()
	for i in range(inv.size()):
		if _inv_item(inv[i]) == item:
			idx = i
			break
		if _inv_item(inv[i]) == 0:
			break
	if idx >= 0 and idx < MAX_INVENTORY and _inv_amount(inv[idx]) == 1 \
			and old != 0 and _get_item_amount(old) == 0:
		var slot = inv[idx]
		slot["item"] = old
		PALState.inventory = inv
	else:
		_add_item(item, -1)
		if old != 0:
			_add_item(old, 1)
	_last_unequipped_item = old
	PALState.vars["last_unequipped_item"] = old


func _remove_equipment_effect(role: int, part: int) -> void:
	if _st_has("remove_equipment_effect"):
		_st_call("remove_equipment_effect", [role, part])
		return
	for field in range(_pr_index.size()):
		_eq_set(part, field, role, 0)


func _status_container() -> Array:
	var st = PALState.status
	if not (st is Array):
		st = []
	var a: Array = st
	while a.size() < MAX_PLAYER_ROLES:
		a.append([])
	for r in range(MAX_PLAYER_ROLES):
		if not (a[r] is Array):
			a[r] = []
		var row: Array = a[r]
		while row.size() < STATUS_ALL:
			row.append(0)
	PALState.status = a
	return a


func _status_get(role: int, st: int) -> int:
	if role < 0 or role >= MAX_PLAYER_ROLES or st < 0 or st >= STATUS_ALL:
		return 0
	var a := _status_container()
	return int(a[role][st])


func _status_set(role: int, st: int, rounds: int) -> void:
	if role < 0 or role >= MAX_PLAYER_ROLES or st < 0 or st >= STATUS_ALL:
		return
	var a := _status_container()
	a[role][st] = rounds


func _set_status(role: int, st: int, rounds: int) -> bool:
	if _st_has("set_player_status"):
		return bool(_st_call("set_player_status", [role, st, rounds]))
	if st == 0 or st == 2 or st == 3:
		if _status_get(role, st) == 0:
			_status_set(role, st, rounds)
		return true
	_status_set(role, st, rounds)
	return true


func _remove_status(role: int, st: int) -> void:
	if _st_has("remove_player_status"):
		_st_call("remove_player_status", [role, st])
		return
	_status_set(role, st, 0)


func _player_state_op(op: int, a0: int, a1: int) -> void:
	match op:
		0x002B:
			_cure_poison_kind(last_event_object_id, a1)
		0x002C:
			_cure_poison_level(last_event_object_id, a1)
		0x002D:
			if not _set_status(last_event_object_id, a0, a1):
				script_success = false
		0x002F:
			_remove_status(last_event_object_id, a0)


func _party_index_of_role(role: int) -> int:
	var roles := _party_roles()
	for i in range(roles.size()):
		if roles[i] == role:
			return i
	return -1


func _poison_slots(role: int) -> Array:
	# 返回该角色在 [MAX_POISONS] 列上的槽位（Dictionary 引用，可直接改）
	var pi := _party_index_of_role(role)
	if pi < 0 or pi >= MAX_PLAYABLE_PLAYER_ROLES:
		return []
	var ps = PALState.poison_status
	if not (ps is Array):
		ps = []
	var a: Array = ps
	while a.size() < MAX_POISONS:
		a.append([])
	for i in range(MAX_POISONS):
		var row = a[i]
		if not (row is Array):
			row = []
			a[i] = row
		var r: Array = row
		while r.size() < MAX_PLAYABLE_PLAYER_ROLES:
			r.append({"poison_id": 0, "script": 0})
	PALState.poison_status = a
	var out: Array = []
	for i in range(MAX_POISONS):
		out.append(a[i][pi])
	return out


func _add_poison(role: int, poison_id: int) -> void:
	if _st_has("add_poison"):
		_st_call("add_poison", [role, poison_id])
		return
	if poison_id == 0:
		return
	var slots := _poison_slots(role)
	if slots.is_empty():
		return
	for s in slots:
		if int(s.get("poison_id", 0)) == poison_id:
			return
	for s in slots:
		if int(s.get("poison_id", 0)) == 0:
			s["poison_id"] = poison_id
			return


func _cure_poison_kind(role: int, poison_id: int) -> void:
	if _st_has("cure_poison_by_kind"):
		_st_call("cure_poison_by_kind", [role, poison_id])
		return
	for s in _poison_slots(role):
		if int(s.get("poison_id", 0)) == poison_id:
			s["poison_id"] = 0
			s["script"] = 0


func _poison_level(poison_id: int) -> int:
	if poison_id == 0:
		return 0
	if PALTables != null and PALTables.ready_flag:
		var obj: Dictionary = PALTables.poison_obj_of(poison_id)
		if not obj.is_empty():
			return int(obj.get("poison_level", 1))
	return 1  # 对象表未装载时按 1 级毒处理 [inf]


func _cure_poison_level(role: int, max_level: int) -> void:
	if _st_has("cure_poison_by_level"):
		_st_call("cure_poison_by_level", [role, max_level])
		return
	for s in _poison_slots(role):
		var pid := int(s.get("poison_id", 0))
		if pid != 0 and _poison_level(pid) <= max_level:
			s["poison_id"] = 0
			s["script"] = 0


func _is_poisoned_kind(role: int, poison_id: int) -> bool:
	if _st_has("is_poisoned_by_kind"):
		return bool(_st_call("is_poisoned_by_kind", [role, poison_id]))
	for s in _poison_slots(role):
		if int(s.get("poison_id", 0)) == poison_id:
			return true
	return false


func _is_poisoned_level(role: int, min_level: int) -> bool:
	if _st_has("is_poisoned_by_level"):
		return bool(_st_call("is_poisoned_by_level", [role, min_level]))
	for s in _poison_slots(role):
		var pid := int(s.get("poison_id", 0))
		if pid == 0:
			continue
		var lvl := _poison_level(pid)
		if lvl >= 99:
			continue
		if lvl >= min_level:
			return true
	return false


func _player_poison_resist(role: int) -> int:
	if _st_has("get_player_poison_resistance"):
		return int(_st_call("get_player_poison_resistance", [role]))
	return _pr_get(PR_POISON_RES, role)


func _add_magic(role: int, magic: int) -> bool:
	if _st_has("add_magic"):
		return bool(_st_call("add_magic", [role, magic]))
	for i in range(MAX_PLAYER_MAGICS):
		if _pr_get(32 + i, role) == magic:
			return false
	for i in range(MAX_PLAYER_MAGICS):
		if _pr_get(32 + i, role) == 0:
			_pr_set(32 + i, role, magic)
			return true
	return false


func _remove_magic(role: int, magic: int) -> void:
	if _st_has("remove_magic"):
		_st_call("remove_magic", [role, magic])
		return
	for i in range(MAX_PLAYER_MAGICS):
		if _pr_get(32 + i, role) == magic:
			_pr_set(32 + i, role, 0)
			return


func _player_level_up(role: int, levels: int) -> void:
	if _st_has("player_level_up"):
		_st_call("player_level_up", [role, levels])
		return
	if role < 0 or role >= MAX_PLAYER_ROLES or levels <= 0:
		return
	_pr_set(6, role, mini(MAX_LEVELS, _pr_get(6, role) + levels))
	for i in range(levels):
		_pr_set(7, role, mini(999, _pr_get(7, role) + 10 + randi_range(0, 7)))
		_pr_set(8, role, mini(999, _pr_get(8, role) + 8 + randi_range(0, 5)))
		_pr_set(PR_ATK, role, mini(999, _pr_get(PR_ATK, role) + 4 + randi_range(0, 1)))
		_pr_set(PR_MAG, role, mini(999, _pr_get(PR_MAG, role) + 4 + randi_range(0, 1)))
		_pr_set(PR_DEF, role, mini(999, _pr_get(PR_DEF, role) + 2 + randi_range(0, 1)))
		_pr_set(PR_DEX, role, mini(999, _pr_get(PR_DEX, role) + 2 + randi_range(0, 1)))
		_pr_set(PR_FLEE, role, mini(999, _pr_get(PR_FLEE, role) + 2))


# ---------------------------------------------------------------- 数据补丁 / 辅助

## 0x0090：改 SSS 块 2 的对象 WORD（PALTables.objects 现在是已解析表，直接改其 data）。
func _patch_object_word(obj_id: int, word_index: int, value: int) -> void:
	if obj_id <= 0 or word_index < 0 or word_index >= 7:
		return
	if PALTables != null and PALTables.ready_flag and obj_id < PALTables.objects.size():
		var o = PALTables.objects[obj_id]
		if o is Dictionary and o.get("data") is PackedInt32Array:
			var arr: PackedInt32Array = o["data"]
			arr[word_index] = value
			o["data"] = arr
	elif data != null:
		var off := (obj_id * 14) + word_index * 2
		if off + 1 < data.objects_raw.size():
			var raw := data.objects_raw
			raw[off] = value & 0xFF
			raw[off + 1] = (value >> 8) & 0xFF
			data.objects_raw = raw
	# 同时记录到 PALState.vars，便于菜单/战斗模块立即读到
	var ov = PALState.vars.get("object_word_override", {})
	if not (ov is Dictionary):
		ov = {}
	ov["%d:%d" % [obj_id, word_index]] = value
	PALState.vars["object_word_override"] = ov


## 0x0057/0x0088：仙术基础伤害（写 PALTables.magic_defs，并记录到 vars 便于战斗读取）。
func _magic_damage_override(magic_obj_id: int, damage: int) -> void:
	var ov = PALState.vars.get("magic_base_damage", {})
	if not (ov is Dictionary):
		ov = {}
	ov[magic_obj_id] = damage
	PALState.vars["magic_base_damage"] = ov
	if PALTables != null and PALTables.ready_flag:
		var md: Dictionary = PALTables.magic_def_for(magic_obj_id)
		if not md.is_empty():
			md["base_damage"] = damage


func _store_item(store_id: int, index: int) -> int:
	if PALTables == null or not PALTables.ready_flag:
		return 0
	var items: PackedInt32Array = PALTables.store_items(store_id)
	if index >= 0 and index < items.size():
		return int(items[index])
	return 0


# ---------------------------------------------------------------- 记录/日志

func _note_missing_hook(name: String) -> void:
	_missing_hooks[name] = int(_missing_hooks.get(name, 0)) + 1
	if debug and _missing_hooks[name] == 1:
		print("[ScriptVM] 缺少 World/战斗 hook: ", name)


func _log_unknown(op: int) -> void:
	_unknown_ops[op] = int(_unknown_ops.get(op, 0)) + 1
	if world != null:
		world.call("script_note_unknown", op, ip)
