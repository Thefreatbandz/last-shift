extends SceneTree
## Detail + animation + interior-loot screenshots.
##   xvfb-run -a godot --path . --script res://tests/detail_shots.gd
## Saves qa_shots/detail/*.png:
##   interior_loot, store_aisle, street_detail,
##   zombie_shamble, zombie_windup, zombie_strike, zombie_stagger, zombie_death

var _booted := false
var _frames := 0
var _main: Node
var _cam: Camera3D
var _zv: Node


func _shot(name: String) -> void:
	var out := "/home/hatch/workspace/last-shift/qa_shots/detail"
	DirAccess.make_dir_recursive_absolute(out)
	# Let the frame render before capture.
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("DETSHOT saved ", name)


func _cam_at(pos: Vector3, focus: Vector3, fov := 50.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 500.0
		root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _step_zv(n: int) -> void:
	for _i in n:
		_zv.tick(1.0 / 60.0, 0.0, false)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_main.get_node("TimeManager").set("time_hours", 10.5)
		return false
	_frames += 1
	match _frames:
		5:
			_interior_shot()
		7:
			_store_shot()
		9:
			_street_shot()
		11:
			_spawn_zombie()
			for _i in 40:
				_zv.tick(1.0 / 60.0, 1.2, true) # mid-shamble, not idle
			_cam_at(_zv.global_position + Vector3(0.5, 1.35, 4.2),
				_zv.global_position + Vector3(0, 1.0, 0))
			_shot("zombie_shamble")
		13:
			_zv.play_lunge()
			_step_zv(5) # t ~= 0.2: wind-up coil
			_cam_at(_zv.global_position + Vector3(2.4, 1.5, 2.4),
				_zv.global_position + Vector3(0, 1.1, 0))
			_shot("zombie_windup")
		15:
			_step_zv(8) # t ~= 0.58: strike snap (damage instant)
			_cam_at(_zv.global_position + Vector3(2.4, 1.5, 2.4),
				_zv.global_position + Vector3(0, 1.1, 0))
			_shot("zombie_strike")
		17:
			_step_zv(11) # finish the 0.38s envelope
			_zv.play_hit_reaction(Vector3(0, 0, 1))
			_step_zv(9) # mid-flinch
			_cam_at(_zv.global_position + Vector3(3.2, 2.0, 3.2),
				_zv.global_position + Vector3(0, 0.9, 0))
			_shot("zombie_stagger")
		19:
			_zv.play_death()
			for _i in 16:
				_zv.tick_dead(1.0 / 60.0) # t ~= 0.6: mid-crumple
			_cam_at(_zv.global_position + Vector3(3.2, 2.2, 3.2),
				_zv.global_position + Vector3(0, 0.5, 0))
			_shot("zombie_death")
		21:
			print("DETSHOT done")
			quit()
			return true
	return false


func _interior_shot() -> void:
	var nb := _main.get_node("Neighborhood")
	# First non-safehouse house: it has the bedroom duffel.
	var h: Dictionary = (nb.houses[0]) as Dictionary
	for hi in (nb.houses as Array).size():
		if hi != nb.safehouse_index:
			h = (nb.houses[hi]) as Dictionary
			break
	var hp := h["pos"] as Vector3
	var w := float(h["w"])
	var d := float(h["d"])
	var face := float(h["face"])
	# Front-right corner, looking across to the back-left: bed + bedroom
	# duffel, junk crate, stocked shelf, baseboards, ceiling light.
	_cam_at(hp + Vector3(w * 0.5 - 0.9, 1.75, face * (d * 0.5 - 0.9)),
		hp + Vector3(-w * 0.5 + 1.6, 0.55, -face * (d * 0.5 - 2.0)), 70.0)
	_shot("interior_loot")


func _store_shot() -> void:
	var groc := _main.get_node("Neighborhood/bld_grocery") as Node3D
	if groc == null:
		print("DETSHOT no grocery")
		return
	var gp: Vector3 = groc.global_position
	# From inside the aisle (x=2 gap between shelf rows), looking down it
	# toward the back-right where the new restock crate sits at (2.8, -3.2).
	_cam_at(gp + Vector3(2.0, 1.6, 3.5), gp + Vector3(2.6, 0.7, -3.2), 60.0)
	_shot("store_aisle")


func _street_shot() -> void:
	var nb := _main.get_node("Neighborhood")
	var ez: float = nb.get("road_ew_z")
	# Crosswalk bars at x=-14 + manholes/drains along the road.
	_cam_at(Vector3(-14.0, 5.5, ez + 9.0), Vector3(-14.0, 0.0, ez - 1.0), 55.0)
	_shot("street_detail")


func _spawn_zombie() -> void:
	var nb := _main.get_node("Neighborhood")
	# Clear game-spawned zombies so the animation subject is isolated
	# (a wandering pack zombie overlapping the subject reads as a
	# detached head in a still frame).
	var zm := _main.get_node("Zombies")
	for z in zm.get("zombies") as Array:
		(z as Node).queue_free()
	# Also clear building-interior zombies (grocery shot).
	for c in _main.get_children():
		if (c as Node).get_script() != null and str((c as Node).get_script().resource_path).ends_with("zombie_ai.gd"):
			(c as Node).queue_free()
	var spot: Vector3 = nb.player_start + Vector3(4.0, 0.0, 4.0)
	_zv = ZombieVisual.new()
	root.add_child(_zv)
	_zv.global_position = spot
	_zv.rotation.y = -0.6
	print("DETSHOT zombie at ", spot)
