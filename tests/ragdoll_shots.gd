extends SceneTree
## Xvfb screenshot staging for procedural ragdoll deaths:
##   1. ragdoll_bat_air.png — bat kill mid-tumble (body sprawling)
##   2. ragdoll_bat_down.png — same corpse settled/frozen on the ground
##   3. ragdoll_shotgun.png — shotgun kill mid-launch (body flying hard)
## Usage: xvfb-run -a godot --path . --script res://tests/ragdoll_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/ragdoll_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _player: Node
var _phase := 0
var _t0 := 0
var _z1: Node = null
var _z2: Node = null


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("RSHOT saved ", name)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var now := Time.get_ticks_msec()
	if _phase == 0 and _frames == 60:
		_player = _main.get_node("Player")
		var zs := _alive()
		if zs.size() >= 2:
			_z1 = zs[0]
			_place(_z1)
			_phase = 1
	elif _phase == 1 and _frames == 75:
		# Bat-strength killing blow from the south; body sprawls north.
		_kill(_z1, 1.0)
		_t0 = now
		_phase = 2
	elif _phase == 2 and now - _t0 >= 350:
		_shot("ragdoll_bat_air")
		_phase = 3
	elif _phase == 3 and now - _t0 >= 2900:
		_shot("ragdoll_bat_down")
		var zs := _alive()
		if not zs.is_empty():
			_z2 = zs[0]
			_place(_z2)
		_phase = 4
	elif _phase == 4 and now - _t0 >= 3400:
		# Shotgun-strength blow: the body launches.
		_kill(_z2, 2.8)
		_t0 = now
		_phase = 5
	elif _phase == 5 and now - _t0 >= 280:
		_shot("ragdoll_shotgun")
		_phase = 6
	elif _phase == 6 and now - _t0 >= 1200:
		print("RSHOT done")
		quit(0)
		return true
	return false


func _alive() -> Array:
	var out: Array = []
	for z in _main.get_node("Zombies").get("zombies"):
		if not bool(z.call("is_dead")):
			out.append(z)
	return out


func _place(z: Node) -> void:
	# 3m in front of the player, where the follow camera can see it.
	var pp: Vector3 = _player.global_position
	(z as Node3D).global_position = pp + Vector3(1.8, 0.3, -2.4)
	z.set("velocity", Vector3.ZERO)


func _kill(z: Node, launch: float) -> void:
	if z == null:
		return
	var zp: Vector3 = (z as Node3D).global_position
	z.call("take_damage", 99999.0, zp + Vector3(0, 0, -1.0), launch)
