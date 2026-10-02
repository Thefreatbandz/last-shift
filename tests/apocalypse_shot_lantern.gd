extends SceneTree
## Single shot: lantern-lit compound interior at night.
## Usage: xvfb-run -a godot --path . --script res://tests/apocalypse_shot_lantern.gd

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
		tm.call("set_time", 1.0) # deep night
		var nb = _main.get_node("Neighborhood")
		var iz = nb.get("interior_zones")
		var z: Dictionary = (iz.get("zones") as Array)[0]
		(z["root"] as Node3D).visible = true
		_main.player.global_position = (z["spawn_in"] as Vector3) + Vector3(2.0, 0, 2.0)
	elif _frames == 90:
		DirAccess.make_dir_recursive_absolute(OUT)
		var img := root.get_texture().get_image()
		img.save_png(OUT + "/apoc_lantern_interior.png")
		print("APOCSHOT saved apoc_lantern_interior.png")
		quit(0)
		return true
	return false
