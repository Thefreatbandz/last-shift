extends SceneTree
## Diagnostic: list everything within 6m of each house door, across seeds.
## Usage: godot --headless --path . --script res://tests/probe_door_scan.gd

var _booted := false
var _frames := 0
var _main: Node
var _nb: Node
var _seeds: Array = [48392017, 12345678, 777001, 42424242, 999888777]
var _si := 0

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
		print("DOORSCAN complete")
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
	var nodes: Array = []
	_collect(_nb, nodes)
	print("DOORSCAN seed=", seed, " houses=", houses.size())
	for h in houses:
		var hd := h as Dictionary
		var hp: Vector3 = hd["pos"]
		var face := float(hd["face"])
		var w := float(hd["w"])
		var d := float(hd["d"])
		# door approx at front face center
		var door := hp + Vector3(0, 0, face * d * 0.5)
		for n in nodes:
			var n3 := n as Node3D
			var gp: Vector3 = n3.global_position
			var dist := Vector2(gp.x - door.x, gp.z - door.z).length()
			if dist > 6.0 or dist < 0.5:
				continue
			var desc := _describe(n3)
			if desc != "":
				print("DOORSCAN seed=", seed, " door=", _v2(door), " dist=", snappedf(dist, 0.1), " ", desc)

func _v2(v: Vector3) -> String:
	return "(%s,%s)" % [snappedi(v.x, 1), snappedi(v.z, 1)]

func _describe(n: Node3D) -> String:
	var parts: Array = []
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		var a := m.get_aabb()
		var gs: Vector3 = m.global_transform.basis.get_scale()
		var sx: float = a.size.x * gs.x
		var sy: float = a.size.y * gs.y
		var sz: float = a.size.z * gs.z
		var mx := maxf(sx, maxf(sy, sz))
		if mx < 1.2:
			return ""
		parts.append("MI %sx%sx%s" % [snappedf(sx, 0.1), snappedf(sy, 0.1), snappedf(sz, 0.1)])
		parts.append("y=%s" % snappedf(n.global_position.y, 0.1))
		parts.append("mat=%s" % _matname(m))
	elif n is GPUParticles3D:
		parts.append("PARTICLES amount=%d" % (n as GPUParticles3D).amount)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		parts.append("MULTIMESH instances=%d" % (mm.instance_count if mm else -1))
	else:
		return ""
	parts.append("node=" + n.name)
	return " ".join(parts)

func _matname(m: MeshInstance3D) -> String:
	var mat := m.get_active_material(0)
	if mat == null:
		mat = m.material_override
	if mat is StandardMaterial3D:
		var c: Color = (mat as StandardMaterial3D).albedo_color
		return "(%s,%s,%s)" % [snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1)]
	return "?"

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			out.append(c)
		_collect(c, out)
