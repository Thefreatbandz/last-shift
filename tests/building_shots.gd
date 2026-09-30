extends SceneTree
## Xvfb screenshot staging for the building-types phase:
##   1. police exterior (POLICE sign, barred windows)
##   2. police interior (cells, armory, brute)
##   3. hospital interior (wards, medicine cabinets)
##   4. grocery aisles (stocked shelves)
##   5. fourth building exterior (rotating kind)
##   6. brute close-up
##   7. expanded minimap (building colors/labels/legend)
## Usage: xvfb-run -a godot --path . --script res://tests/building_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/bld_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb
var _kinds := {}


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("BSHOT saved ", name)


func _bld(kind: String) -> Dictionary:
	for b in _nb.buildings:
		var bd := b as Dictionary
		if String(bd["kind"]) == kind:
			return bd
	return {}


func _front_spot(bd: Dictionary, dist: float) -> Vector3:
	var p: Vector3 = bd["pos"]
	var face := float(bd["face"])
	return p + Vector3(0, 0, face * (float(bd["d"]) * 0.5 + dist))


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		return false
	_frames += 1
	match _phase:
		0:
			# Police exterior: stand on the door side, camera sees the facade.
			if _frames == 30:
				_main.player.global_position = _front_spot(_bld("police"), 5.0)
			elif _frames == 70:
				_shot("bld_police_ext")
				# Unlock + step inside for the interior.
				var doors = _main.get_node("HouseDoors")
				var pj := _police_j()
				_main.get_node("Inventory").add("police_key", 1)
				doors.try_unlock_building(pj)
				var pp: Vector3 = (_bld("police"))["pos"]
				_main.player.global_position = pp + Vector3(0, 0.2, 0)
				_phase = 1
				_frames = 0
		1:
			if _frames == 45:
				_shot("bld_police_int")
				var hp: Vector3 = (_bld("hospital"))["pos"]
				_main.player.global_position = hp + Vector3(0, 0.2, 0)
				_phase = 2
				_frames = 0
		2:
			if _frames == 45:
				_shot("bld_hospital_int")
				var gp: Vector3 = (_bld("grocery"))["pos"]
				_main.player.global_position = gp + Vector3(0, 0.2, 2.0)
				_phase = 3
				_frames = 0
		3:
			if _frames == 45:
				_shot("bld_grocery_aisles")
				# Fourth building exterior (rotating kind).
				var fourth := _fourth()
				_main.player.global_position = _front_spot(fourth, 6.0)
				_phase = 4
				_frames = 0
		4:
			if _frames == 45:
				var fourth := _fourth()
				_shot("bld_" + String(fourth["kind"]) + "_ext")
				# Brute close-up: park next to the first brute.
				var bz: Vector3 = _nb.brute_spawns[0]
				_main.player.global_position = bz + Vector3(2.2, 0, 1.2)
				_phase = 5
				_frames = 0
		5:
			if _frames == 40:
				_shot("bld_brute")
				_main.get("_minimap_view").set_expanded(true)
				_phase = 6
				_frames = 0
		6:
			if _frames == 30:
				_shot("bld_minimap_expanded")
				print("BSHOT done")
				quit(0)
				return true
	return false


func _police_j() -> int:
	for j in _nb.buildings.size():
		if String((_nb.buildings[j] as Dictionary)["kind"]) == "police":
			return j
	return -1


func _fourth() -> Dictionary:
	for b in _nb.buildings:
		var bd := b as Dictionary
		if not String(bd["kind"]) in ["police", "hospital", "grocery"]:
			return bd
	return (_nb.buildings[0] as Dictionary)
