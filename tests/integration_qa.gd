extends SceneTree
## Headless integration QA: boots the real main scene with a seed, runs
## 200 frames, exercises pause/resume, then new-game reload TWICE (fresh
## seeds each time). Verifies one indoor loot container per house and
## HouseDoors registration. Run:
##   godot --headless --path . --script res://tests/integration_qa.gd
## Grep the output for SCRIPT ERROR separately.

var _booted := false
var _frames := 0
var _phase := 0
var _ok := true
var _hash_a := ""
var _hash_b := ""
var _nodes_a := 0
var _rs: Node # RunState autoload (fetched dynamically; not visible at compile)
var _main: Node

const CURATED_SPOTS := 18 # seeded outdoor loot variety (NeighborhoodBuilder.OUTDOOR_LOOT_COUNT)
const OFFICER_CORPSE := 1 # dead officer with a pistol outside the police station


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_rs = root.get_node("RunState")
		_rs.set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _phase:
		0:
			if _frames == 200:
				_check_run("a", 48392017)
				# Exercise the pause menu wiring directly.
				_main._on_menu_button()
				_ok = _check("paused_flag", _main._paused, _ok)
				_ok = _check("tree_paused", paused, _ok)
				_ok = _check("menu_open", _main.hud.is_menu_open(), _ok)
				_main._on_continue()
				_ok = _check("resumed", not _main._paused and not paused, _ok)
				_ok = _check("menu_closed", not _main.hud.is_menu_open(), _ok)
				# New game #1: fresh seed + scene reload (same as the menu button).
				_main._on_new_game()
				_phase = 1
				_frames = 0
		1:
			if _frames == 200:
				_main = current_scene
				_hash_b = _main.get_node("Neighborhood").layout_hash()
				_check_run("b", -1)
				_ok = _check("new_seed_b", int(_rs.get("world_seed")) != 48392017, _ok)
				_ok = _check("different_world_b",
					_hash_b != _hash_a and _hash_b != "", _ok)
				# New game #2: reload once more, seed must change again.
				_main._on_new_game()
				_phase = 2
				_frames = 0
		2:
			if _frames == 200:
				_main = current_scene
				_check_run("c", -1)
				var hash_c: String = _main.get_node("Neighborhood").layout_hash()
				_ok = _check("new_seed_c",
					int(_rs.get("world_seed")) != 48392017, _ok)
				_ok = _check("different_world_c",
					hash_c != _hash_a and hash_c != _hash_b and hash_c != "", _ok)
				# Node count should be in the same ballpark: no leaks, no leftovers.
				var nodes_c := _count(_main)
				var ratio := float(nodes_c) / float(maxi(_nodes_a, 1))
				_ok = _check("nodes_stable", ratio > 0.7 and ratio < 1.4, _ok)
				print("INTEGQA run_c hash=", hash_c, " nodes=", nodes_c,
					" ratio=", ratio)
				print("INTEGQA_RESULT ok=", _ok)
				quit(0 if _ok else 1)
				return true
	return false


func _check_run(tag: String, expect_seed: int) -> void:
	var nb = _main.get_node("Neighborhood")
	var n_houses: int = nb.houses.size()
	if tag == "a":
		_hash_a = nb.layout_hash()
		_nodes_a = _count(_main)
	_ok = _check("run_started_" + tag, _main._run_started, _ok)
	_ok = _check("houses_built_" + tag, n_houses >= 7, _ok)
	# Base pack is 10 outdoor walkers on the expanded map; building types add
	# 2 Brutes (police) + interior walkers (hospital/grocery/offices).
	_ok = _check("zombie_pack_" + tag,
		_main.get_node("Zombies").zombies.size() == 10 \
			+ nb.brute_spawns.size() + nb.building_zombie_spawns.size(), _ok)
	_ok = _check("player_at_start_" + tag,
		_main.player.global_position.distance_to(nb.player_start) < 2.0, _ok)
	_ok = _check("safehouse_wired_" + tag,
		_main.get_node("Safehouse").porch.distance_to(nb.safehouse_porch) < 0.01, _ok)
	if expect_seed >= 0:
		_ok = _check("seed_set_" + tag, int(_rs.get("world_seed")) == expect_seed, _ok)
	# Indoor loot per house: 1 corner container + 1 bedroom duffel (every
	# non-safehouse house) + 1 back-corner junk crate (+ curated street
	# spots + seeded commercial-building containers + the dead officer
	# outside the police station, gun-findability 2026-10-02).
	_ok = _check("loot_per_house_" + tag,
		_main.get_node("Loot").container_count() == CURATED_SPOTS \
			+ (3 * n_houses - 1) + nb.building_loot.size() + OFFICER_CORPSE, _ok)
	# Every generated house and commercial building registered with HouseDoors.
	_ok = _check("doors_registered_" + tag,
		_main.get_node("HouseDoors")._ids.size() \
			+ _main.get_node("HouseDoors")._bids.size() \
			== n_houses + nb.buildings.size(), _ok)
	print("INTEGQA run_", tag, " hash=", nb.layout_hash(), " houses=", n_houses)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("INTEGQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
