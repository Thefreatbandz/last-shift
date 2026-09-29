extends SceneTree
## World-polish visual QA screenshots (run under xvfb-run):
##   polish_street   - gritty street, daytime (grime, fences, boards, rust)
##   polish_house    - house exterior close-up (grime band, boarded windows)
##   polish_prompt_3m- interact prompt at ~3m (small, readable, never giant)
##   polish_swipe    - zombie mid-swipe, arms extended, body planted
##   polish_hurt     - player staggering backward when hit
##   polish_night    - night street scene (lamps, lit windows, zombie eyes)
## Usage: xvfb-run -a godot --path . --script res://tests/world_polish_shots.gd

const OUT := "/home/hatch/workspace/last-shift/qa_shots/world_polish"

var _booted := false
var _main: Node
var _cam: Camera3D
var _phase := 0
var _t0 := 0
var _player_pos := Vector3(14.0, 0.0, -7.0)


func _now() -> int:
	return int(Time.get_ticks_msec())


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("POLISHSHOT saved ", name)


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
	_main.get_node("TimeManager").set("time_hours", 10.0)
	print("POLISHSHOT booted")


func _player() -> Node:
	return _main.get_node("Player")


func _cam_at(pos: Vector3, focus: Vector3) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_cam.far = 220.0
		root.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _face(n: Node, target: Vector3) -> void:
	var to: Vector3 = target - (n.get("global_position") as Vector3)
	n.set("rotation", Vector3(0.0, atan2(-to.x, -to.z), 0.0))


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	match _phase:
		0:
			_t0 = _now()
			_phase = 1
		1:
			# Settle the world, then frame a gritty daytime street.
			if _now() - _t0 > 5000:
				var p := _player()
				p.set("global_position", _player_pos)
				p.set("velocity", Vector3.ZERO)
				var pp: Vector3 = p.get("global_position")
				_cam_at(pp + Vector3(6.0, 3.2, 8.0), pp + Vector3(-2.0, 1.2, -4.0))
				_t0 = _now()
				_phase = 2
		2:
			if _now() - _t0 > 800:
				_shot("polish_street")
				# House exterior close-up: grime band + boarded windows.
				var hood := _main.get_node("Neighborhood")
				var houses: Array = hood.get("houses")
				var h: Dictionary = houses[1]
				var hp: Vector3 = h["pos"]
				var hw: float = h["w"]
				_cam_at(hp + Vector3(hw * 0.5 + 4.5, 1.6, 5.5), hp + Vector3(0, 1.4, 0))
				_t0 = _now()
				_phase = 3
		3:
			if _now() - _t0 > 800:
				_shot("polish_house")
				# Interact prompt at ~3m: park the player by a loot container.
				var c: Node3D = _main.get_node("Loot").get_containers()[0]
				var p2 := _player()
				var to: Vector3 = (p2.get("global_position") as Vector3) - c.global_position
				to.y = 0.0
				p2.set("global_position", c.global_position + to.normalized() * 3.0)
				p2.set("global_position", Vector3((p2.get("global_position") as Vector3).x, 0.0, (p2.get("global_position") as Vector3).z))
				p2.set("velocity", Vector3.ZERO)
				_face(p2, c.global_position)
				_t0 = _now()
				_phase = 4
		4:
			# Wait for the prompt label to appear, then frame it at ~3m.
			var im := _main.get_node("Interact")
			var l: Label3D = im.get("_prompt_3d")
			if (l.visible or _now() - _t0 > 4000) and _now() - _t0 > 600:
				var lp: Vector3 = l.global_position
				var side := Vector3(-1.0, 0.35, 1.0).normalized()
				_cam_at(lp + side * 3.0, lp)
				_t0 = _now()
				_phase = 5
		5:
			if _now() - _t0 > 800:
				_shot("polish_prompt_3m")
				# Zombie mid-swipe: statue zombie, drive the lunge by hand.
				var p3 := _player()
				p3.set("global_position", _player_pos)
				p3.set("velocity", Vector3.ZERO)
				var zs: Array = _main.get_node("Zombies").living_zombies()
				var z: Node = zs[0]
				z.set_physics_process(false)
				z.set("global_position", _player_pos + Vector3(0, 0, -2.2))
				z.set("velocity", Vector3.ZERO)
				_face(p3, z.get("global_position"))
				_face(z, _player_pos)
				z.get_node("Visual").play_lunge()
				for _i in 12:
					z.get_node("Visual").tick(1.0 / 60.0, 0.0, false)
				var zp: Vector3 = z.get("global_position")
				_cam_at(zp + Vector3(3.0, 1.5, 0.8), zp + Vector3(0, 1.0, 0))
				_t0 = _now()
				_phase = 6
		6:
			if _now() - _t0 > 500:
				_shot("polish_swipe")
				# Player hurt: stagger-back check.
				var p4 := _player()
				_face(p4, Vector3(_player_pos.x, 0, _player_pos.z - 5.0))
				p4.get_node("Health").damage(12.0)
				var pp4: Vector3 = p4.get("global_position")
				_cam_at(pp4 + Vector3(2.6, 1.6, 2.2), pp4 + Vector3(0, 1.0, 0))
				_t0 = _now()
				_phase = 7
		7:
			if _now() - _t0 > 350:
				_shot("polish_hurt")
				# Night scene.
				_main.get_node("TimeManager").set("time_hours", 23.5)
				var p5 := _player()
				var pp5: Vector3 = p5.get("global_position")
				_cam_at(pp5 + Vector3(6.0, 3.4, 8.0), pp5 + Vector3(-2.0, 1.0, -4.0))
				_t0 = _now()
				_phase = 8
		8:
			if _now() - _t0 > 1500:
				_shot("polish_night")
				print("POLISHSHOT done")
				quit(0)
				return true
	return false
