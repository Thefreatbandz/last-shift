extends SceneTree
## Expansion + loot variety screenshots: aerial overview of the bigger map,
## the treeline/brush edge, and a close-up of each new container type.
##   xvfb-run -a godot --path . --script res://tests/expansion_shots.gd
## Saves qa_shots/expansion/*.png

var _booted := false
var _main: Node
var _cam: Camera3D
var _phase := 0
var _t0 := 0
var _kinds: Array = []
var _kind_idx := 0


func _now() -> int:
	return int(Time.get_ticks_msec())


func _shot(name: String) -> void:
	var out := "/home/hatch/workspace/last-shift/qa_shots/expansion"
	DirAccess.make_dir_recursive_absolute(out)
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("EXPSHOT saved ", name)


func _boot() -> void:
	root.get_node("RunState").set("world_seed", 48392017)
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	_main.name = &"Main"
	root.add_child(_main)
	current_scene = _main
	_main.get_node("TimeManager").set("time_hours", 10.5)
	_kinds = ["trash", "corpse", "fresh_corpse", "toolbox", "firstaid",
		"duffel", "crate"]
	print("EXPSHOT booted")


func _cam_at(pos: Vector3, focus: Vector3, fov := 50.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = fov
		_cam.far = 500.0
		root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _kind_pos(kind: String) -> Vector3:
	var hood := _main.get_node("Neighborhood")
	for e in hood.get("outdoor_loot") as Array:
		var ed := e as Dictionary
		if String(ed["kind"]) == kind:
			return ed["pos"] as Vector3
	return Vector3.ZERO


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		_t0 = _now()
		return false
	var hood := _main.get_node("Neighborhood")
	match _phase:
		0: # aerial overview of the expanded 200x200 map
			if _now() - _t0 > 6000:
				_cam_at(Vector3(0, 52, 88), Vector3(0, 0, -12), 55.0)
				_t0 = _now()
				_phase = 1
		1:
			if _now() - _t0 > 900:
				_shot("overview")
				# treeline edge: diagonal along the brush wall + forest barrier
				_cam_at(Vector3(-25, 2.8, 89), Vector3(28, 2.2, 99))
				_t0 = _now()
				_phase = 2
		2:
			if _now() - _t0 > 900:
				_shot("edge")
				_kind_idx = 0
				_t0 = _now()
				_phase = 3
		3: # close-up of each container type
			if _now() - _t0 > 700:
				if _kind_idx >= _kinds.size():
					print("EXPSHOT done")
					quit(0)
					return true
				var k := String(_kinds[_kind_idx])
				var p := _kind_pos(k)
				_cam_at(p + Vector3(2.6, 1.9, 2.6), p + Vector3(0, 0.35, 0))
				_t0 = _now()
				_phase = 4
		4:
			if _now() - _t0 > 700:
				_shot("container_" + String(_kinds[_kind_idx]))
				_kind_idx += 1
				_t0 = _now()
				_phase = 3
	return false
