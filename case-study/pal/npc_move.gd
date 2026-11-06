class_name NpcMove
extends RefCounted
## NPC / 队伍移动层 —— 移植 sdlpal `script.c` 前 500 行：
##   PAL_NPCWalkTo / PAL_NPCWalkOneStep / PAL_PartyWalkTo /
##   PAL_PartyRideEventObject / PAL_MonsterChasePlayer，
## 以及 `scene.c` 的 PAL_CheckObstacle（NPC/怪物侧使用）。
##
## 与 sdlpal 的差异（[inf] 推断/适配）：原版这些函数是**阻塞循环**，内部自己等帧；
## 本移植统一改成「一帧一步」的 `*_step()`，由 ScriptVM 的 `_waiting_move` 状态机逐帧
## 调用直到返回 true（到达），从而不阻塞 Godot 主循环。速度语义保持 sdlpal：
##   西/南 x−=2*speed，东 x+=2*speed；北/西 y−=1*speed，南/东 y+=1*speed。
##
## 数据模型（与 Lead 重构后的 world/PALState 对齐）：
##   - 事件对象 = `PALTables.sss.event(id)`，Array[int] 活表（1-based 全局 id），
##     字段下标同 `PalData.EO_*`；读出来就是引用，改完即生效。
##   - 队伍：`PALState.party[0] = {role,x,y,frame}` 是**屏幕坐标**（恒 (160,112)），
##     绝对坐标 = `PALState.viewport + party[0]`。移动队伍 = 移动 viewport。
##   - 足迹：`PALState.trail[i] = {x,y,dir}`（绝对坐标），供跟随者渲染。

const DIR_SOUTH := 0
const DIR_WEST := 1
const DIR_NORTH := 2
const DIR_EAST := 3

# EVENTOBJECT 字段（见 PalData.EO_*；这里直接复用 PalData 常量）
const EO_VANISH := PalData.EO_VANISH
const EO_X := PalData.EO_X
const EO_Y := PalData.EO_Y
const EO_LAYER := PalData.EO_LAYER
const EO_TRIGGER_SCRIPT := PalData.EO_TRIGGER_SCRIPT
const EO_AUTO_SCRIPT := PalData.EO_AUTO_SCRIPT
const EO_STATE := PalData.EO_STATE
const EO_TRIGGER_MODE := PalData.EO_TRIGGER_MODE
const EO_FRAMES := PalData.EO_FRAMES
const EO_DIRECTION := PalData.EO_DIRECTION
const EO_CUR_FRAME := PalData.EO_CUR_FRAME
const EO_IDLE_FRAME := PalData.EO_IDLE_FRAME
const EO_FRAMES_AUTO := PalData.EO_FRAMES_AUTO

const KIND_NPC := "npc"
const KIND_PARTY := "party"
const KIND_RIDE := "ride"
const KIND_VIEWPORT := "viewport"

static var _walk_phase: int = 0


static func _s16(v: int) -> int:
	return v - 0x10000 if v >= 0x8000 else v


static func _pos16(v: int) -> int:
	return posmod(v, 0x10000)


# ---------------------------------------------------------------- 事件对象读写

## 取事件对象活表（Array[int]）。id 为 1-based 全局事件对象号。
static func get_event(world: Node, id: int) -> Array:
	if id <= 0:
		return []
	var sss: PalData = null
	if world != null:
		var s = world.get("sss")
		if s is PalData:
			sss = s
	if sss == null and PALState.data != null:
		sss = PALState.data
	if sss == null:
		return []
	return sss.event(id)


## 事件对象是活表（Array 引用语义），通常无需写回；保留此函数用于语义清晰/兼容旧代码。
static func set_event(_world: Node, _id: int, _e: Array) -> void:
	pass


# ---------------------------------------------------------------- 队伍/视口读写

static func party_abs(world: Node) -> Vector2i:
	if PALState.party.is_empty():
		return PALState.viewport
	var p: Dictionary = PALState.party[0]
	return PALState.viewport + Vector2i(int(p["x"]), int(p["y"]))


static func party_x(world: Node) -> int:
	return party_abs(world).x


static func party_y(world: Node) -> int:
	return party_abs(world).y


## 把队伍绝对位置设为 (px,py)：移动 viewport，party[0] 屏幕坐标保持不动。
## 注意：脚本驱动的队伍移动**不做视口钳制**（对齐 sdlpal PAL_PartyWalkTo，允许越界），
## 钳制只发生在玩家自由移动时（world._update_movement）。
static func set_party_abs(world: Node, px: int, py: int) -> void:
	if PALState.party.is_empty():
		return
	var p: Dictionary = PALState.party[0]
	PALState.viewport = Vector2i(px - int(p["x"]), py - int(p["y"]))


static func move_viewport(world: Node, dx: int, dy: int) -> void:
	PALState.viewport += Vector2i(dx, dy)


static func _clamp(world: Node) -> void:
	if world != null and world.has_method("_clamp_viewport"):
		world.call("_clamp_viewport")


## 记录队伍足迹（sdlpal PAL_PartyWalkTo/PAL_PartyRideEventObject 里的 rgTrail 移位）。
static func push_trail(dir: int, abs_x: int = -1, abs_y: int = -1, offset_x: int = 0, offset_y: int = 0) -> void:
	if PALState.trail.is_empty():
		return
	var trail: Array = PALState.trail
	for i in range(trail.size() - 1, 0, -1):
		trail[i] = trail[i - 1].duplicate()
	if abs_x < 0 or abs_y < 0:
		var a := Vector2i(0, 0)
		if not PALState.party.is_empty():
			var p: Dictionary = PALState.party[0]
			a = PALState.viewport + Vector2i(int(p["x"]), int(p["y"]))
		abs_x = a.x
		abs_y = a.y
	trail[0] = {"x": abs_x + offset_x, "y": abs_y + offset_y, "dir": dir}


## 队伍行走动画（sdlpal PAL_UpdatePartyGestures 的 leader 帧序列 0,1,0,2）。
static func animate_party(world: Node, direction: int, walking: bool) -> void:
	if PALState.party.is_empty():
		return
	PALState.party_dir = direction
	if not walking:
		_walk_phase = 0
		PALState.party[0]["frame"] = direction * 3
		return
	_walk_phase = (_walk_phase + 1) % 4
	var leader := 0
	if (_walk_phase & 1) != 0:
		leader = (_walk_phase + 1) / 2
	PALState.party[0]["frame"] = direction * 3 + leader


# ---------------------------------------------------------------- 障碍判定

## 移植 scene.c: PAL_CheckObstacleWithRange（NPC/怪物侧）。
static func check_obstacle(world: Node, px: int, py: int, check_events: bool,
		self_id: int, check_range: bool) -> bool:
	if world == null:
		return false
	var map = world.get("current_map")
	if map == null:
		return false
	var off := Vector2i(160, 112)
	if not PALState.party.is_empty():
		var p: Dictionary = PALState.party[0]
		off = Vector2i(int(p["x"]), int(p["y"]))
	var block_x: int = off.x / 32
	var block_y: int = off.y / 16
	var x: int = px / 32
	var y: int = py / 16
	var h := 0
	if check_range:
		# sdlpal 这里 y 上限写成 2048（而非 2048/16），条件永不成立；按原样保留 [obs]。
		if x < block_x or x >= 2048 / 32 - block_x - 1 or y < block_y or y >= 2048 - block_y - 1:
			return true
	var xr: int = px % 32
	var yr: int = py % 16
	if xr + yr * 2 >= 16:
		if xr + yr * 2 >= 48:
			x += 1
			y += 1
		elif 32 - xr + yr * 2 < 16:
			x += 1
		elif 32 - xr + yr * 2 < 48:
			h = 1
		else:
			y += 1
	if map.is_blocked(x, y, h):
		return true
	if check_events:
		var evs := _scene_events(world)
		for id in evs:
			if id == self_id:
				continue
			var o: Array = get_event(world, id)
			if o.size() <= EO_STATE:
				continue
			if int(o[EO_STATE]) >= 2:
				if absi(int(o[EO_X]) - px) + absi(int(o[EO_Y]) - py) * 2 < 16:
					return true
	return false


## 当前场景事件对象 id 列表（使用 world.evt_start/evt_end；跨场景回落到 PALState.scene）。
static func _scene_events(world: Node) -> Array[int]:
	var out: Array[int] = []
	var sss: PalData = null
	if world != null:
		var s = world.get("sss")
		if s is PalData:
			sss = s
	if sss == null:
		sss = PALState.data
	if sss == null:
		return out
	var start_i := 0
	var end_i := sss.events.size()
	if world != null:
		var s0 = world.get("evt_start")
		var e0 = world.get("evt_end")
		if s0 != null and e0 != null:
			start_i = int(s0)
			end_i = int(e0)
	else:
		var n := int(PALState.scene)
		if n - 1 >= 0 and n - 1 < sss.scenes.size():
			start_i = int(sss.scenes[n - 1][PalData.SC_EVENT_START])
		if n >= 0 and n < sss.scenes.size():
			end_i = int(sss.scenes[n][PalData.SC_EVENT_START])
	for id in range(start_i + 1, end_i + 1):
		out.append(id)
	return out


# ---------------------------------------------------------------- NPC 单步/寻路

## 移植 PAL_NPCWalkOneStep（scene.c）。返回是否有效。
static func walk_one_step(world: Node, id: int, speed: int) -> void:
	var e := get_event(world, id)
	if e.is_empty():
		return
	_walk_one_step_in(e, speed)


static func _walk_one_step_in(e: Array, speed: int) -> void:
	if e.size() <= EO_CUR_FRAME:
		return
	var dir: int = int(e[EO_DIRECTION])
	var dx := -2 if (dir == DIR_WEST or dir == DIR_SOUTH) else 2
	var dy := -1 if (dir == DIR_WEST or dir == DIR_NORTH) else 1
	e[EO_X] = _pos16(int(e[EO_X]) + dx * speed)
	e[EO_Y] = _pos16(int(e[EO_Y]) + dy * speed)
	# 手势推进（scene.c 同源）
	var nframes: int = int(e[EO_FRAMES])
	if nframes > 0:
		e[EO_CUR_FRAME] = (int(e[EO_CUR_FRAME]) + 1) % (4 if nframes == 3 else nframes)
	elif e.size() > EO_FRAMES_AUTO and int(e[EO_FRAMES_AUTO]) > 0:
		e[EO_CUR_FRAME] = (int(e[EO_CUR_FRAME]) + 1) % int(e[EO_FRAMES_AUTO])


## 移植 PAL_NPCWalkTo 的一步。返回是否已到达目标格（到达时把当前帧归零）。
static func walk_to_step(world: Node, id: int, tx: int, ty: int, h: int, speed: int) -> bool:
	var e := get_event(world, id)
	if e.is_empty():
		return true
	var dest_x: int = tx * 32 + h * 16
	var dest_y: int = ty * 16 + h * 8
	var xo: int = dest_x - int(e[EO_X])
	var yo: int = dest_y - int(e[EO_Y])
	# 朝向：sdlpal 用 yOffset 先行判定
	if yo < 0:
		e[EO_DIRECTION] = DIR_WEST if xo < 0 else DIR_NORTH
	else:
		e[EO_DIRECTION] = DIR_SOUTH if xo < 0 else DIR_EAST
	if absi(xo) < speed * 2 or absi(yo) < speed * 2:
		e[EO_X] = dest_x
		e[EO_Y] = dest_y
	else:
		_walk_one_step_in(e, speed)
	if int(e[EO_X]) == dest_x and int(e[EO_Y]) == dest_y:
		e[EO_CUR_FRAME] = 0
		return true
	return false


# ---------------------------------------------------------------- 队伍移动

## 移植 PAL_PartyWalkTo 的一步。返回是否到达（目标为 tile 坐标 + h）。
static func party_walk_step(world: Node, tx: int, ty: int, h: int, speed: int) -> bool:
	var dest_x: int = tx * 32 + h * 16
	var dest_y: int = ty * 16 + h * 8
	var cur := party_abs(world)
	var xo: int = dest_x - cur.x
	var yo: int = dest_y - cur.y
	if xo == 0 and yo == 0:
		animate_party(world, int(PALState.party_dir), false)
		return true
	var dir := DIR_SOUTH
	if yo < 0:
		dir = DIR_WEST if xo < 0 else DIR_NORTH
	else:
		dir = DIR_SOUTH if xo < 0 else DIR_EAST
	push_trail(dir, cur.x, cur.y)
	var dx := xo if absi(xo) <= speed * 2 else (speed * 2 if xo > 0 else -speed * 2)
	var dy := yo if absi(yo) <= speed else (speed if yo > 0 else -speed)
	move_viewport(world, dx, dy)
	animate_party(world, dir, true)
	var now := party_abs(world)
	return now.x == dest_x and now.y == dest_y


## 移植 PAL_PartyRideEventObject 的一步：队伍与所骑事件对象同步位移。
static func party_ride_step(world: Node, id: int, tx: int, ty: int, h: int, speed: int) -> bool:
	var dest_x: int = tx * 32 + h * 16
	var dest_y: int = ty * 16 + h * 8
	var cur := party_abs(world)
	var xo: int = dest_x - cur.x
	var yo: int = dest_y - cur.y
	if xo == 0 and yo == 0:
		return true
	var dir := DIR_SOUTH
	if yo < 0:
		dir = DIR_WEST if xo < 0 else DIR_NORTH
	else:
		dir = DIR_SOUTH if xo < 0 else DIR_EAST
	var dx := xo if absi(xo) <= speed * 2 else (speed * 2 if xo > 0 else -speed * 2)
	var dy := yo if absi(yo) <= speed else (speed if yo > 0 else -speed)
	push_trail(dir, cur.x, cur.y, dx, dy)
	PALState.party_dir = dir
	move_viewport(world, dx, dy)
	var e := get_event(world, id)
	if not e.is_empty() and e.size() > EO_Y:
		e[EO_X] = _pos16(int(e[EO_X]) + dx)
		e[EO_Y] = _pos16(int(e[EO_Y]) + dy)
	var now := party_abs(world)
	return now.x == dest_x and now.y == dest_y


## 0x006E：队伍整体平移一步（原版直接改 viewport，party 相对屏幕位置不变）。
static func party_offset_step(world: Node, dx: int, dy: int, layer: int) -> void:
	var cur := party_abs(world)
	push_trail(int(PALState.party_dir), cur.x, cur.y)
	PALState.viewport += Vector2i(dx, dy)
	if dx != 0 or dy != 0:
		animate_party(world, int(PALState.party_dir), true)
	if layer != 0:
		PALState.layer = layer


# ---------------------------------------------------------------- 怪物追击

## 移植 PAL_MonsterChasePlayer 的一帧。
## 感知范围倍数来自 PALState.chase_range（脚本 0x0062/0x0063 修改）；
## floating=true 时忽略障碍；frame_num 用于「驱魔香原地打转」的半帧判定。
static func monster_chase_step(world: Node, id: int, speed: int, chase_range: int,
		floating: bool, frame_num: int) -> void:
	var e := get_event(world, id)
	if e.is_empty() or e.size() <= EO_CUR_FRAME:
		return
	var chase_global: int = int(PALState.chase_range)
	var monster_speed := 0
	if chase_global != 0:
		var pt := party_abs(world)
		var x: int = pt.x - int(e[EO_X])
		var y: int = pt.y - int(e[EO_Y])
		if x == 0:
			x = -1 if (randi() & 1) != 0 else 1
		if y == 0:
			y = -1 if (randi() & 1) != 0 else 1
		var prevx: int = int(e[EO_X])
		var prevy: int = int(e[EO_Y])
		# 当前所在格（半格 h 由偏移决定）
		var i: int = prevx % 32
		var j: int = prevy % 16
		var grid_x: int = prevx / 32
		var grid_y: int = prevy / 16
		var l := 0
		if i + j * 2 >= 16:
			if i + j * 2 >= 48:
				grid_x += 1
				grid_y += 1
			elif 32 - i + j * 2 < 16:
				grid_x += 1
			elif 32 - i + j * 2 < 48:
				l = 1
			else:
				grid_y += 1
		# sdlpal 把 prevx/prevy 改写成「吸附到半格中心」的值，障碍时回退到该值
		prevx = grid_x * 32 + l * 16
		prevy = grid_y * 16 + l * 8
		var near: bool = absi(x) + absi(y) * 2 < chase_range * 32 * chase_global
		if near:
			if x < 0:
				e[EO_DIRECTION] = DIR_WEST if y < 0 else DIR_SOUTH
			else:
				e[EO_DIRECTION] = DIR_NORTH if y < 0 else DIR_EAST
			var target_x: int = (int(e[EO_X]) + (x / absi(x)) * 16) if x != 0 else int(e[EO_X])
			var target_y: int = (int(e[EO_Y]) + (y / absi(y)) * 8) if y != 0 else int(e[EO_Y])
			if floating:
				monster_speed = speed
			else:
				if not check_obstacle(world, target_x, target_y, true, id, false):
					monster_speed = speed
				else:
					e[EO_X] = prevx
					e[EO_Y] = prevy
				# 四角微调：绕开卡住的拐角（sdlpal 原样）
				for k in range(4):
					match k:
						0:
							e[EO_X] = _pos16(int(e[EO_X]) - 4)
							e[EO_Y] = _pos16(int(e[EO_Y]) + 2)
						1:
							e[EO_X] = _pos16(int(e[EO_X]) - 4)
							e[EO_Y] = _pos16(int(e[EO_Y]) - 2)
						2:
							e[EO_X] = _pos16(int(e[EO_X]) + 4)
							e[EO_Y] = _pos16(int(e[EO_Y]) - 2)
						3:
							e[EO_X] = _pos16(int(e[EO_X]) + 4)
							e[EO_Y] = _pos16(int(e[EO_Y]) + 2)
					if check_obstacle(world, int(e[EO_X]), int(e[EO_Y]), false, 0, false):
						e[EO_X] = prevx
						e[EO_Y] = prevy
	else:
		# 驱魔香：每两帧转一次方向
		if (frame_num & 1) != 0:
			e[EO_DIRECTION] = (int(e[EO_DIRECTION]) + 1) % 4
	_walk_one_step_in(e, monster_speed)
