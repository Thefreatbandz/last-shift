extends SceneTree
## Screenshot: safehouse exterior at morning, player outside (roof stays on).
## Usage: xvfb-run -a godot --path . --script res://tests/probe_safehouse_shot.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _nb: Node
var _tm: Node
var _seed := 48392017

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("SHSHOT saved ", n)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		if OS.has_feature("editor"):
			pass
		var args := OS.get_cmdline_user_args()
		for a in args:
			if a.begins_with("--shotseed="):
				_seed = int(a.trim_prefix("--shotseed="))
		root.get_node("RunState").set("world_seed", _seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_tm = _main.get_node("TimeManager")
		return false
	_frames += 1
	if _frames == 40:
		_tm.call("set_time", 10.2)
		var porch: Vector3 = _nb.get("safehouse_porch")
		_main.player.global_position = porch + Vector3(0, 0.3, 2.0)
	elif _frames == 100:
		_shot("safehouse_morning_%d.png" % _seed)
		quit(0)
		return true
	return false
