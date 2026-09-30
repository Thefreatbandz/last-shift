extends SceneTree
## Interior-zones QA: the "compound on the inside" phase.
## Builder phase (no scene): zone records, area, origins, non-empty loot.
## Live phase (main.tscn): entry/exit through the real door, visibility,
## zombie threshold crossing both ways, closed/barricaded door holds +
## pounding, a real zone loot search (inventory + pickup toast), and a
## forced night wave cleared while the player is indoors and alive.
## Run:
##   godot --headless --path . --script res://tests/interior_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEEDS := [48392017, 12345, 777]
const LIVE_SEED := 48392017
const AREA_FACTOR := 2.5 # zone floor must be >= 2.5x the exterior footprint

var _booted := false
var _frames := 0
var _ok := true

var _main: Node
var _nb: Node
var _zones: Node
var _doors: Node
var _barricades: Node
var _zombies: Node
var _loot: Node
var _inv: Node
var _hud: Node
var _player: Node
var _interact: Node
var _waves: Node
var _hbi := -1 # hospital building index (always present, never locked)
var _hzone := {}
var _zz: Node = null # scratch zombie for crossing / pound tests
var _hp_before := 0.0
var _inv_before := {}
var _search_target: Node = null
# Lazy-loaded classes: in bare --script SceneTree mode the test script's
# static class_name dependencies compile before autoload singletons are
# registered, so any class touching the Sound autoload (NeighborhoodBuilder
# via ChoppableTree, InteriorZones, BarricadeManager, ZombieAI) must be
# loaded here instead. (prompt_qa.gd precedent.)
var _NB: GDScript
var _IZ: GDScript
var _BM: GDScript
var _ZA: GDScript


func _check(label: String, cond: bool) -> void:
	if cond:
		print("IZQA PASS ", label)
	else:
		_ok = false
		print("IZQA FAIL ", label)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_NB = load("res://scripts/world/neighborhood_builder.gd")
		_IZ = load("res://scripts/world/interior_zones.gd")
		_BM = load("res://scripts/world/barricade_manager.gd")
		_ZA = load("res://scripts/zombie/zombie_ai.gd")
		_builder_checks()
		root.get_node("RunState").set("world_seed", LIVE_SEED)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _frames:
		30:
			_live_setup()
		36:
			_open_door_and_enter()
		44:
			_assert_entered()
		# Teleport cooldown is 0.25s (~36 frames headless): wait it out.
		100:
			_place_at_exit()
		108:
			_assert_exited()
			_zombie_cross_in()
		116:
			_assert_zombie_in()
		172:
			_zombie_cross_out()
		180:
			_assert_zombie_out()
			_closed_door_hold()
		188:
			_assert_closed_hold()
			_build_barricade()
		196:
			_start_pound()
		316:
			_assert_pounding()
			_loot_search_setup()
		322:
			_start_search()
		# Headless runs uncapped (~145fps), so the 1.5s search needs ~220+
		# frames, not 90. Poll generously.
		580:
			_assert_search_done()
			_wave_indoors_setup()
		590:
			_assert_wave_spawned()
			_kill_wave()
		602:
			_assert_wave_cleared()
			print("IZQA_RESULT ok=", _ok)
			quit(0 if _ok else 1)
			return true
		_:
			pass
	return false


# ------------------------------------------------------- builder checks ---

func _builder_checks() -> void:
	for seed in SEEDS:
		var nb: Node = _NB.new()
		root.add_child(nb)
		nb.build_world(seed)
		var iz: Node = nb.interior_zones
		_check("zones_exist_%d" % seed, iz != null)
		if iz == null:
			nb.free()
			continue
		var kinds := {}
		for z in iz.zones:
			kinds[String((z as Dictionary)["kind"])] = true
		_check("anchored_zoned_%d" % seed,
			kinds.has("police") and kinds.has("hospital") and kinds.has("warehouse"))
		# Office regression (Tbandz field report): EITHER office kind must
		# register a usable zone WHEN the seed selects it. Seeds that pick
		# "corner" have no office building and nothing to check.
		for b in nb.buildings:
			var bk := String((b as Dictionary)["kind"])
			if bk == "office_tall" or bk == "office_small":
				_check("office_zoned_%s_%d" % [bk, seed], kinds.has(bk))
		# No other kinds are zoned; every zone maps to a real building.
		for z in iz.zones:
			var zd := z as Dictionary
			_check("zone_kind_known_%d" % seed,
				_IZ.is_zoned_kind(String(zd["kind"])))
			_check("zone_building_%d" % seed,
				int(zd["building"]) >= 0 and int(zd["building"]) < nb.buildings.size())
		# Zone floor clearly larger than the exterior footprint.
		for z in iz.zones:
			var zd := z as Dictionary
			var b := nb.buildings[int(zd["building"])] as Dictionary
			var ext := float(b["w"]) * float(b["d"])
			var zb := zd["bounds"] as Rect2
			_check("zone_bigger_%s_%d" % [String(zd["kind"]), seed],
				zb.size.x * zb.size.y >= ext * AREA_FACTOR)
		# Deterministic origins: same seed twice -> same origins; and the
		# documented layout formula holds.
		var o1 := _zone_origins(nb)
		var nb2: Node = _NB.new()
		root.add_child(nb2)
		nb2.build_world(seed)
		_check("origins_stable_%d" % seed, _zone_origins(nb2) == o1)
		nb2.free()
		for zi in iz.zones.size():
			var zd := iz.zones[zi] as Dictionary
			var want := Vector3(1200.0 + float(zi) * 500.0, 0.0, 1200.0)
			_check("origin_formula_%s_%d" % [String(zd["kind"]), seed],
				(zd["origin"] as Vector3).distance_to(want) < 0.01)
		# Loot regression net (Tbandz field report): EVERY container ships
		# non-empty loot. No silent empty searches, ever.
		for li in nb.building_loot.size():
			var items := ((nb.building_loot[li] as Dictionary)["items"]) as Array
			_check("bld_loot_nonempty_%d_%d" % [li, seed], items.size() > 0)
		for oi in nb.outdoor_loot.size():
			var oitems := ((nb.outdoor_loot[oi] as Dictionary)["items"]) as Array
			_check("out_loot_nonempty_%d_%d" % [oi, seed], oitems.size() > 0)
		nb.free()


func _zone_origins(nb: Node) -> Array:
	var out: Array = []
	for z in nb.interior_zones.zones:
		out.append((z as Dictionary)["origin"])
	return out


# ---------------------------------------------------------- live checks ---

func _live_setup() -> void:
	_nb = _main.get_node("Neighborhood")
	_zones = _nb.get("interior_zones")
	_doors = _main.get_node("HouseDoors")
	_barricades = _main.get_node("Barricades")
	_zombies = _main.get_node("Zombies")
	_loot = _main.get_node("Loot")
	_inv = _main.get_node("Inventory")
	_hud = _main.get_node("HUD")
	_player = _main.get_node("Player")
	_interact = _main.get_node("Interact")
	_waves = _main.get_node("Waves")
	_check("zones_wired", _zones != null)
	for bi in (_nb.get("buildings") as Array).size():
		var b := (_nb.get("buildings") as Array)[bi] as Dictionary
		if String(b["kind"]) == "hospital":
			_hbi = bi
	_check("hospital_found", _hbi >= 0)
	for z in _zones.get("zones"):
		if String((z as Dictionary)["kind"]) == "hospital":
			_hzone = z
	_check("hospital_zone", not _hzone.is_empty())
	# Runtime loot net: every live container (houses, buildings, outdoor,
	# zones) carries non-empty loot.
	for c in _loot.call("get_containers"):
		_check("live_loot_nonempty_%d" % int(c.get("container_id")),
			(c.get("loot") as Array).size() > 0)
	# Grab a scratch zombie (resurrected far from the action).
	var zl: Array = _zombies.get("zombies")
	_zz = zl[0] as Node
	_check("scratch_zombie", _zz != null)


func _trigger_pos(name: String) -> Vector3:
	# Place bodies at y=0.5 (inside the trigger's 0.0-2.2 span) so they
	# don't fall through the open doorway before the Area3D detects them.
	var p := ((_hzone[name] as Area3D).global_position)
	return Vector3(p.x, 0.5, p.z)


func _open_door_and_enter() -> void:
	_doors.call("set_building_door_open", _hbi, true, false)
	_player.set("global_position", _trigger_pos("entry_trigger"))


func _assert_entered() -> void:
	var pp: Vector3 = _player.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("enter_in_zone", zb.grow(0.6).has_point(Vector2(pp.x, pp.z)))
	_check("enter_zone_visible", bool((_hzone["root"] as Node3D).visible))
	for z in _zones.get("zones"):
		var zd := z as Dictionary
		if zd == _hzone:
			continue
		_check("other_zone_hidden_%s" % String(zd["kind"]),
			not bool((zd["root"] as Node3D).visible))
	# The player never stands inside the exterior footprint: the roof stays
	# on (that is the whole point of the zone design).
	var b := (_nb.get("buildings") as Array)[_hbi] as Dictionary
	var bp := b["pos"] as Vector3
	var inside_ext := absf(pp.x - bp.x) < float(b["w"]) * 0.5 \
		and absf(pp.z - bp.z) < float(b["d"]) * 0.5
	_check("never_in_footprint", not inside_ext)
	_check("shell_roof_stays", bool((b["roof"] as Node3D).visible))


func _place_at_exit() -> void:
	_player.set("global_position", _trigger_pos("exit_trigger"))


func _assert_exited() -> void:
	var pp: Vector3 = _player.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("exit_outside_zone", not zb.grow(0.6).has_point(Vector2(pp.x, pp.z)))
	var sp := _hzone["spawn_out"] as Vector3
	_check("exit_at_door", pp.distance_to(sp) < 2.0)
	_check("exit_zone_hidden", not bool((_hzone["root"] as Node3D).visible))


func _zombie_cross_in() -> void:
	# Door is still open, no boards: the zombie must ride the trigger in.
	_zz.set("global_position", _trigger_pos("entry_trigger"))


func _assert_zombie_in() -> void:
	var zp: Vector3 = _zz.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("zombie_crossed_in", zb.grow(0.6).has_point(Vector2(zp.x, zp.z)))


func _zombie_cross_out() -> void:
	_zz.set("global_position", _trigger_pos("exit_trigger"))


func _assert_zombie_out() -> void:
	var zp: Vector3 = _zz.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("zombie_crossed_out", not zb.grow(0.6).has_point(Vector2(zp.x, zp.z)))


func _closed_door_hold() -> void:
	_doors.call("set_building_door_open", _hbi, false, false)
	_player.set("global_position", _trigger_pos("entry_trigger"))


func _assert_closed_hold() -> void:
	var pp: Vector3 = _player.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("closed_door_holds", not zb.grow(0.6).has_point(Vector2(pp.x, pp.z)))


func _build_barricade() -> void:
	_inv.call("add", "wood", 10)
	_inv.call("add", "scrap", 10)
	_barricades.call("_on_use", _BM.key_for_building(_hbi))
	_check("barricade_built",
		_barricades.call("has_boards", _BM.key_for_building(_hbi)))
	_hp_before = float(_barricades.call("boards_hp",
		_BM.key_for_building(_hbi)))


func _start_pound() -> void:
	# Zombie at the barricaded door in CHASE, player in open view: it must
	# pound the boards, not slip through the trigger.
	var door := ((_nb.get("buildings") as Array)[_hbi]) as Dictionary
	var dp := (door["door"] as Dictionary)["pos"] as Vector3
	var face := float(door["face"])
	var out := Vector3(0, 0, face)
	_zz.set("global_position", dp + out * 1.8 + Vector3(0, 0.3, 0))
	_zz.set("state", _ZA.State.CHASE)
	_player.set("global_position", dp + out * 7.0 + Vector3(2.0, 0, 0))


func _assert_pounding() -> void:
	var hp := float(_barricades.call("boards_hp",
		_BM.key_for_building(_hbi)))
	_check("pounding_damages_boards", hp < _hp_before)
	var zp: Vector3 = _zz.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("barricaded_door_holds_zombie",
		not zb.grow(0.6).has_point(Vector2(zp.x, zp.z)))


func _loot_search_setup() -> void:
	# Nearest unsearched hospital-zone container.
	var zb := _hzone["bounds"] as Rect2
	var best: Node = null
	var best_d := 99999.0
	var pp: Vector3 = _player.get("global_position")
	for c in _loot.call("get_containers"):
		var cn := c as Node
		if bool(cn.get("searched")):
			continue
		var cp: Vector3 = cn.get("global_position")
		if not zb.grow(0.6).has_point(Vector2(cp.x, cp.z)):
			continue
		var d := pp.distance_to(cp)
		if d < best_d:
			best_d = d
			best = cn
	_check("zone_container_found", best != null)
	_search_target = best
	if best == null:
		return
	var cp: Vector3 = best.get("global_position")
	_player.set("global_position", cp + Vector3(1.5, 0.1, 0))
	for id in ["medicine", "bandage", "health_kit", "painkillers", "cloth", "scrap"]:
		_inv_before[id] = int(_inv.call("count", id))


func _start_search() -> void:
	if _search_target == null:
		return
	_interact.call("try_interact")
	_check("search_started", bool(_loot.get("_searching")))
	# The interact manager searches the NEAREST container, which may differ
	# from the one we measured: track the real target.
	_search_target = _loot.get("_search_target")


func _assert_search_done() -> void:
	if _search_target == null:
		_check("search_done", false)
		return
	_check("container_searched", bool(_search_target.get("searched")))
	var gained := 0
	for id in _inv_before.keys():
		gained += int(_inv.call("count", String(id))) - int(_inv_before[id])
	_check("search_granted_inventory", gained > 0)
	# The pickup notice (Tbandz regression watch): the toast must be up.
	var label: Label = _hud.get("_pickup_label") as Label
	_check("pickup_toast_visible", label != null and label.visible)
	_check("pickup_toast_text",
		label != null and String(label.text).length() > 0)


func _wave_indoors_setup() -> void:
	# Player holes up in the zone; the wave must come to the building.
	_player.set("global_position", _hzone["spawn_in"])
	(_player.get_node("Health") as Node).set("hp", 100.0)
	_waves.set("phase", "night")
	_waves.set("_spawned_this_night", true)
	_waves.call("_spawn_wave", 1)


func _assert_wave_spawned() -> void:
	var wv: Array = _waves.get("wave_zombies")
	_check("wave_spawned", wv.size() > 0)
	# Nobody spawns in the void: every wave zombie is on the real map.
	var map_ok := true
	for z in wv:
		var p: Vector3 = (z as Node).get("global_position")
		if absf(p.x) > 100.0 or absf(p.z) > 100.0:
			map_ok = false
	_check("wave_on_map", map_ok)
	# ...converging near the hospital door, not scattered at random.
	var door := ((_nb.get("buildings") as Array)[_hbi]) as Dictionary
	var dp := (door["door"] as Dictionary)["pos"] as Vector3
	var near := 0
	for z in wv:
		var p: Vector3 = (z as Node).get("global_position")
		if Vector2(p.x - dp.x, p.z - dp.z).length() < 100.0:
			near += 1
	_check("wave_converges_on_door", near == wv.size())


func _kill_wave() -> void:
	for z in _waves.get("wave_zombies"):
		(z as Node).call("take_damage", 99999.0,
			(z as Node).get("global_position"))


func _assert_wave_cleared() -> void:
	_check("wave_kills_register", int(_waves.call("zombies_remaining")) == 0)
	_check("wave_cleared_to_day", String(_waves.get("phase")) == "day")
	_check("wave_number_1", int(_waves.get("wave_number")) == 1)
	var hp := float((_player.get_node("Health") as Node).get("hp"))
	_check("player_alive_indoors", hp > 0.0)
	var pp: Vector3 = _player.get("global_position")
	var zb := _hzone["bounds"] as Rect2
	_check("player_still_indoors", zb.grow(0.6).has_point(Vector2(pp.x, pp.z)))
