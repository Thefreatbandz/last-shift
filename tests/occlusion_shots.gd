extends SceneTree
## Exterior occlusion sweep: park the player outside each building type,
## open its door, rotate the camera through 4 yaws, capture screenshots.
##   godot --headless --path . --script res://tests/occlusion_shots.gd
## Screenshots land in /tmp/occl/ (viewed via Xvfb run below).

var _booted := false
var _frames := 0
var _phase := 0
var _ok := true
var _main: Node
var _shots: Array = []
var _shot_i := 0


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
	if _phase == 0 and _frames == 90:
		_collect_shots()
		_phase = 1
		_frames = 0
		return false
	if _phase == 1:
		if _shot_i >= _shots.size():
			print("OCCL done shots=", _shots.size())
			quit(0)
			return true
		# 8 frames per shot: 4 to move/settle, 4 spare.
		if _frames % 8 == 0:
			var s: Dictionary = _shots[_shot_i]
			_pose(s)
		elif _frames % 8 == 6:
			var s2: Dictionary = _shots[_shot_i]
			_capture(s2)
			_shot_i += 1
	return false


func _collect_shots() -> void:
	var hood = _main.neighborhood
	var spots: Array = []
	# Houses: first two.
	for i in mini(2, hood.houses.size()):
		var h: Dictionary = hood.houses[i]
		spots.append({"kind": "house", "pos": h["pos"], "w": h["w"], "d": h["d"], "face": h["face"], "hi": i, "bi": -1})
	# Commercial buildings: one of each kind.
	var seen := {}
	for j in hood.buildings.size():
		var bd: Dictionary = hood.buildings[j]
		if not seen.has(bd["kind"]):
			seen[bd["kind"]] = true
			spots.append({"kind": bd["kind"], "pos": bd["pos"], "w": bd["w"], "d": bd["d"], "face": bd["face"], "hi": -1, "bi": j})
	print("OCCL spots=", spots.size())
	for sp in spots:
		var pos: Vector3 = sp["pos"]
		var w: float = sp["w"]
		var d: float = sp["d"]
		# Orbit: player at 4 compass points 8m outside the walls, camera
		# aimed at the building center each time. Covers every exterior angle.
		var dirs := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
		var dnames := ["S", "E", "N", "W"]
		for k in dirs.size():
			var dir: Vector3 = dirs[k]
			var ppos := pos + dir * (maxf(w, d) * 0.5 + 8.0)
			# Camera forward is -Z rotated by yaw: want it to point along (pos - ppos).
			var to: Vector3 = (pos - ppos).normalized()
			var yaw := atan2(-to.x, -to.z)
			_shots.append({
				"ppos": ppos,
				"yaw": yaw,
				"name": "occl_%s_%s" % [sp["kind"], dnames[k]],
				"door": sp,
			})

func _pose(s: Dictionary) -> void:
	var player = _main.player
	player.global_position = s["ppos"]
	player.velocity = Vector3.ZERO
	_main.camera_rig.set_yaw_immediate(s["yaw"])
	_main.camera_rig.snap()
	# Open the building's door so we capture the worst case.
	_open_door()


func _open_door() -> void:
	var sp: Dictionary = _shots[_shot_i]["door"]
	var doors = _main.get_node_or_null("HouseDoors")
	if doors == null:
		return
	if int(sp["hi"]) >= 0:
		doors.set_door_open(int(sp["hi"]), true, false)
	elif int(sp["bi"]) >= 0:
		doors.set_building_door_open(int(sp["bi"]), true, false)


func _capture(s: Dictionary) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("/tmp/occl/%s.png" % s["name"])
	print("OCCL shot ", s["name"])
