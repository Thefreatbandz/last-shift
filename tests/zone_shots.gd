extends SceneTree
## Zone screenshots: exterior-vs-interior scale contrast + compounds.
## Usage: xvfb-run -a godot --path . --script res://tests/zone_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/zone_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb: Node
var _iz: Node


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("ZSHOT saved ", name)


func _zone(kind: String) -> Dictionary:
	for z in _iz.get("zones"):
		var zd := z as Dictionary
		if String(zd["kind"]) == kind:
			return zd
	return {}


func _bld_for(zone: Dictionary) -> Dictionary:
	var bi := int(zone["building"])
	return (_nb.get("buildings") as Array)[bi] as Dictionary


func _ext_spot(bd: Dictionary) -> Vector3:
	var p: Vector3 = bd["pos"]
	var face := float(bd["face"])
	return p + Vector3(0, 1.0, face * (float(bd["d"]) * 0.5 + 7.0))


func _int_spot(zone: Dictionary) -> Vector3:
	# Center of the zone for a wide compound view (not the entrance).
	var o: Vector3 = zone["origin"]
	return o + Vector3(0, 0.5, 0)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_iz = _nb.get("interior_zones")
		return false
	_frames += 1
	match _phase:
		0:
			if _frames == 30:
				var pz := _zone("police")
				var bd := _bld_for(pz)
				_main.get_node("Player").set("global_position", _ext_spot(bd))
			elif _frames == 70:
				_shot("zone_police_ext")
				# Into the compound: teleport to the center (visibility follows).
				var pz := _zone("police")
				_main.get_node("Player").set("global_position", (pz["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
				_phase = 1
				_frames = 0
		1:
			if _frames == 60:
				_shot("zone_police_int")
				var hz := _zone("hospital")
				_main.get_node("Player").set("global_position", (hz["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
				_phase = 2
				_frames = 0
		2:
			if _frames == 30:
				var hz := _zone("hospital")
				var bd := _bld_for(hz)
				_main.get_node("Player").set("global_position", _ext_spot(bd))
			elif _frames == 70:
				_shot("zone_hospital_ext")
				var hz := _zone("hospital")
				_main.get_node("Player").set("global_position", (hz["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
				_phase = 3
				_frames = 0
		3:
			if _frames == 60:
				_shot("zone_hospital_int")
				# Office (seed 48392017 has office_small): exterior then zone.
				var oz := _zone("office_small")
				if oz.is_empty():
					oz = _zone("office_tall")
				var bd := _bld_for(oz)
				_main.get_node("Player").set("global_position", _ext_spot(bd))
				_phase = 4
				_frames = 0
		4:
			if _frames == 70:
				var oz := _zone("office_small")
				var oname := "office_small"
				if oz.is_empty():
					oz = _zone("office_tall")
					oname = "office_tall"
				_shot("zone_" + oname + "_ext")
				_main.get_node("Player").set("global_position", (oz["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
				_phase = 5
				_frames = 0
		5:
			if _frames == 60:
				var oz := _zone("office_small")
				var oname := "office_small"
				if oz.is_empty():
					oz = _zone("office_tall")
					oname = "office_tall"
				_shot("zone_" + oname + "_int")
				_phase = 6
				_frames = 0
		6:
			if _frames == 30:
				print("ZSHOT done")
				quit(0)
				return true
	return false
