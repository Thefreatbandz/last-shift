extends SceneTree
## Headless functional QA for the minimap: model/view wiring, fog of war,
## player tracking, zombie dots, containers, safehouse claim marker,
## expanded toggle, and new-game (scene reload) regeneration.
## Run:
##   godot --headless --path . --fixed-fps 60 --script res://tests/minimap_qa.gd
## Grep the output for SCRIPT ERROR separately.

var _booted := false
var _frames := 0
var _phase := 0
var _ok := true
var _main: Node
var _rs: Node
var _mmap: Node
var _view: Control
var _fog_before := 0

const SEED_A := 777001


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_rs = root.get_node("RunState")
		_rs.set("world_seed", SEED_A)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _phase:
		0:
			if _frames == 30:
				_phase_a()
		1:
			if _frames == 30:
				_phase_b()
		2:
			if _frames == 30:
				_phase_c()
	return false


func _phase_a() -> void:
	# Wiring + initial state (a few 10Hz ticks have run by frame 30).
	_mmap = _main.get_node("Minimap")
	_view = _main.get("_minimap_view")
	_ok = _check("model_exists", _mmap != null, _ok)
	_ok = _check("view_exists", _view != null, _ok)
	_ok = _check("view_hidden_with_hud",
		_view.get_parent() == _main.hud._hud_root, _ok)
	_ok = _check("seed_matches", int(_mmap.get("seed")) == SEED_A, _ok)
	_ok = _check("houses_tracked", _mmap.houses().size() >= 7, _ok)
	_ok = _check("safehouse_idx", _mmap.safehouse_index() >= 0, _ok)
	_ok = _check("roads_four", _mmap.road_rects().size() == 4, _ok)
	_ok = _check("fog_revealed_start", _mmap.revealed_count() > 0, _ok)
	var pp: Vector2 = _mmap.player_pos()
	var gp: Vector3 = _main.player.global_position
	_ok = _check("player_tracked",
		pp.distance_to(Vector2(gp.x, gp.z)) < 0.5, _ok)
	var n_cont: int = _main.get_node("Loot").container_count()
	_ok = _check("containers_tracked",
		_mmap.containers_unsearched().size() == n_cont, _ok)
	_ok = _check("none_searched_yet",
		_mmap.containers_searched().is_empty(), _ok)
	_fog_before = _mmap.revealed_count()
	# Teleport far away: fog must grow, zombie dots must appear near a zombie.
	var z0: Vector3 = _main.get_node("Zombies").living_zombies()[0].global_position
	_main.player.global_position = z0 + Vector3(5, 0, 0)
	_frames = 0
	_phase = 1


func _phase_b() -> void:
	_ok = _check("fog_grows_with_travel",
		_mmap.revealed_count() > _fog_before, _ok)
	_ok = _check("zombie_dots_near",
		_mmap.zombie_dots().size() > 0, _ok)
	var pp: Vector2 = _mmap.player_pos()
	var gp: Vector3 = _main.player.global_position
	_ok = _check("player_tracked_after_tp",
		pp.distance_to(Vector2(gp.x, gp.z)) < 0.5, _ok)
	# Claim the safehouse: marker must flip to claimed.
	_main.get_node("Safehouse").claim()
	_ok = _check("claimed_flag", _mmap.is_claimed(), _ok)
	# Expanded overlay toggle (logic only; visuals verified via Xvfb shots).
	_view.set_expanded(true)
	_ok = _check("expanded_on", _view.expanded, _ok)
	_view.set_expanded(false)
	_ok = _check("expanded_off", not _view.expanded, _ok)
	# New game: scene reload with a fresh seed (the real flow).
	_main._on_new_game()
	_frames = 0
	_phase = 2


func _phase_c() -> void:
	_main = current_scene
	_mmap = _main.get_node("Minimap")
	_view = _main.get("_minimap_view")
	var new_seed := int(_mmap.get("seed"))
	_ok = _check("new_seed", new_seed != SEED_A and new_seed >= 0, _ok)
	_ok = _check("regen_houses", _mmap.houses().size() >= 7, _ok)
	_ok = _check("regen_fog", _mmap.revealed_count() > 0, _ok)
	_ok = _check("regen_view", _view != null and not _view.expanded, _ok)
	print("MINIMAPQA_RESULT ok=", _ok)
	quit(0 if _ok else 1)


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("MINIMAPQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
