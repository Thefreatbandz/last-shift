extends SceneTree
## Combat-fix visual QA screenshots (run under xvfb-run):
##   fix1_kneel      - mid-search kneel at a chest (feet on floor, not through)
##   fix2_pickup     - pickup beat right after the search
##   fix3_windup     - bat swing wind-up (arms-driven check)
##   fix4_midsweep   - bat swing mid-sweep
##   fix5_followthru - bat swing follow-through
##   fix6_connect    - real bat->zombie connect (blood + zombie reels back)
##   fix7_hurt       - zombie hits player (player staggers back)
## Usage: xvfb-run -a godot --path . --script res://tests/combat_fix_shots.gd

const OUT := "/home/hatch/workspace/last-shift/qa_shots/combat_fix"

var _booted := false
var _main: Node
var _cam: Camera3D
var _phase := 0
var _t0 := 0
var _connect_shots := 0
var _hurt_shots := 0
var _player_pos := Vector3(14.0, 0.0, -7.0)


func _now() -> int:
	return int(Time.get_ticks_msec())


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("FIXSHOT saved ", name)


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
	print("FIXSHOT booted")


func _player() -> Node:
	return _main.get_node("Player")


func _visual() -> Node:
	return _player().get_node("Visual")


func _loot() -> Node:
	return _main.get_node("Loot")


func _zombie() -> Node:
	var zs: Array = _main.get_node("Zombies").living_zombies()
	return zs[0] if not zs.is_empty() else null


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
			# Settle, then start the chest search.
			_t0 = _now()
			_phase = 1
		1:
			if _now() - _t0 > 4000:
				var p := _player()
				var c: Node3D = _loot().get_containers()[0]
				var to: Vector3 = (p.get("global_position") as Vector3) - c.global_position
				to.y = 0.0
				p.set("global_position", c.global_position + to.normalized() * 1.4)
				p.set("global_position", Vector3((p.get("global_position") as Vector3).x, 0.0, (p.get("global_position") as Vector3).z))
				p.set("velocity", Vector3.ZERO)
				_face(p, c.global_position)
				_loot()._on_search(c)
				# Side-on camera: perpendicular to the player->chest axis.
				var pp: Vector3 = p.get("global_position")
				var axis: Vector3 = (c.global_position - pp).normalized()
				var side := Vector3(-axis.z, 0.0, axis.x)
				_cam_at(pp + side * 2.6 + Vector3(0, 1.3, 0), pp + Vector3(0, 0.7, 0))
				_t0 = _now()
				_phase = 2
		2:
			if _now() - _t0 > 900:
				_shot("fix1_kneel")
				_t0 = _now()
				_phase = 3
		3:
			# Wait for the search to finish; pickup starts automatically.
			if not bool(_loot().get("_searching")):
				_t0 = _now()
				_phase = 4
		4:
			if _now() - _t0 > 250:
				_shot("fix2_pickup")
				_stage_combat()
				_phase = 5
		5:
			# Deterministic swing poses, driven by hand.
			_pose(0.12)
			_t0 = _now()
			_phase = 6
		6:
			if _now() - _t0 > 400:
				_shot("fix3_windup")
				_pose(0.50)
				_t0 = _now()
				_phase = 7
		7:
			if _now() - _t0 > 400:
				_shot("fix4_midsweep")
				_pose(0.88)
				_t0 = _now()
				_phase = 8
		8:
			if _now() - _t0 > 400:
				_shot("fix5_followthru")
				# Real connect: zombie in range, live swing.
				var z := _zombie()
				z.set_physics_process(true)
				z.set("global_position", _player_pos + Vector3(0, 0, -1.6))
				z.set("velocity", Vector3.ZERO)
				_face(_player(), z.get("global_position"))
				_player().get_node("Combat").try_attack()
				_connect_shots = 0
				_t0 = _now()
				_phase = 9
		9:
			if _now() - _t0 > 120 and _connect_shots < 5:
				_shot("fix6_connect_%d" % _connect_shots)
				_connect_shots += 1
				_t0 = _now()
			elif _connect_shots >= 5:
				# Zombie hits the player: stagger-back check.
				var z2 := _zombie()
				_player().get_node("Health").damage(12.0)
				_hurt_shots = 0
				_t0 = _now()
				_phase = 10
		10:
			if _now() - _t0 > 120 and _hurt_shots < 4:
				_shot("fix7_hurt_%d" % _hurt_shots)
				_hurt_shots += 1
				_t0 = _now()
			elif _hurt_shots >= 4:
				print("FIXSHOT done")
				quit(0)
				return true
	return false


func _stage_combat() -> void:
	var p := _player()
	p.set("global_position", _player_pos)
	p.set("velocity", Vector3.ZERO)
	var z := _zombie()
	z.set_physics_process(false) # frozen statue for the posed shots
	z.set("global_position", _player_pos + Vector3(0, 0, -2.5))
	z.set("velocity", Vector3.ZERO)
	_face(p, z.get("global_position"))
	_face(z, _player_pos)
	var pp: Vector3 = p.get("global_position")
	_cam_at(pp + Vector3(2.8, 1.8, -1.2), pp + Vector3(0, 1.0, -1.2))


func _pose(t: float) -> void:
	var v := _visual()
	v.play_attack(10.0) # long envelope; we pin the exact moment
	v.set("_action_t", 10.0 * t)
	v.tick(0.0001, 0.0, false) # apply base pose + action at this t
