extends SceneTree
## Diagnostic: capture morning shadows near a house with a nearby tree.
## Usage: xvfb-run -a godot --headless --path . --script res://tests/probe_shadow_shot.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb: Node
var _tm: Node
var _seeds: Array = [48392017, 12345678, 777001, 42424242]
var _shot_n := 0

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("SHADOWSHOT saved ", n)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_next_seed()
		return false
	_frames += 1
	if _phase == 0 and _frames == 50:
		_tm.call("set_time", 10.2)
		var spot := _find_house_with_tree()
		if spot == Vector3.INF:
			print("SHADOWSHOT no house+tree in seed")
			_next_seed()
			return false
		_main.player.global_position = spot
	elif _phase == 0 and _frames == 110:
		_shot("shadow_diag_%d.png" % _shot_n)
		_shot_n += 1
		_next_seed()
	return false

func _next_seed() -> void:
	if _shot_n >= 3:
		quit(0)
		return
	if _main != null:
		root.remove_child(_main)
		_main.queue_free()
		_main = null
	root.get_node("RunState").set("world_seed", _seeds[_shot_n])
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	current_scene = _main
	_nb = _main.get_node("Neighborhood")
	_tm = _main.get_node("TimeManager")
	_frames = 0
	_phase = 0

func _find_house_with_tree() -> Vector3:
	var houses: Array = _nb.get("houses")
	var meshes: Array = []
	_collect(_nb, meshes)
	var best := Vector3.INF
	var best_d := 7.0
	for h in houses:
		var hp: Vector3 = (h as Dictionary)["pos"]
		for mi in meshes:
			var m := mi as MeshInstance3D
			var mp: Vector3 = m.global_position
			if mp.y < 1.5 or mp.y > 6.0:
				continue # canopy-height meshes only
			var dd := Vector2(mp.x - hp.x, mp.z - hp.z).length()
			if dd < best_d and dd > 2.5:
				best_d = dd
				best = hp
	return best

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect(c, out)
