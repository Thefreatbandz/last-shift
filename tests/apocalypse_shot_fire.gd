extends SceneTree
## Retake: night street with barrel fire, camera snapped.
## Usage: xvfb-run -a godot --path . --script res://tests/apocalypse_shot_fire.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 30:
		var tm = _main.get_node("TimeManager")
		tm.call("set_time", 1.0)
		var nb = _main.get_node("Neighborhood")
		var d = nb.find_children("*", "ApocalypseDressing", true, false)[0]
		var fp := Vector3.ZERO
		for e in d.get("_fires"):
			var l = (e as Dictionary).get("light")
			if l != null:
				fp = (l as Node3D).global_position
				break
		_main.player.global_position = fp + Vector3(3.5, 0, 3.5)
		var cam = _main.get_node("CameraRig")
		if cam.has_method("snap"):
			cam.call("snap")
	elif _frames == 110:
		DirAccess.make_dir_recursive_absolute(OUT)
		var img := root.get_texture().get_image()
		img.save_png(OUT + "/apoc_night_fire.png")
		print("APOCSHOT saved apoc_night_fire.png")
		quit(0)
		return true
	return false
