extends SceneTree
## 200-frame full-game smoke test for three explicit seeds.
##   godot --headless --path . --script res://tests/smoke3.gd
## Grep for SCRIPT ERROR separately.

var _seeds := [48392017, 777, 12345678]
var _idx := 0
var _frames := 0
var _booted := false
var _ok := true
var _main: Node


func _boot() -> void:
	root.get_node("RunState").set("world_seed", _seeds[_idx])
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	_main.name = &"Main"
	root.add_child(_main)
	current_scene = _main


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	_frames += 1
	if _frames == 200:
		var nb = _main.get_node("Neighborhood")
		var ok: bool = _main._run_started
		ok = ok and nb.houses.size() >= 7
		# Building types: 10 outdoor walkers + interior walkers + Brutes
		# (police station). Count must match the builder's spawn data.
		var expect_z: int = 10 + (nb.brute_spawns as Array).size() \
			+ (nb.building_zombie_spawns as Array).size()
		ok = ok and _main.get_node("Zombies").zombies.size() == expect_z
		ok = ok and _main.player.global_position.distance_to(nb.player_start) < 2.0
		print("SMOKE3 seed=", _seeds[_idx], " houses=", nb.houses.size(),
			" hash=", nb.layout_hash(), ": ", "PASS" if ok else "FAIL")
		_ok = _ok and ok
		_idx += 1
		if _idx >= _seeds.size():
			print("SMOKE3_RESULT ok=", _ok)
			quit(0 if _ok else 1)
			return true
		_main.queue_free()
		_frames = -30 # let the old scene flush before booting the next
		_booted = false
	elif _frames < 0:
		pass
	return false
