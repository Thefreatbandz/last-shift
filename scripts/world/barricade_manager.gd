class_name BarricadeManager
extends Node3D
## Real door barricades for the wave loop. Zombies come through doors, so
## doors are what you board up:
## - BOARD UP: 3 wood + 1 scrap. Instant, with the repair pose + thud.
##   100 HP of boards across the doorway.
## - 3 visual damage stages: 4 planks -> 3 -> 2 as HP falls.
## - Zombies pound boards with their arms-only attack (ZombieAI routes
##   through pound()). Boards break with a crack; then the door itself
##   has 60 HP before it bursts open.
## - REPAIR: 2 wood, +50 HP. REMOVE BOARDS when intact.
## - Boarded doors refuse to swing (HouseDoors asks has_boards first).
## - This supersedes the old abstract safehouse ward barricade: the porch
##   walls + zombie ward are retired, not duplicated.

signal boards_changed(key: String)

const BUILD_WOOD := 3
const BUILD_SCRAP := 1
const REPAIR_WOOD := 2
const REPAIR_AMOUNT := 50.0
const BOARDS_MAX := 100.0
const DOOR_MAX := 60.0
const POUND_SOUND_CD := 0.5

var _hood: NeighborhoodBuilder
var _doors: HouseDoors
var _interact: InteractManager
var _inv: Inventory
var _survival: SurvivalStats
var _hud: Hud
var _player: PlayerController

var _st := {} # key -> {hp, door_hp, boards: Node3D, entry: int, marker: Node3D}
var _pound_cd := 0.0
var _poll_t := 0.0
var _wood_mat: StandardMaterial3D
var _dark_wood_mat: StandardMaterial3D


static func key_for_house(i: int) -> String:
	return "h%d" % i


static func key_for_building(j: int) -> String:
	return "b%d" % j


func setup(hood: NeighborhoodBuilder, doors: HouseDoors, interact: InteractManager,
		inv: Inventory, survival: SurvivalStats, hud: Hud,
		player: PlayerController, safehouse: Safehouse) -> void:
	_hood = hood
	_doors = doors
	_interact = interact
	_inv = inv
	_survival = survival
	_hud = hud
	_player = player
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.50, 0.36, 0.20)
	_wood_mat.roughness = 0.9
	_dark_wood_mat = StandardMaterial3D.new()
	_dark_wood_mat.albedo_color = Color(0.36, 0.25, 0.14)
	_dark_wood_mat.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 4451
	for i in _hood.houses.size():
		var h := _hood.houses[i] as Dictionary
		var door := h["door"] as Dictionary
		_register(key_for_house(i), door, float(h.get("face", 1.0)), rng)
	for j in _hood.buildings.size():
		var b := _hood.buildings[j] as Dictionary
		var door := b["door"] as Dictionary
		_register(key_for_building(j), door, float(b.get("face", 1.0)), rng)
	# The safehouse door stays unboardable until claimed.
	var si := _doors.safehouse_door_index()
	if si >= 0:
		_interact.set_enabled(int((_st[key_for_house(si)] as Dictionary)["entry"]), false)
		safehouse.claimed_house.connect(_on_safehouse_claimed)


func _on_safehouse_claimed() -> void:
	var si := _doors.safehouse_door_index()
	if si >= 0 and _st.has(key_for_house(si)):
		_interact.set_enabled(int((_st[key_for_house(si)] as Dictionary)["entry"]), true)
		_refresh_prompt(key_for_house(si))


func _register(key: String, door: Dictionary, face: float, rng: RandomNumberGenerator) -> void:
	var pos := door["pos"] as Vector3
	var yaw := 0.0 if face >= 0.0 else PI
	# Marker: a small plank stack leaning by the door frame (side offset so
	# the door's own OPEN/CLOSE prompt stays reachable head-on).
	var marker := Node3D.new()
	marker.position = pos + Vector3(cos(yaw), 0, -sin(yaw)) * 1.35 + Vector3(0, 1.0, 0)
	marker.rotation.y = yaw
	add_child(marker)
	var entry := _interact.register(marker, "", 2.2, _on_use.bind(key))
	_st[key] = {"hp": 0.0, "door_hp": DOOR_MAX, "boards": null,
		"entry": entry, "marker": marker, "yaw": yaw, "pos": pos, "seed": rng.randf()}
	_refresh_prompt(key)


func has_boards(key: String) -> bool:
	return _st.has(key) and float((_st[key] as Dictionary)["hp"]) > 0.0


func boards_hp(key: String) -> float:
	return float((_st[key] as Dictionary)["hp"]) if _st.has(key) else 0.0


## ZombieAI: nearest door that is closed and poundable (boarded or not).
## Returns {} when none within max_dist.
func nearest_closed_door(from: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for key in _st:
		var s := _st[key] as Dictionary
		if _door_open(key):
			continue
		var d: float = from.distance_to(s["pos"] as Vector3)
		if d < best_d:
			best_d = d
			best = {"key": key, "pos": s["pos"]}
	return best


func _door_open(key: String) -> bool:
	var door := _door_dict(key)
	return bool(door.get("open", false))


func _door_dict(key: String) -> Dictionary:
	if key.begins_with("h"):
		return ((_hood.houses[int(key.substr(1))] as Dictionary)["door"] as Dictionary)
	return ((_hood.buildings[int(key.substr(1))] as Dictionary)["door"] as Dictionary)


func _on_use(key: String) -> void:
	if not _st.has(key):
		return
	var s := _st[key] as Dictionary
	var hp: float = s["hp"]
	if hp <= 0.0:
		_try_build(key, s)
	elif hp < BOARDS_MAX:
		_try_repair(key, s)
	else:
		_remove_boards(key, s)


func _can_build() -> bool:
	return _inv.count(LootDefs.WOOD) >= BUILD_WOOD \
		and _inv.count(LootDefs.SCRAP) >= BUILD_SCRAP


func _try_build(key: String, s: Dictionary) -> void:
	if _door_open(key):
		_hud.show_interact("CLOSE THE DOOR FIRST", 1.5)
		Sound.play("click", -6.0, 0.7)
		return
	if not _can_build():
		_hud.show_interact("NEED %d WOOD + %d SCRAP" % [BUILD_WOOD, BUILD_SCRAP], 1.8)
		Sound.play("click", -6.0, 0.7)
		return
	if not _survival.spend_stamina(6.0):
		return
	_inv.remove(LootDefs.WOOD, BUILD_WOOD)
	_inv.remove(LootDefs.SCRAP, BUILD_SCRAP)
	s["hp"] = BOARDS_MAX
	s["door_hp"] = DOOR_MAX
	_build_boards(key, s)
	(_player.get_node("Visual") as PlayerVisual).play_repair()
	Sound.play_3d("pound", (s["pos"] as Vector3) + Vector3(0, 1.2, 0))
	_refresh_prompt(key)
	boards_changed.emit(key)


func _try_repair(key: String, s: Dictionary) -> void:
	if _inv.count(LootDefs.WOOD) < REPAIR_WOOD:
		_hud.show_interact("NEED %d WOOD" % REPAIR_WOOD, 1.5)
		Sound.play("click", -6.0, 0.7)
		return
	if not _survival.spend_stamina(6.0):
		return
	_inv.remove(LootDefs.WOOD, REPAIR_WOOD)
	s["hp"] = minf(BOARDS_MAX, float(s["hp"]) + REPAIR_AMOUNT)
	_update_stage(key, s)
	(_player.get_node("Visual") as PlayerVisual).play_repair()
	Sound.play_3d("pound", (s["pos"] as Vector3) + Vector3(0, 1.2, 0))
	_refresh_prompt(key)
	boards_changed.emit(key)


func _remove_boards(key: String, s: Dictionary) -> void:
	s["hp"] = 0.0
	_clear_boards(s)
	Sound.play_3d("door", (s["pos"] as Vector3) + Vector3(0, 1.2, 0))
	_refresh_prompt(key)
	boards_changed.emit(key)


## Zombie pounding. Boards take it first; then the door bursts open.
func pound(key: String, dmg: float) -> void:
	if not _st.has(key):
		return
	var s := _st[key] as Dictionary
	if _door_open(key):
		return
	var pos := s["pos"] as Vector3
	if float(s["hp"]) > 0.0:
		s["hp"] = maxf(0.0, float(s["hp"]) - dmg)
		if _pound_cd <= 0.0:
			Sound.play_3d("pound", pos + Vector3(0, 1.2, 0))
			_pound_cd = POUND_SOUND_CD
		if float(s["hp"]) <= 0.0:
			_clear_boards(s)
			Sound.play_3d("barricade_break", pos + Vector3(0, 1.2, 0))
			_hud.show_interact("BARRICADE BROKEN!", 1.6)
		else:
			_update_stage(key, s)
	else:
		s["door_hp"] = float(s["door_hp"]) - dmg
		if _pound_cd <= 0.0:
			Sound.play_3d("pound", pos + Vector3(0, 1.2, 0))
			_pound_cd = POUND_SOUND_CD
		if float(s["door_hp"]) <= 0.0:
			_burst_open(key, s, pos)
	_refresh_prompt(key)
	boards_changed.emit(key)


func _burst_open(key: String, s: Dictionary, pos: Vector3) -> void:
	s["door_hp"] = DOOR_MAX
	Sound.play_3d("barricade_break", pos + Vector3(0, 1.2, 0))
	_hud.show_interact("DOOR BROKEN OPEN!", 1.6)
	if key.begins_with("h"):
		_doors.set_door_open(int(key.substr(1)), true, true)
	else:
		_doors.set_building_door_open(int(key.substr(1)), true, true)


func _process(delta: float) -> void:
	if _pound_cd > 0.0:
		_pound_cd -= delta
	# Doors swing on their own tween: poll so BOARD UP enables/disables as
	# doors open and close (cheap dict reads, ~30 doors).
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.3
		for key in _st:
			_refresh_prompt(key)


func _refresh_prompt(key: String) -> void:
	var s := _st[key] as Dictionary
	var id := int(s["entry"])
	if _door_open(key):
		_interact.set_enabled(id, false)
		return
	_interact.set_enabled(id, true)
	var hp: float = s["hp"]
	if hp <= 0.0:
		_interact.set_prompt(id, "BOARD UP (%d WOOD+%d SCRAP)" % [BUILD_WOOD, BUILD_SCRAP])
	elif hp < BOARDS_MAX:
		_interact.set_prompt(id, "REPAIR BOARDS (%d WOOD)" % REPAIR_WOOD)
	else:
		_interact.set_prompt(id, "REMOVE BOARDS")


## Door toggles must refresh barricade prompts (open doors can't board).
func on_door_toggled(key: String) -> void:
	if _st.has(key):
		_refresh_prompt(key)


# --- Boards visuals: 3 damage stages (4 planks -> 3 -> 2) ---

func _build_boards(key: String, s: Dictionary) -> void:
	_clear_boards(s)
	var g := Node3D.new()
	var yaw := float(s["yaw"])
	# Offset proud of the door face so the planks read over the door mesh.
	g.position = (s["pos"] as Vector3) + Vector3(0, 0.02, 0) \
		+ Vector3(0, 0, 0.07).rotated(Vector3.UP, yaw)
	g.rotation.y = yaw
	add_child(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(s["seed"]) * 100000.0) + 7
	var heights := [0.55, 0.90, 1.25, 1.58]
	for i in heights.size():
		var plank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.55, 0.17, 0.055)
		plank.mesh = bm
		plank.material_override = _wood_mat if i % 2 == 0 else _dark_wood_mat
		plank.position = Vector3(rng.randf_range(-0.05, 0.05), heights[i],
			rng.randf_range(-0.03, 0.03))
		plank.rotation.z = rng.randf_range(-0.10, 0.10)
		plank.name = "plank%d" % i
		g.add_child(plank)
	s["boards"] = g
	_update_stage(key, s)


func _update_stage(key: String, s: Dictionary) -> void:
	var g := s["boards"] as Node3D
	if not is_instance_valid(g):
		return
	var hp: float = s["hp"]
	# Stage 0 (full): 4 planks. Stage 1 (<66%): 3. Stage 2 (<33%): 2,
	# tilted and darkened.
	var keep := 4
	if hp < BOARDS_MAX * 0.33:
		keep = 2
	elif hp < BOARDS_MAX * 0.66:
		keep = 3
	for i in 4:
		var p := g.get_node_or_null("plank%d" % i) as MeshInstance3D
		if p == null:
			continue
		p.visible = i < keep
		if keep == 2 and i < 2:
			p.rotation.z = -0.28 if i == 0 else 0.24
			p.material_override = _dark_wood_mat
	_refresh_prompt(key)


func _clear_boards(s: Dictionary) -> void:
	var g := s["boards"] as Node3D
	if is_instance_valid(g):
		g.queue_free()
	s["boards"] = null
