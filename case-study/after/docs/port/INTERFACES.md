# 完整移植架构与接口契约 v1

目标：把 sdlpal（GPL-3.0，`<LOCAL_PATH>`）的全部游戏逻辑模块化移植到
`<LOCAL_PATH>`（Godot 4.7.2，GDScript），数据格式以
`docs/rea/` 的 REA 证据为准。

## 0. 运行时单例（project.godot autoload）

| 单例名 | 脚本 | 职责 | 负责人 |
|---|---|---|---|
| `PALTables` | `pal/pal_tables.gd` | 只读数据表：Data.mkf 各块 + Word.dat + SSS + M.msg | Lead |
| `PALState` | `pal/pal_state.gd` | 可变全局状态（对应 sdlpal `GLOBALVARS`）+ 全部 global.c 工具函数 | Lead |
| `PALAudio` | `pal/pal_audio.gd` | BGM/音效/语音 | port-audio-text |
| `PALText` | `pal/text_db.gd` | 文本库：词条、消息取文、对白分页/控制码/图标 | port-audio-text |

均 `extends Node`，在 `_ready()`/`init_all()` 里装载。访问方式：`PALTables.xxx`、`PALState.xxx`。

## 1. PALTables（Lead 实现，只读）

```gdscript
var data_dir: String
var sss: PalData                 # 既有 SSS 表 + msgs
var data_mkf: MkfFile
var words: PackedStringArray      # Word.dat 565 条

# 结构体用 Dictionary（键名 = sdlpal 字段名去掉 w/rg 前缀，snake_case）
var player_roles: Dictionary     # 见 §5.1（默认值，来自 DATA.MKF #3）
var items: Array                 # 索引 1..n，OBJECT_ITEM
var object_players: Array         # OBJECT_PLAYER（索引 1..6 role）
var magics: Array                 # OBJECT_MAGIC
var magic_defs: Array             # DATA.MKF #4 tagMAGIC
var enemies: Array                # DATA.MKF #1 tagENEMY（enemy_def）
var enemy_teams: Array            # DATA.MKF #2，每项 PackedInt32Array(5)
var battle_fields: Array          # DATA.MKF #5 tagBATTLEFIELD
var battle_effect_index: Array    # DATA.MKF #11
var enemy_pos: Array              # DATA.MKF #13
var level_up_exp: Array           # DATA.MKF #14（6×100）
var level_up_magic: Array         # DATA.MKF #6（6×? tagLEVELUPMAGIC）
var stores: Array                 # DATA.MKF #0（每项字典 {items: PackedInt32Array(9)}）
var poisons: Array                # OBJECT_POISON
var poison_defs: Array            # 毒定义（若与 OBJECT 合并则同 poisons）

# 名称/词条
func word(id: int) -> String
func player_name(role: int) -> String      # role 0-5
func item_name(item_id: int) -> String     # = word(items[item_id].name?)  规则见 sdlpal uigame.c
func magic_name(magic_id: int) -> String
func enemy_name(enemy_id: int) -> String
func item_desc(item_id: int) -> PackedStringArray  # 走脚本描述（0xFFFF 消息序列）
```

- 装载入口：`func init(data_dir: String) -> bool`，由 `main.gd` 在进标题前调用一次。
- 数据解析按小端 u16/u32；结构体布局以 `<LOCAL_PATH>` 为准。
- 对齐 sdlpal `global.c: PAL_ReadGlobalGameData / PAL_LoadDefaultGame / PAL_InitGlobalGameData`。

## 2. PALState（Lead 实现，可变）

字段镜像 `GLOBALVARS`（sdlpal `global.h`），命名对应：

```gdscript
var scene: int; var palette: int; var night_palette: bool
var music: int; var battle_music: int; var battle_field: int
var collect_value: int; var screen_wave: int; var wave_progression: int
var chase_range: int; var chase_speed_cycles: int; var follower_count: int
var cash: int
var party: Array      # [{role:int, x:int, y:int, frame:int}]
var trail: Array      # [{x:int, y:int, dir:int}]
var party_dir: int; var max_party_member_index: int
var party_offset: Vector2i; var viewport: Vector2i; var layer: int
var roles: Dictionary          # 运行时 PLAYERROLES（从 PALTables.player_roles 深拷贝）
var equipment_effect: Array    # [7] 份 PLAYERROLES
var status: Array              # [6][9] int
var poison_status: Array       # [16][6] [{poison_id:int, script:int}]
var inventory: Array           # [MAX_INVENTORY] [{item:int, amount:int, in_use:int}]
var exp: Dictionary            # ALLEXPERIENCE: primary/health/magic/attack/magic_power/defense/dexterity/flee，各 {level:int, exp:int}
var vars: Dictionary           # 移植补充：脚本/剧情通用变量（保存时另存 JSON）
var battle_speed: int
var saved_times: int
var data: PalData              # = PALTables.sss 的引用（脚本/消息用）
```

方法（逐一对应 `global.c`，签名用 int）：

```
reset_defaults() -> void                      # = PAL_LoadDefaultGame
init_game_data(slot: int) -> void              # = PAL_InitGameData
count_item(item_id) -> int
get_item_index(item_id) -> int                 # -1 表示没有
add_item(item_id, n) -> int                    # = PAL_AddItemToInventory
get_item_amount(item_id) -> int
compress_inventory() -> void
increase_hpmp(role, hp, mp) -> bool
update_equipments() -> void
remove_equipment_effect(role, part) -> void
add_poison(role, poison_id) -> void
cure_poison_by_kind(role, id) -> void
cure_poison_by_level(role, level) -> void
is_poisoned_by_level(role, level) -> bool
is_poisoned_by_kind(role, id) -> bool
get_player_attack_strength(role) -> int ...（magic_strength/defense/dexterity/flee_rate/poison_resistance/elemental_resistance/battle_sprite/cooperative_magic）
player_can_attack_all(role) -> bool
add_magic(role, magic_id) -> bool
remove_magic(role, magic_id) -> bool
set_player_status(role, status, rounds) -> void
remove_player_status(role, status) -> void
clear_all_player_status() -> void
player_level_up(role) -> bool
save_game(slot) -> bool / load_game(slot) -> bool
```

## 3. World 公共 API（`game/world.gd`，Lead 实现；其他模块只调用不修改）

```gdscript
# 场景/脚本
func script_dialog(text: String, msg_id: int) -> void          # 显示一页对白并等按键
func script_dialog_closed() -> void
func script_dialog_clear() -> void
func script_dialog_style(style: int) -> void
func script_refresh(gestures: bool) -> void
func script_change_scene(n: int) -> void
func script_enter_distance_scene(n: int, distance: int) -> void
# 战斗（脚本 0x0007）
func request_battle(team_id: int, flee_disabled: bool, force_win: bool) -> void
func on_battle_finished(result: String) -> void                # 由 battle 回填，脚本继续
# 菜单
func open_menu(kind: String) -> void                           # "item"/"magic"/"equip"/"status"/"system"/"save"/"load"/"shop"
func on_menu_closed() -> void
# 动画/特效
func request_rng(rng_id: int) -> void
func request_ending() -> void
func set_screen_wave(level: int, progression: int) -> void
func shake_screen(times: int) -> void
func fade_out(speed: int) -> void / fade_in(speed: int)
func set_palette(num: int, night: bool) -> void
func redraw() -> void
# 状态暴露
var current_map: PalMap
var scene_events: Dictionary     # 1-based id -> PackedInt32Array(16)
var vm: ScriptVM
var player_busy: bool            # 对话/战斗/菜单期间为 true
```

## 4. 跨模块调用约定

| 调用方 | 被调 | 方式 |
|---|---|---|
| ScriptVM | World | 上节方法（脚本操作码） |
| ScriptVM | PALState | 属性/方法 |
| ScriptVM | PALAudio | `play_music/play_sound/stop_music` |
| World | Battle（`game/battle.gd`） | 实例化 `Battle.new()`，`setup(team_id, flags)`，`add_child`，完成时 `emit_signal("finished", result)` |
| World | Menu（`game/menu.gd`） | 实例化，菜单内部用 `PALState`，关闭时 `emit_signal("closed")` |
| Battle/Menu | World | 只调用 §3 API（如 `redraw`、`open_menu`）、`PALState`、`PALTables` |
| 所有 | PALText | `PALText.msg(i)`、`PALText.paginate(text)`、`PALText.words` |

## 5. 数据表结构（sdlpal 字段 → Dictionary 键）

### 5.1 PLAYERROLES（DATA.MKF #3）
`avatar[6] / sprite_in_battle[6] / sprite_in_scene[6] / name[6] / attack_all[6] /
unknown1[6] / level[6] / max_hp[6] / max_mp[6] / hp[6] / mp[6] /
equipment[6][6] / attack_strength[6] / magic_strength[6] / defense[6] / dexterity[6] /
flee_rate[6] / poison_resistance[6] / elemental_resistance[5][6] /
unknown2..4[6] / covered_by[6] / magic[5][6] / walk_frames[6] / cooperative_magic[6] /
unknown5,unknown6[6] / death_sound[6] / attack_sound[6] / weapon_sound[6] /
critical_sound[6] / magic_sound[6] / cover_sound[6] / dying_sound[6]`

顺序 = sdlpal `global.h: tagPLAYERROLES` 字段顺序，按 u16 连续读取（EQUIPMENT 为 [part][role]）。

### 5.2 其它
- `items`（OBJECT_ITEM，7×u16）：`bitmap/price/script_on_use/script_on_equip/script_on_throw/script_desc/flags`
- `magics`（OBJECT_MAGIC，7×u16）：`magic_number/reserved1/script_on_success/script_on_use/script_desc/reserved2/flags`
- `magic_defs`（DATA#4 tagMAGIC：17×u16，含 specific 联合体按 u16 处理）
- `enemies`（DATA#1 tagENEMY，37×u16，字段见 global.h）
- `enemy_teams`（DATA#2：5×u16）
- `battle_fields`（DATA#5：1 + 5 u16）
- `stores`（DATA#0：每项 9×u16）
- `level_up_magic`（DATA#6：每角色 `LEVELUPMAGIC m[6]` = 6×(level,magic)）
- `poisons`（OBJECT_POISON：5×u16）

## 6. 文件归属（写权限，勿越界）

| 归属 | 文件 |
|---|---|
| Lead | `project.godot` `main.gd` `main.tscn` `game/world.gd` `game/title.gd` `pal/pal_config.gd` `pal/mkf.gd` `pal/pal_sprite.gd` `pal/pal_map.gd` `pal/pal_data.gd` `pal/pal_tables.gd` `pal/pal_state.gd` `tools/port_check.gd` `docs/**` |
| port-script | `pal/script_vm.gd` `pal/npc_move.gd` |
| port-battle | `game/battle.gd` `game/battle_ui.gd` `pal/battle_data.gd` |
| port-menus | `game/menu.gd` `game/menu_*.gd` `game/save_system.gd` `game/shop.gd` `pal/ui_assets.gd` |
| port-audio-text | `pal/pal_audio.gd` `pal/text_db.gd` `game/dialog_box.gd` `pal/rng_player.gd` `game/ending.gd` |

跨归属需要的接口改动 → `send_message` 给 lead，不要直接改别人的文件。

## 7. 验收方式

```powershell
# 语法/自检
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path <proj> --script res://tools/port_check.gd
# 实机自动演示（截图到 _rea_runtime/out/shots）
Godot_v4.7.2-stable_mono_win64_console.exe --path <proj> --auto --quit-after 4200
```
