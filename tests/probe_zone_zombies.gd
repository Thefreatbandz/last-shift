extends SceneTree
## Verify: each compound zone kind has living zombies inside its bounds.
## Usage: godot --headless --path . --script res://tests/probe_zone_zombies.gd

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb: Node
var _iz: Node
var _zm: Node
var _player: Node
var _zi := 0

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 60 and _phase == 0:
		_nb = _main.get_node("Neighborhood")
		_iz = _nb.get("interior_zones")
		_zm = _main.get_node("Zombies")
		_player = _main.get_node("Player")
		if _iz == null:
			print("ZONEZ no interior_zones")
			quit(1)
			return true
		_phase = 1
		_frames = 0
		return false
	if _phase == 1 and _frames >= 30:
		var zones: Array = _iz.get("zones")
		if _zi >= zones.size():
			print("ZONEZ complete")
			quit(0)
			return true
		var z := zones[_zi] as Dictionary
		# Teleport player into the zone so it renders and triggers fire.
		(_player as Node3D).global_position = (z["origin"] as Vector3) + Vector3(0, 0.5, 0)
		_zi += 1
		_frames = 0
		_phase = 2
		return false
	if _phase == 2 and _frames >= 25:
		var zones: Array = _iz.get("zones")
		var z := zones[_zi - 1] as Dictionary
		var bounds: Rect2 = z["bounds"]
		var kind := String(z["kind"])
		var n := 0
		var brutes := 0
		for zb in _zm.call("living_zombies"):
			var zp: Vector3 = (zb as Node3D).global_position
			if bounds.has_point(Vector2(zp.x, zp.z)):
				n += 1
				if bool(zb.get("is_brute")):
					brutes += 1
		print("ZONEZ kind=", kind, " zombies_inside=", n, " brutes=", brutes,
			" visible=", (z["root"] as Node3D).visible)
		_phase = 1
		_frames = 0
	return false
