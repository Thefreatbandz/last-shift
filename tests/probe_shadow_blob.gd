extends SceneTree
## Diagnostic: find oversized shadow casters near houses.
## Usage: xvfb-run -a godot --headless --path . --script res://tests/probe_shadow_blob.gd

var _booted := false
var _frames := 0
var _main: Node
var _hood: Node

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 90:
		_hood = _main.get_node("Neighborhood")
		_scan()
		quit(0)
		return true
	return false

func _scan() -> void:
	var houses: Array = _hood.get("houses")
	print("SHADOWPROBE houses=", houses.size())
	var mesh_roots: Array = []
	_collect_meshes(_hood, mesh_roots)
	print("SHADOWPROBE total MeshInstance3D=", mesh_roots.size())
	var n := 0
	for h in houses:
		var hd := h as Dictionary
		var hp: Vector3 = hd["pos"]
		var w := float(hd["w"])
		var d := float(hd["d"])
		for mi in mesh_roots:
			var m := mi as MeshInstance3D
			var gp: Vector3 = m.global_position
			var dx := absf(gp.x - hp.x)
			var dz := absf(gp.z - hp.z)
			# Near the house but outside its footprint (+1m margin).
			if dx > w * 0.5 + 1.0 or dz > d * 0.5 + 1.0:
				continue
			if dx < w * 0.5 - 0.5 and dz < d * 0.5 - 0.5:
				continue # deep inside the house footprint; part of the house
			var aabb: AABB = m.get_aabb()
			var gs: Vector3 = m.global_transform.basis.get_scale()
			var sz: Vector3 = Vector3(aabb.size.x * gs.x, aabb.size.y * gs.y, aabb.size.z * gs.z)
			var mx := maxf(sz.x, maxf(sz.y, sz.z))
			if mx > 2.0:
				var mn: String = m.name
				var mesh := m.mesh
				print("SHADOWPROBE big-near-house aabb=", snappedi(sz.x * 10, 1) / 10.0, ",", snappedi(sz.y * 10, 1) / 10.0, ",", snappedi(sz.z * 10, 1) / 10.0,
					" pos=", gp, " name=", mn, " mesh=", mesh)
				n += 1
	print("SHADOWPROBE done, flagged=", n)

func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)
