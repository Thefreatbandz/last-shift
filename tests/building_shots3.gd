extends SceneTree
## Re-shoot: office tower (pulled back to show the tower) + brute close-up
## (brute teleported into frame just before the shot).
##   xvfb-run -a godot --path . --script res://tests/building_shots3.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb
var _rig


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("BSHOT3 saved ", name)


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
		return false
	_main.player.get_node("Health").heal(1000.0)
	_frames += 1
	match _phase:
		0:
			if _frames == 10:
				var o := _bld("office_tall")
				var op: Vector3 = o["pos"]
				var of := float(o["face"])
				# Pulled back: tower (10m tall) must fit in frame.
				_place(op + Vector3(0, 0, of * 17.0), op + Vector3(0, 4.0, 0))
			elif _frames == 70:
				_shot("bld2_office_tall_ext")
				_phase = 1
				_frames = 0
		1:
			if _frames == 10:
				# Stand in the open near the police station; brute gets
				# teleported into frame just before the shot.
				var p := _bld("police")
				var pp: Vector3 = p["pos"]
				var pf := float(p["face"])
				_place(pp + Vector3(-6.0, 0.2, pf * 9.0), pp + Vector3(-6.0, 1.0, pf * 4.0))
			elif _frames == 55:
				# Drop the brute 2.5m in front of the player (between player
				# and the look target), facing the camera so its riot gear
				# and face read. Zombie front = local -Z.
				var bz := _brute_node()
				if bz != null:
					var p := _bld("police")
					var pf := float(p["face"])
					var pp2: Vector3 = _main.player.global_position
					bz.global_position = Vector3(pp2.x, 0.3, pp2.z - pf * 2.5)
					bz.rotation.y = PI if pf > 0.0 else 0.0
			elif _frames == 70:
				_shot("bld2_brute")
				print("BSHOT3 done")
				quit(0)
				return true
	return false
