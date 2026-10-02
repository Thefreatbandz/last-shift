extends SceneTree
## Zombie-pressure QA: wave zombies keep attacking the house instead of
## going passive.
## (a) A SUSPICIOUS zombie within POUND_RANGE of a closed door pounds it
##     (barricade door_hp drops) instead of staring.
## (b) Night phase re-aggro: a WANDER wave zombie returns to SUSPICIOUS
##     with a fresh stimulus; CHASE zombies are untouched.
## (c) Day phase: no re-aggro fires (WANDER stays WANDER, accumulator idle).
## Run:
##   godot --headless --path . --script res://tests/zombie_pressure_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEED := 48392017

var _booted := false
var _frames := 0
var _ok := true

var _main: Node
var _player: Node
var _zombies: Node
var _barricades: Node
var _waves: Node
var _doors: Node
var _nb: Node

# Lazy-loaded like interior_qa.gd: class_name scripts that touch the Sound
# autoload must load here, not via static class_name refs.
var _ZA: GDScript
var _BM: GDScript

var _zz: Node = null # pound-test zombie
var _bkey := ""
var _door_hp_before := 0.0
var _door_pos := Vector3.ZERO
var _wv: Array = [] # wave zombies for the re-aggro checks
var _wz: Node = null # the lone survivor used in (b)/(c)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("ZPQA PASS ", label)
	else:
		_ok = false
		print("ZPQA FAIL ", label)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_ZA = load("res://scripts/zombie/zombie_ai.gd")
		_BM = load("res://scripts/world/barricade_manager.gd")
		_static_checks()
		root.get_node("RunState").set("world_seed", SEED)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _frames:
		30:
			_live_setup()
		60:
			_start_pound_test()
		260:
			_assert_pounding()
			_setup_reaggro()
		266:
			_assert_reaggro_direct()
		272:
			_start_night_accumulator()
		340:
			_assert_night_accumulator()
			_start_day_quiet()
		780:
			_assert_day_quiet()
			_finish()
	return false


func _static_checks() -> void:
	var za := FileAccess.get_file_as_string("res://scripts/zombie/zombie_ai.gd")
	var sus := za.find("func _do_suspicious")
	_check("suspicious_pounds_first",
		sus >= 0 and za.find("_pound_door_first()", sus) > sus
		and za.find("_pound_door_first()", sus) < za.find("func _do_chase", sus))
	var wm := FileAccess.get_file_as_string("res://scripts/world/wave_manager.gd")
	_check("reaggro_fn_exists", wm.contains("func _reaggro_wave()"))
	_check("night_calls_reaggro", wm.contains("_reaggro_wave()"))
	_check("reaggro_every_5s", wm.contains("_reaggro_t >= 5.0"))
	_check("reaggro_skips_dead", wm.contains("not z.is_dead()"))


func _live_setup() -> void:
	_player = _main.get_node("Player")
	_zombies = _main.get_node("Zombies")
	_barricades = _main.get_node("Barricades")
	_waves = _main.get_node("Waves")
	_doors = _main.get_node("HouseDoors")
	_nb = _main.get_node("Neighborhood")
	_check("refs_ok", _player != null and _zombies != null
		and _barricades != null and _waves != null and _nb != null)


func _start_pound_test() -> void:
	# Building 0's door, closed, unbarricaded boards (hp 0 -> pound hits door_hp).
	var bi := 0
	_bkey = _BM.key_for_building(bi)
	var b := ((_nb.get("buildings") as Array)[bi]) as Dictionary
	var door := b["door"] as Dictionary
	_door_pos = door["pos"] as Vector3
	var face := float(b.get("face", 1.0))
	_doors.call("set_building_door_open", bi, false, false)
	# Player far away so the zombie never sees him (no CHASE escalation).
	_player.set("global_position", _door_pos + Vector3(40, 0, 40))
	# Zombie just inside pound range of the closed door, SUSPICIOUS with a
	# stale stimulus — the exact "staring at the house" scenario.
	var out := Vector3(0, 0, face)
	_zz = _zombies.call("_spawn_at", _door_pos + out * 1.8 + Vector3(0, 0.3, 0))
	_zz.set("state", _ZA.State.SUSPICIOUS)
	_zz.set("_stimulus", _door_pos + Vector3(20, 0, 0))
	_zz.set("_look_t", 0.0)
	var st: Dictionary = _barricades.get("_st")
	# Fortify the test door: the headless clock runs many physics ticks
	# per render frame, so a 60hp door would burst open mid-test and the
	# reset would mask the damage. We assert pound DAMAGE, not a breach.
	(st[_bkey] as Dictionary)["door_hp"] = 100000.0
	_door_hp_before = float((st[_bkey] as Dictionary)["door_hp"])
	_check("pound_setup_door_closed", not bool((st[_bkey] as Dictionary).get("open", false)))


func _assert_pounding() -> void:
	var st: Dictionary = _barricades.get("_st")
	var hp := float((st[_bkey] as Dictionary)["door_hp"])
	_check("suspicious_pounds_door", hp < _door_hp_before)
	var zp: Vector3 = _zz.get("global_position")
	_check("pounder_stays_at_door", zp.distance_to(_door_pos) < 4.0)
	_check("pounder_not_wandering", int(_zz.get("state")) != _ZA.State.WANDER)


func _setup_reaggro() -> void:
	# Fresh wave: every zombie spawns SUSPICIOUS with the player's position.
	_waves.call("_spawn_wave", 1)
	_wv = _waves.get("wave_zombies")
	_check("wave_spawned", _wv.size() >= 2)
	_wz = _wv[0]
	# Survivor 1: falls back to WANDER with a stale stimulus (the bug).
	_wz.set("state", _ZA.State.WANDER)
	_wz.set("_stimulus", Vector3(500, 0, 500))
	# Survivor 2: mid-CHASE — re-aggro must leave it alone.
	(_wv[1] as Node).set("state", _ZA.State.CHASE)
	# Kill the rest so the night loop stays quiet for the checks.
	for i in range(2, _wv.size()):
		var z := _wv[i] as Node
		z.call("take_damage", 99999.0, z.get("global_position"))
	_waves.set("phase", "night")
	_waves.set("_spawned_this_night", true)


func _assert_reaggro_direct() -> void:
	# Direct call first: deterministic, no timing involved.
	var pp: Vector3 = _player.get("global_position")
	_waves.call("_reaggro_wave")
	_check("wander_reaggroed", int(_wz.get("state")) == _ZA.State.SUSPICIOUS)
	var stim: Vector3 = _wz.get("_stimulus")
	_check("stimulus_fresh", stim.distance_to(pp) < 2.0)
	_check("chase_untouched", int((_wv[1] as Node).get("state")) == _ZA.State.CHASE)


func _start_night_accumulator() -> void:
	# Prime the accumulator near its 5s trip point with a wanderer to
	# catch: the night loop must trip it and re-aggro. Frame-count timing
	# is meaningless here (headless runs many physics ticks per render
	# frame), so we assert the OBSERVABLE re-aggro, not a timer value.
	_waves.set("_reaggro_t", 4.9)
	_wz.set("state", _ZA.State.WANDER)
	_wz.set("_stimulus", Vector3(500, 0, 500))


func _assert_night_accumulator() -> void:
	# The accumulator tripped during night and re-aggroed the wanderer.
	_check("night_accumulator_ticks", int(_wz.get("state")) == _ZA.State.SUSPICIOUS)


func _start_day_quiet() -> void:
	# Back to WANDER, far from the player (no legit perception), day phase:
	# nothing may re-aggro it now.
	_wz.set("state", _ZA.State.WANDER)
	_wz.set("_stimulus", Vector3(500, 0, 500))
	_wz.set("global_position", (_player.get("global_position") as Vector3) + Vector3(60, 0, 0))
	(_wv[1] as Node).call("take_damage", 99999.0, (_wv[1] as Node).get("global_position"))
	_waves.set("phase", "day")
	_waves.set("_reaggro_t", 0.0)


func _assert_day_quiet() -> void:
	# 440 frames ≈ 7.3s > the 5s re-aggro interval: had day been calling it,
	# the zombie would be SUSPICIOUS again.
	_check("day_no_reaggro", int(_wz.get("state")) == _ZA.State.WANDER)
	_check("day_accumulator_idle", is_zero_approx(float(_waves.get("_reaggro_t"))))


func _finish() -> void:
	# Clean up scratch zombies so the smoke run stays quiet.
	if is_instance_valid(_zz):
		_zz.queue_free()
	if is_instance_valid(_wz):
		_wz.queue_free()
	print("ZPQA DONE ok=", _ok)
	quit(0 if _ok else 1)
