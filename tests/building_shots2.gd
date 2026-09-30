extends SceneTree
## Re-shoot staging for building-types phase with god-mode player and
## explicit camera yaw. Run:
##   xvfb-run -a godot --path . --script res://tests/building_shots2.gd
## Writes to ~/workspace/last-shift/polish_shots/bld2_*.png.

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
	print("BSHOT2 saved ", name)


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
	# Rig local +Z must point opposite the view direction (camera sits behind).
	var yaw := atan2(-d.x, -d.z)
	_rig.set_yaw_immediate(yaw)
	_rig.snap()
	# God mode: full heal now and every frame in _process.
	_main.player.get_node("Health").heal(1000.0)


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
	# God mode every frame.
	_main.player.get_node("Health").heal(1000.0)
	_frames += 1
	var police := _bld("police")
	var pp: Vector3 = police["pos"]
	var pface := float(police["face"])
	var pd := float(police["d"])
	match _phase:
		0:
			if _frames == 10:
				# Police exterior: stand on the door side, look at the facade.
				_place(pp + Vector3(0, 0, pface * (pd * 0.5 + 7.0)), pp)
			elif _frames == 60:
				_shot("bld2_police_ext")
				_phase = 1
				_frames = 0
		1:
			if _frames == 10:
				# Police interior: stand mid-room, look at the cell block.
				_place(pp + Vector3(2.0, 0.2, pface * 1.0), pp + Vector3(-4.0, 0, -pface * 3.0))
				var doors = _main.get_node("HouseDoors")
				_main.get_node("Inventory").add("police_key", 1)
				doors.try_unlock_building(_police_j())
			elif _frames == 60:
				_shot("bld2_police_int")
				_phase = 2
				_frames = 0
		2:
			if _frames == 10:
				# Grocery aisles: stand at the door end, look down the shelves.
				var g := _bld("grocery")
				var gp: Vector3 = g["pos"]
				var gf := float(g["face"])
				_place(gp + Vector3(0, 0.2, gf * 3.4), gp + Vector3(0, 0, -gf * 3.0))
			elif _frames == 60:
				_shot("bld2_grocery_aisles")
				_phase = 3
				_frames = 0
		3:
			if _frames == 10:
				# Office tower exterior.
				var o := _bld("office_tall")
				var op: Vector3 = o["pos"]
				var of := float(o["face"])
				var od := float(o["d"])
				_place(op + Vector3(0, 0, of * (od * 0.5 + 9.0)), op + Vector3(0, 2.0, 0))
			elif _frames == 60:
				_shot("bld2_office_tall_ext")
				_phase = 4
				_frames = 0
		4:
			if _frames == 10:
				# Brute close-up: park 3m from the first brute, look at it.
				var bz: Vector3 = (_nb.brute_spawns as Array)[0]
				var to_p: Vector3 = (pp - bz)
				to_p.y = 0.0
				to_p = to_p.normalized()
				_place(bz + to_p * 3.0 + Vector3(0, 0.2, 0), bz + Vector3(0, 1.0, 0))
			elif _frames == 60:
				_shot("bld2_brute")
				_phase = 5
				_frames = 0
		5:
			if _frames == 10:
				# Street view: on the road near the police station, building in frame.
				_place(pp + Vector3(-14.0, 0, pface * 9.0), pp)
			elif _frames == 60:
				_shot("bld2_street")
				_main.get("_minimap_view").set_expanded(true)
				_phase = 6
				_frames = 0
		6:
			if _frames == 40:
				_shot("bld2_minimap_expanded")
				print("BSHOT2 done")
				quit(0)
				return true
	return false


func _police_j() -> int:
	for j in _nb.buildings.size():
		if String((_nb.buildings[j] as Dictionary)["kind"]) == "police":
			return j
	return -1
