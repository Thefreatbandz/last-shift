extends SceneTree
## Re-shoot v2: office tower (shallow camera pitch) + brute (pinned in frame).
##   xvfb-run -a godot --path . --script res://tests/building_shots4.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb
var _rig
var _cam: Camera3D
var _pin_brute := false
var _brute_spot := Vector3.ZERO
var _brute_yaw := 0.0


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("BSHOT4 saved ", name)


func _bld(kind: String) -> Dictionary:
	for b in _nb.buildings:
		var bd := b as Dictionary
		if String(bd["kind"]) == kind:
			return bd
	return {}


func _place(player_pos: Vector3, look_at: Vector3) -> void:
	_main.player.global_position = player_pos
	var d := look_at - player_pos
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	d = d.normalized()
	_rig.set_yaw_immediate(atan2(-d.x, -d.z))
	_rig.snap()
	_main.player.get_node("Health").heal(1000.0)


func _brute_node() -> Node:
	for z in _main.get_node("Zombies").zombies:
		if z.get("is_brute"):
			return z
	return null


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_rig = _main.get_node("CameraRig")
		_cam = _rig.get_node("Camera3D")
		return false
	_main.player.get_node("Health").heal(1000.0)
	if _pin_brute:
		var bz := _brute_node()
		if bz != null:
			bz.global_position = _brute_spot
			bz.rotation.y = _brute_yaw
	_frames += 1
	match _phase:
		0:
			if _frames == 10:
				var o := _bld("office_tall")
				var op: Vector3 = o["pos"]
				var of := float(o["face"])
				# Shallow the pitch so the 10m tower fits in frame.
				_cam.rotation_degrees.x = -30.0
				_place(op + Vector3(0, 0, of * 20.0), op + Vector3(0, 4.0, 0))
			elif _frames == 70:
				_shot("bld2_office_tall_ext")
				_cam.rotation_degrees.x = -55.0
				_phase = 1
				_frames = 0
		1:
			if _frames == 10:
				var p := _bld("police")
				var pp: Vector3 = p["pos"]
				var pf := float(p["face"])
				# Stand 12m out so there's room for the brute between us
				# and the wall (wall is 5m from center).
				_place(pp + Vector3(-6.0, 0.2, pf * 12.0), pp + Vector3(-6.0, 1.0, pf * 2.0))
				# Hide the live brute far away so it can't wander into frame.
				var live := _brute_node()
				if live != null:
					live.global_position = pp + Vector3(60.0, 0.3, 60.0)
			elif _frames == 55:
				# Fresh brute visual: neutral pose, no AI. Face the camera
				# (zombie front = local -Z; camera sits at +pf*Z).
				# 4m in front of the player = ~3m clear of the wall.
				var p2 := _bld("police")
				var pf2 := float(p2["face"])
				var pp2: Vector3 = _main.player.global_position
				var bv := ZombieVisual.new()
				_main.add_child(bv) # _ready builds the meshes
				(bv as ZombieVisual).set_brute()
				bv.global_position = Vector3(pp2.x, 0.0, pp2.z - pf2 * 4.0)
				bv.rotation.y = PI if pf2 > 0.0 else 0.0
			elif _frames == 70:
				_shot("bld2_brute")
				_phase = 2
				_frames = 0
		2:
			if _frames == 10:
				# Street view: player on the road in front of the police
				# station, 3/4 angle so the building fills the frame.
				var p3 := _bld("police")
				var pp3: Vector3 = p3["pos"]
				var pf3 := float(p3["face"])
				_place(pp3 + Vector3(5.0, 0.2, pf3 * 13.0), pp3 + Vector3(0, 2.0, 0))
			elif _frames == 70:
				_shot("bld2_street")
				print("BSHOT4 done")
				quit(0)
				return true
	return false
