extends SceneTree
## HD-pass visual QA screenshots under Xvfb (software GL is slow — be patient).
##   g1 zombie close-up, day (faces camera)
##   g2 zombie close-up, night (glowing eyes)
##   g3 player close-up, day
##   g4 street view, day (down the road)
##   g5 house interior, day
##   g6 night street, flashlight on a house
## Usage: xvfb-run -a godot --path . --script res://tests/graphics_shots.gd
## Writes to qa_shots/graphics/*.png.

var _phase := 0
var _frames := 0
var _booted := false
var _main: Node
var _cam: Camera3D
const OUT := "/home/hatch/workspace/last-shift/qa_shots/graphics"
const WAIT := 25
const COFF := Vector3(2.3, 2.1, 3.5) # close-up camera offset


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("GSHOT saved ", name)


func _boot() -> void:
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
	print("GSHOT booted")


func _player() -> Node:
	return _main.get_node("Player")


func _rig() -> Node:
	return _main.get_node("CameraRig")


func _zombie() -> Node:
	var zs: Array = _main.get_node("Zombies").living_zombies()
	return zs[0] if not zs.is_empty() else null


func _closeup(focus: Vector3) -> void:
	_free_cam()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 220.0
	root.add_child(_cam)
	_cam.global_position = focus + COFF
	_cam.look_at(focus + Vector3(0, 1.0, 0))
	_cam.current = true


func _free_cam() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	_rig().get_node("Camera3D").current = true


func _set_hour(h: float) -> void:
	_main.get_node("TimeManager").set("time_hours", h)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	_frames += 1
	match _phase:
		0:
			# Settle, then stage: player on the road (no CLAIM prompt),
			# zombie beside them, frozen, facing the close-up camera.
			if _frames >= 60:
				var p := _player()
				p.set("global_position", Vector3(14.0, 0, -7.0))
				p.set("velocity", Vector3.ZERO)
				var z := _zombie()
				var zp: Vector3 = p.get("global_position") + Vector3(2.0, 0, 1.0)
				z.set("global_position", zp)
				z.set_physics_process(false)
				z.set("rotation", Vector3(0, atan2(-COFF.x, -COFF.z), 0))
				_closeup(zp)
				_phase = 1
				_frames = 0
		1:
			if _frames >= WAIT:
				_shot("g1_zombie_day")
				_set_hour(23.5) # night: eyes glow
				# Aim the player's flashlight at the zombie's face.
				var p := _player()
				var z := _zombie()
				var to_z: Vector3 = (z.get("global_position") as Vector3) - (p.get("global_position") as Vector3)
				p.set("rotation", Vector3(0, atan2(-to_z.x, -to_z.z), 0))
				_phase = 2
				_frames = 0
		2:
			if _frames >= WAIT:
				_shot("g2_zombie_night")
				_set_hour(10.0)
				# Face the player toward the close-up camera for the beauty shot.
				_player().set("rotation", Vector3(0, atan2(-COFF.x, -COFF.z), 0))
				_closeup(_player().get("global_position"))
				_phase = 3
				_frames = 0
		3:
			if _frames >= WAIT:
				_shot("g3_player_day")
				# Street view: clear stretch of EW road, camera EAST looking west
				# (house at x~23 sits west of the player; keep it out of the foreground).
				_free_cam()
				_player().set("global_position", Vector3(30.0, 0, -7.0))
				_rig().set_yaw_immediate(PI * 0.5)
				_rig().snap()
				_phase = 4
				_frames = 0
		4:
			if _frames >= WAIT:
				_shot("g4_street_day")
				# Inside the safehouse: roof hides, interior visible.
				var hood := _main.get_node("Neighborhood")
				var sh: Dictionary = hood.houses[hood.safehouse_index]
				var hp: Vector3 = sh["pos"]
				var p := _player()
				p.set("global_position", hp + Vector3(0.5, 0, 0.5))
				p.set("velocity", Vector3.ZERO)
				_rig().set_yaw_immediate(0.0)
				_rig().snap()
				_phase = 5
				_frames = 0
		5:
			if _frames >= WAIT:
				_shot("g5_interior_day")
				# Night street: player faces a house so the flashlight lands.
				_set_hour(23.5)
				var p := _player()
				p.set("global_position", Vector3(10.0, 0, -7.0))
				p.set("velocity", Vector3.ZERO)
				p.set("rotation", Vector3(0, 0, 0))
				_rig().set_yaw_immediate(PI * 0.5)
				_rig().snap()
				_phase = 6
				_frames = 0
		6:
			if _frames >= WAIT:
				_shot("g6_street_night")
				print("GSHOTS_DONE")
				quit(0)
				return true
	return false
