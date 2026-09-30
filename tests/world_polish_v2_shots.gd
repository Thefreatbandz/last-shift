extends SceneTree
## World-polish v2 before/after screenshots. Fixed camera positions, fixed
## seed, fixed times of day — run with --tag=before and --tag=after:
##   xvfb-run -a godot --path . --script res://tests/world_polish_v2_shots.gd -- --tag=before
## Saves qa_shots/world_polish_v2/<tag>_street.png, <tag>_house.png, <tag>_night.png

var _booted := false
var _main: Node
var _cam: Camera3D
var _phase := 0
var _t0 := 0
var _tag := "shot"
var _player_pos := Vector3(14.0, 0.0, -7.0)


func _now() -> int:
	return int(Time.get_ticks_msec())


func _shot(name: String) -> void:
	var out := "/home/hatch/workspace/last-shift/qa_shots/world_polish_v2"
	DirAccess.make_dir_recursive_absolute(out)
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + _tag + "_" + name + ".png")
	print("V2SHOT saved ", _tag, "_", name)


func _boot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	for c in root.get_children():
		if c.name == &"Main":
			root.remove_child(c)
			c.free()
	root.get_node("RunState").set("world_seed", 48392017)
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	_main.name = &"Main"
	root.add_child(_main)
	current_scene = _main
	_main.get_node("TimeManager").set("time_hours", 10.0)
	print("V2SHOT booted tag=", _tag)


func _player() -> Node:
	return _main.get_node("Player")


func _cam_at(pos: Vector3, focus: Vector3) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_cam.far = 220.0
		root.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	match _phase:
		0:
			_t0 = _now()
			_phase = 1
		1:
			if _now() - _t0 > 5000:
				var p := _player()
				p.set("global_position", _player_pos)
				p.set("velocity", Vector3.ZERO)
				var hood := _main.get_node("Neighborhood")
				var ez: float = hood.get("road_ew_z")
				var nx: float = hood.get("road_ns_x")
				# On the east-west road looking down its length: road wear,
				# cars, lamps, houses on both sides, treeline beyond.
				_cam_at(Vector3(nx + 30.0, 5.2, ez + 2.0),
					Vector3(nx - 16.0, 1.0, ez - 2.0))
				_t0 = _now()
				_phase = 2
		2:
			if _now() - _t0 > 800:
				_shot("street")
				var hood2 := _main.get_node("Neighborhood")
				var houses: Array = hood2.get("houses")
				var h: Dictionary = houses[1]
				var hp: Vector3 = h["pos"]
				# Pulled back: full house facade, lawn, street in frame.
				_cam_at(hp + Vector3(11.0, 5.5, 11.0), hp + Vector3(0, 1.6, 0))
				_t0 = _now()
				_phase = 3
		3:
			if _now() - _t0 > 800:
				_shot("house")
				_main.get_node("TimeManager").set("time_hours", 23.5)
				var hood3 := _main.get_node("Neighborhood")
				var ez3: float = hood3.get("road_ew_z")
				var nx3: float = hood3.get("road_ns_x")
				_cam_at(Vector3(nx3 + 30.0, 5.2, ez3 + 2.0),
					Vector3(nx3 - 16.0, 1.0, ez3 - 2.0))
				_t0 = _now()
				_phase = 4
		4:
			if _now() - _t0 > 1500:
				_shot("night")
				print("V2SHOT done")
				quit(0)
				return true
	return false
