extends SceneTree
## Apocalypse-phase screenshot staging:
##   1. apoc_night_fire.png — night street with barrel fires
##   2. apoc_blood_wall.png — blood on a building wall near a door (day)
##   3. apoc_dirt_road.png — dirt road (day)
##   4. apoc_lantern_interior.png — lantern-lit compound interior (night)
## Usage: xvfb-run -a godot --path . --script res://tests/apocalypse_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/apoc_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb: Node
var _tm: Node

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("APOCSHOT saved ", n)

func _dress() -> Node:
	var f: Array = _nb.find_children("*", "ApocalypseDressing", true, false)
	return f[0] if f.size() > 0 else null

func _fire_pos() -> Vector3:
	var d := _dress()
	if d == null:
		return Vector3.ZERO
	for e in d.get("_fires"):
		var l = (e as Dictionary).get("light")
		if l != null:
			return (l as Node3D).global_position
	return Vector3.ZERO

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_tm = _main.get_node("TimeManager")
		return false
	_frames += 1
	match _phase:
		0: # blood on wall near a building door, day
			if _frames == 40:
				_tm.call("set_time", 10.0)
				var b: Dictionary = (_nb.get("buildings") as Array)[0]
				var p: Vector3 = b["pos"]
				_main.player.global_position = p + Vector3(0, 0, float(b["d"]) * 0.5 + 4.0)
			elif _frames == 80:
				_shot("apoc_blood_wall.png")
				_phase = 1
				_frames = 0
		1: # dirt road, day
			if _frames == 20:
				var rects: Array = _nb.call("get_road_rects")
				var r: Rect2 = rects[2] # first dirt rect
				_main.player.global_position = Vector3(r.get_center().x, 0, r.get_center().y)
			elif _frames == 60:
				_shot("apoc_dirt_road.png")
				_phase = 2
				_frames = 0
		2: # night street with barrel fires
			if _frames == 20:
				_tm.call("set_time", 1.0)
				var fp := _fire_pos()
				_main.player.global_position = fp + Vector3(5.0, 0, 5.0)
			elif _frames == 70:
				_shot("apoc_night_fire.png")
				_phase = 3
				_frames = 0
		3: # lantern-lit interior, night
			if _frames == 20:
				var iz = _nb.get("interior_zones")
				var z: Dictionary = (iz.get("zones") as Array)[0]
				(z["root"] as Node3D).visible = true
				_main.player.global_position = (z["spawn_in"] as Vector3) + Vector3(2.0, 0, 2.0)
			elif _frames == 70:
				_shot("apoc_lantern_interior.png")
				print("APOCSHOT done")
				quit(0)
				return true
	return false
