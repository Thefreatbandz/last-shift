extends SceneTree
## Furnishing pass screenshots: furnished police + office interiors, and a
## detailed lootable corpse close-up.
## Usage: xvfb-run -a godot --path . --script res://tests/furnish_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/furn_*.png.
##
## NOTE: the hidden zones only flip visible when the PLAYER crosses the
## threshold, so each phase teleports the player in first (zone_shots.gd
## precedent), then parks + hides the player at a neutral spot so neither
## the body nor the search prompt photobombs the frame.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"
const LC := preload("res://scripts/loot/loot_container.gd")

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _iz: Node
var _cam: Camera3D


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("FSHOT saved ", name)


func _zone(kind: String) -> Dictionary:
	for z in _iz.get("zones"):
		var zd := z as Dictionary
		if String(zd["kind"]) == kind:
			return zd
	return {}


func _cam_at(pos: Vector3, focus: Vector3, fov := 55.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 500.0
		root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(focus)
	_cam.current = true


func _player() -> Node:
	return _main.get_node("Player")


func _park_player(zone: Dictionary, local: Vector3) -> void:
	var o: Vector3 = zone["origin"]
	_player().set("global_position", o + local + Vector3(0, 0.5, 0))
	_player().hide()


func _clear_zombies() -> void:
	# Zone brutes photobomb (or kill the parked player) mid-shot; the
	# wave director won't replace them during a daytime still.
	var zm := _main.get_node_or_null("Zombies")
	if zm != null:
		for z in zm.get("zombies") as Array:
			if is_instance_valid(z):
				(z as Node).queue_free()
	for c in _main.get_children():
		var sc: Script = (c as Node).get_script()
		if sc != null and str(sc.resource_path).ends_with("zombie_ai.gd"):
			(c as Node).queue_free()


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_iz = _main.get_node("Neighborhood").get("interior_zones")
		return false
	_frames += 1
	match _phase:
		0:
			# Furnished police: cell block + wanted board + desks.
			if _frames == 5:
				_player().set("global_position",
					(_zone("police")["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
			elif _frames == 30:
				_clear_zombies()
				var pz := _zone("police")
				var o: Vector3 = pz["origin"]
				var fd := float(pz["face"])
				_park_player(pz, Vector3(0, 0, -fd * 2.0))
				# Front-left, looking diagonally to the back-right: wanted
				# board on the back wall, evidence lockers right, desks mid.
				_cam_at(o + Vector3(-5.0, 2.6, fd * 8.0),
					o + Vector3(5.0, 1.2, -fd * 7.0), 58.0)
			elif _frames == 70:
				_shot("furn_police_int")
			elif _frames == 75:
				_phase = 1
				_frames = 0
		1:
			# Furnished office (small): lobby counter, cubicles, meeting table.
			if _frames == 5:
				_player().show()
				_player().set("global_position",
					(_zone("office_small")["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
			elif _frames == 30:
				_clear_zombies()
				var oz := _zone("office_small")
				var o: Vector3 = oz["origin"]
				var fd := float(oz["face"])
				_park_player(oz, Vector3(0, 0, fd * 2.0))
				_cam_at(o + Vector3(-3.0, 3.0, fd * 8.5),
					o + Vector3(2.5, 0.7, -fd * 4.0), 58.0)
			elif _frames == 70:
				_shot("furn_office_int")
			elif _frames == 75:
				_phase = 2
				_frames = 0
		2:
			# Detailed corpse close-up in the police lobby.
			if _frames == 5:
				_player().show()
				_player().set("global_position",
					(_zone("police")["spawn_in"] as Vector3) + Vector3(0, 0.5, 0))
			elif _frames == 30:
				_clear_zombies()
				var pz := _zone("police")
				var o: Vector3 = pz["origin"]
				var fd := float(pz["face"])
				# Corpse in the clear mid-lane; player parked well away.
				_park_player(pz, Vector3(-4.0, 0, fd * 4.0))
				var c: Node3D = LC.new()
				c.set("container_id", 1000)
				root.add_child(c)
				c.global_position = o + Vector3(1.5, 0.02, -fd * 3.0)
				c.call("build", [["bandage", 1]], "fresh_corpse")
				c.rotation.y = 0.4
				_cam_at(c.global_position + Vector3(2.0, 1.5, 2.4),
					c.global_position + Vector3(0, 0.2, 0), 50.0)
			elif _frames == 60:
				_shot("furn_corpse_close")
			elif _frames == 65:
				print("FSHOT done")
				quit()
				return true
	return false
