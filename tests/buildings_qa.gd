extends SceneTree
## Headless QA for the building-types phase: seeded commercial buildings,
## locked police door (key / lockpick), medicine, Brutes, interior loot and
## zombie spawns, minimap metadata, lockpick crafting. Run:
##   godot --headless --path . --script res://tests/buildings_qa.gd
## Grep the output for SCRIPT ERROR separately.

var _booted := false
var _frames := 0
var _ok := true
var _main: Node
# Lazy load: NeighborhoodBuilder touches the Sound autoload (via
# ChoppableTree); static class_name refs compile before autoloads register
# in bare --script mode. (prompt_qa.gd precedent.)
var _NB: GDScript


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_NB = load("res://scripts/world/neighborhood_builder.gd")
		_builder_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 200:
		_live_checks()
		print("BUILDQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


func _builder_checks() -> void:
	# Determinism without booting the scene.
	var n1: Node = _NB.new()
	root.add_child(n1)
	n1.build_world(48392017)
	var n2: Node = _NB.new()
	root.add_child(n2)
	n2.build_world(48392017)
	_ok = _check("layout_determinism", n1.layout_hash() == n2.layout_hash(), _ok)
	_ok = _check("interior_determinism",
		n1.interior_hash() == n2.interior_hash() and n1.interior_hash() != "", _ok)
	n2.free()
	var n3: Node = _NB.new()
	root.add_child(n3)
	n3.build_world(777)
	_ok = _check("interior_varies", n3.interior_hash() != n1.interior_hash(), _ok)
	_ok = _check("buildings_5", n1.buildings.size() == 5, _ok) # 4 anchors + warehouse
	_ok = _check("loot_spots", n1.building_loot.size() >= 7, _ok)
	_ok = _check("brute_spots_2", n1.brute_spawns.size() == 2, _ok)
	_ok = _check("indoor_z_spots", n1.building_zombie_spawns.size() >= 4, _ok)
	n1.free()
	n3.free()


func _live_checks() -> void:
	var nb = _main.get_node("Neighborhood")
	var doors = _main.get_node("HouseDoors")
	var inv = _main.get_node("Inventory")
	_ok = _check("run_started", _main._run_started, _ok)
	_ok = _check("buildings_live_5", nb.buildings.size() == 5, _ok)
	_ok = _check("bids_registered", doors._bids.size() == 5, _ok)
	_ok = _check("minimap_buildings",
		_main.get_node("Minimap").buildings().size() == 5, _ok)
	var pj := _police_idx(nb)
	_ok = _check("police_found", pj >= 0, _ok)
	# --- Locked door: no key => stays locked.
	_ok = _check("police_locked", doors.is_building_locked(pj), _ok)
	_ok = _check("unlock_no_key_fails", not doors.try_unlock_building(pj), _ok)
	_ok = _check("still_locked", doors.is_building_locked(pj), _ok)
	# --- Key path: key is consumed, door opens.
	inv.add("police_key", 1)
	_ok = _check("unlock_with_key", doors.try_unlock_building(pj), _ok)
	_ok = _check("key_consumed", inv.count("police_key") == 0, _ok)
	_ok = _check("unlocked_now", not doors.is_building_locked(pj), _ok)
	doors.set_building_door_open(pj, true, false)
	_ok = _check("door_swings",
		bool(((nb.buildings[pj] as Dictionary)["door"] as Dictionary)["open"]), _ok)
	doors.set_building_door_open(pj, false, false)
	# --- Lockpick path: re-lock, craft-free lockpick, unlock.
	((nb.buildings[pj] as Dictionary)["door"] as Dictionary)["locked"] = true
	inv.add("lockpick", 1)
	_ok = _check("unlock_with_lockpick", doors.try_unlock_building(pj), _ok)
	_ok = _check("lockpick_consumed", inv.count("lockpick") == 0, _ok)
	# --- Medicine: strong heal, usable.
	_ok = _check("medicine_heal_80",
		is_equal_approx(LootDefs.item_heal("medicine"), 80.0), _ok)
	_ok = _check("medicine_usable", LootDefs.is_usable("medicine"), _ok)
	var health = _main.get_node("Player/Health")
	health.hp = 10.0
	inv.add("medicine", 1)
	_ok = _check("medicine_use", inv.use("medicine"), _ok)
	_ok = _check("medicine_healed", health.hp > 80.0, _ok)
	# --- Rifle/ammo are inert Phase-A loot.
	_ok = _check("rifle_inert", not LootDefs.is_usable("rifle"), _ok)
	_ok = _check("ammo_inert", not LootDefs.is_usable("ammo"), _ok)
	# --- Brutes: exactly 2, beefy, only from brute spawns.
	var zm = _main.get_node("Zombies")
	var brutes := 0
	var walkers := 0
	for z in zm.zombies:
		if z.is_brute:
			brutes += 1
			_ok = _check("brute_hp", is_equal_approx(z.hp, 220.0), _ok)
			_ok = _check("brute_bulky", z.visual._body.scale.x > 1.2, _ok)
		else:
			walkers += 1
			_ok = _check("walker_hp_untouched",
				is_equal_approx(z.hp, 100.0), _ok)
	_ok = _check("brute_count_2", brutes == 2, _ok)
	_ok = _check("walker_count",
		walkers == 10 + nb.building_zombie_spawns.size(), _ok)
	# --- Building loot containers are registered: 18 outdoor + house
	# interiors (1 corner + 1 bedroom duffel per non-safehouse house +
	# 1 back-corner junk crate per house) + commercial.
	_ok = _check("building_containers",
		_main.get_node("Loot").container_count() == 18 + 3 * nb.houses.size() - 1 \
			+ nb.building_loot.size(), _ok)
	# --- Lockpick crafting: 2 scrap => 1 lockpick.
	var craft = _main.get_node("Crafting")
	inv.add("scrap", 2)
	_ok = _check("lockpick_recipe", craft.can_craft("lockpick"), _ok)
	_ok = _check("lockpick_craft", craft.craft("lockpick"), _ok)
	_ok = _check("lockpick_made", inv.count("lockpick") == 1, _ok)
	_ok = _check("scrap_spent", inv.count("scrap") == 0, _ok)
	# --- Police key exists in exactly one house container.
	var key_count := 0
	for c in _main.get_node("Loot").get_containers():
		for it in c.loot:
			if String((it as Array)[0]) == "police_key":
				key_count += 1
	_ok = _check("key_in_one_container", key_count == 1, _ok)


func _police_idx(nb) -> int:
	for j in nb.buildings.size():
		if String((nb.buildings[j] as Dictionary)["kind"]) == "police":
			return j
	return -1


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("BUILDQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
