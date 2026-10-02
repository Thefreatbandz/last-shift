extends SceneTree
## Geometric hunt: find a seed where a tree canopy's shadow lands on a house porch.
## Sun at 10:13 -> light_dir ~(0.68,0.51,0.53); shadow offset for height h: (0.68,0.53)/0.51*h
## Usage: godot --headless --path . --script res://tests/probe_canopy_shadow.gd

var _booted := false
var _frames := 0
var _main: Node
var _nb: Node
var _seeds: Array = []
var _si := 0

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	for i in 40:
		_seeds.append(rng.randi_range(1, 99999999))

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_next()
		return false
	_frames += 1
	if _frames == 60:
		_scan()
		_next()
	return false

func _next() -> void:
	if _si >= _seeds.size():
		print("CANOPYSCAN complete, no strong candidate")
		quit(0)
		return
	if _main != null:
		root.remove_child(_main)
		_main.queue_free()
		_main = null
	root.get_node("RunState").set("world_seed", _seeds[_si])
	_si += 1
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	_nb = _main.get_node("Neighborhood")
	_frames = 0

func _scan() -> void:
	var seed: int = _seeds[_si - 1]
	var houses: Array = _nb.get("houses")
	var canopies: Array = []
	_collect_canopies(_nb, canopies)
	# shadow direction (horizontal) and factor at 10:13
	var sh := Vector2(0.68, 0.53) / 0.51
	for h in houses:
		var hd := h as Dictionary
		var hp: Vector3 = hd["pos"]
		var face := float(hd["face"])
		var d := float(hd["d"])
		var door := Vector2(hp.x, hp.z + face * d * 0.5)
		for c in canopies:
			var cp := c as Vector3 # x=world x, y=world z
			var land := Vector2(cp.x, cp.y) + sh * 3.4
			var dist := land.distance_to(door)
			if dist < 6.0:
				print("CANOPYSCAN seed=", seed, " door=(", snappedi(door.x, 1), ",", snappedi(door.y, 1),
					") canopy=(", snappedi(cp.x, 1), ",", snappedi(cp.y, 1), ") shadow_dist=", snappedf(dist, 0.1))
				return # one report per seed is enough

func _collect_canopies(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m := c as MeshInstance3D
			if m.mesh is SphereMesh:
				var sm := m.mesh as SphereMesh
				var gs: Vector3 = m.global_transform.basis.get_scale()
				var r: float = sm.radius * gs.x
				var gp: Vector3 = m.global_position
				if r > 0.8 and gp.y > 1.5 and gp.y < 6.0:
					out.append(Vector3(gp.x, gp.z, gp.y))
		_collect_canopies(c, out)
