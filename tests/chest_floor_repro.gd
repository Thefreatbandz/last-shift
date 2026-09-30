extends SceneTree
## Repro for: "opening a chest sends the player through the floor".
## Boots a live run, teleports the player next to a loot container, triggers
## the search flow, and tracks BOTH the physics body Y and the visual body Y
## across SEARCH_TIME + pickup. Run:
##   godot --headless --path . --script res://tests/chest_floor_repro.gd

var _booted := false
var _frames := 0
var _main: Node
var _phase := 0
var _start_y := 0.0
var _min_py := 999.0
var _max_py := -999.0
var _min_vy := 999.0
var _max_vy := -999.0


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
	if _frames == 120 and _phase == 0:
		_phase = 1
		var player = _main.get_node("Player")
		var loot = _main.get_node("Loot")
		var c = (loot.get_containers()[0] as Node3D)
		# Stand next to the chest, not inside it.
		var to: Vector3 = (player.global_position - c.global_position)
		to.y = 0.0
		player.global_position = c.global_position + to.normalized() * 1.4
		player.global_position.y = 0.0
		player.velocity = Vector3.ZERO
		_start_y = player.global_position.y
		loot._on_search(c)
		print("REPRO search started; start_y=", _start_y)
		return false
	if _phase == 1:
		var player = _main.get_node("Player")
		var vis = player.get_node("Visual")
		var body = vis.get("_body")
		_min_py = minf(_min_py, player.global_position.y)
		_max_py = maxf(_max_py, player.global_position.y)
		_min_vy = minf(_min_vy, (body as Node3D).position.y)
		_max_vy = maxf(_max_vy, (body as Node3D).position.y)
		if _frames == 120 + 240: # ~4s at 60fps physics: search 1.5s + pickup 0.6s + margin
			print("REPRO physics_y: start=", _start_y, " min=", _min_py, " max=", _max_py)
			print("REPRO visual_body_y: min=", _min_vy, " max=", _max_vy)
			print("REPRO searching=", _main.get_node("Loot").get("_searching"))
			quit(0)
			return true
	return false
