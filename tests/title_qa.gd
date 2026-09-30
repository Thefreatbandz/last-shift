extends SceneTree
## Headless QA for the title-screen path: boot with no seed => title menu,
## player frozen, no world built; then new-game => a seeded run starts.
##   godot --headless --path . --script res://tests/title_qa.gd

var _booted := false
var _frames := 0
var _phase := 0
var _ok := true
var _main: Node


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _phase == 0 and _frames == 60:
		_ok = _check("no_run_yet", not _main._run_started, _ok)
		_ok = _check("title_open", _main.hud.is_menu_open(), _ok)
		_ok = _check("player_frozen",
			_main.player.process_mode == Node.PROCESS_MODE_DISABLED, _ok)
		_ok = _check("no_houses", _main.neighborhood.houses.is_empty(), _ok)
		_main._on_new_game()
		_phase = 1
		_frames = 0
	elif _phase == 1 and _frames == 120:
		_main = current_scene # reload freed the old scene
		_ok = _check("run_started", _main._run_started, _ok)
		_ok = _check("seed_chosen", int(root.get_node("RunState").get("world_seed")) >= 0, _ok)
		_ok = _check("houses_built", current_scene.get_node("Neighborhood").houses.size() >= 7, _ok)
		_ok = _check("title_closed", not current_scene.hud.is_menu_open(), _ok)
		print("TITLEQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("TITLEQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
