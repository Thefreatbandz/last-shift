extends SceneTree
## Regression: opening a chest must not send the player through the floor.
## Boots a live run, teleports the player next to a loot container, triggers
## the search flow, and tracks the physics body Y and the visual body Y
## across SEARCH_TIME + pickup.
##   godot --headless --path . --script res://tests/chest_search_qa.gd

var _booted := false
var _frames := 0
var _main: Node
var _ok := true
var _phase := 0
var _start_y := 0.0
var _min_py := 999.0
var _max_py := -999.0
var _min_vy := 999.0


func _check(name: String, cond: bool) -> void:
	print("CHESTQA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


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
		var c: Node3D = loot.get_containers()[0]
		var to: Vector3 = player.global_position - c.global_position
		to.y = 0.0
		player.global_position = c.global_position + to.normalized() * 1.4
		player.global_position.y = 0.0
		player.velocity = Vector3.ZERO
		_start_y = player.global_position.y
		loot._on_search(c)
		return false
	if _phase == 1:
		var player = _main.get_node("Player")
		var body: Node3D = player.get_node("Visual").get("_body")
		_min_py = minf(_min_py, player.global_position.y)
		_max_py = maxf(_max_py, player.global_position.y)
		_min_vy = minf(_min_vy, body.position.y)
		if _frames == 120 + 240:
			# Physics body: must stay on the floor (no sinking).
			_check("physics_y_stable", _min_py > _start_y - 0.15
					and _max_py < _start_y + 0.05)
			# Visual: kneel drop is bounded (~0.26); never near floor-clip.
			_check("visual_drop_bounded", _min_vy > -0.30)
			_check("search_completed", not bool(_main.get_node("Loot").get("_searching")))
			print("CHESTQA_RESULT ok=", _ok,
				" min_py=", _min_py, " min_vy=", _min_vy)
			quit(0 if _ok else 1)
			return true
	return false
