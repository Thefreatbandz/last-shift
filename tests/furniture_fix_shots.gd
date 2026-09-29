extends SceneTree
## Furniture-fix visual proof (run under xvfb-run, NOT headless):
##   xvfb-run -a godot --path . --script res://tests/furniture_fix_shots.gd
## Boots the live game, claims the safehouse, puts the player INSIDE with the
## roof lifted, closes the door, and shoots the furnished interior:
##   proof_wide   - bed + bedroll + couch + workbench/stash + loot + closed door
##   proof_door   - the closed front door seen from inside
##   proof_porch  - porch/lawn view proving nothing spawns outside anymore
## (Camera moves and captures are on separate frames; _shot stays sync.)

const OUT := "/home/hatch/workspace/last-shift/qa_shots/furniture_fix"

var _booted := false
var _frames := 0
var _main: Node
var _cam: Camera3D
var _h := {}
var _hpos := Vector3.ZERO
var _d := 7.0
var _face := 1.0


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("FURNSHOT saved ", name)


func _boot() -> void:
	root.size = Vector2i(1280, 720) # landscape for the wide interior
	root.get_node("RunState").set("world_seed", 48392017)
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.get_node("TimeManager").set("time_hours", 10.0) # morning light
	var nb := _main.get_node("Neighborhood")
	_h = nb.houses[nb.safehouse_index]
	_hpos = _h["pos"]
	_d = float(_h["d"])
	_face = float(_h["face"])
	print("FURNSHOT booted safehouse d=", _d, " face=", _face)


func _hl(local: Vector3) -> Vector3:
	# House-local -> world (house roots are unrotated).
	return _hpos + local


func _cam_at(pos: Vector3, focus: Vector3, fov := 62.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 220.0
		root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	_frames += 1
	match _frames:
		10:
			# Claim: boards fall, door swings, interior trio pops in.
			_main.get_node("Safehouse").claim()
			# Player goes INSIDE (roof lifts + veil hides automatically),
			# back-left corner, out of the camera path.
			var p := _main.get_node("Player")
			p.global_position = _hl(Vector3(-1.6, 0.5, -_face * 2.3))
			p.velocity = Vector3.ZERO
		200:
			# Claim beats done: shut the door again for the closed-door shot.
			var doors := _main.get_node("HouseDoors")
			doors.set_door_open(doors.safehouse_door_index(), false, false)
		213:
			# Wide diagonal: back-right corner -> front-left. In frame: bed,
			# bedroll, couch, workbench + stash, loot, closed door.
			_cam_at(_hl(Vector3(2.9, 2.6, -_face * 2.9)),
				_hl(Vector3(-0.9, 0.2, _face * 1.3)))
		216:
			_shot("proof_wide")
		228:
			# Step out of prompt range (hides the 3D "SLEEP" label), then
			# shoot the closed front door seen from inside.
			var p2 := _main.get_node("Player")
			p2.global_position = _hl(Vector3(2.3, 0.5, -_face * 2.5))
			p2.velocity = Vector3.ZERO
			_cam_at(_hl(Vector3(0.1, 1.7, -_face * 1.6)),
				_hl(Vector3(0.0, 1.1, _face * (_d * 0.5))))
		231:
			_shot("proof_door")
		243:
			# Porch/lawn: nothing should be out here anymore (except the mark).
			_cam_at(_hl(Vector3(-3.4, 2.2, _face * (_d * 0.5 + 5.5))),
				_hl(Vector3(0.0, 0.8, _face * (_d * 0.5 + 1.0))))
		246:
			_shot("proof_porch")
		262:
			print("FURNSHOT done")
			quit(0)
			return true
	return false
