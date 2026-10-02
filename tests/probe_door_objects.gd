extends SceneTree
## List every mesh within 6m of the safehouse door, sorted by size.
## Catches ANY large object (any mesh type) near the porch.

var _booted := false
var _seed := 48392017

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--doorseed="):
				_seed = int(a.trim_prefix("--doorseed="))
		root.get_node("RunState").set("world_seed", _seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		var m := ps.instantiate()
		root.add_child(m)
		current_scene = m
		_scan(m)
		return false
	return true

func _scan(m: Node) -> void:
	var nb: Node = m.get_node("Neighborhood")
	var sh: Node = m.get_node("Safehouse")
	var door_pos: Vector3 = sh.get("door_pos")
	var found: Array = []
	_walk(nb, door_pos, found)
	# Also check the safehouse node itself
	_walk(sh, door_pos, found)
	found.sort_custom(func(a, b): return a[0] > b[0])
	print("DOORSCAN seed=", _seed, " door=(", snappedf(door_pos.x, 0), ",", snappedf(door_pos.z, 0), ")")
	for f in found:
		if f[0] > 0.8: # only report things bigger than 0.8m
			print("DOORSCAN  size=", snappedf(f[0], 0.2), " dist=", snappedf(f[1], 0.1),
				" mesh=", f[2], " color=(", snappedf(f[3].r, 2), ",", snappedf(f[3].g, 2), ",", snappedf(f[3].b, 2), ")")

func _walk(n: Node, door_pos: Vector3, found: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var gp: Vector3 = mi.global_position
			var dd := Vector2(gp.x - door_pos.x, gp.z - door_pos.z).length()
			if dd < 6.0:
				var aabb := mi.get_aabb()
				var sz: float = aabb.size.length()
				# account for node scale
				sz *= mi.global_transform.basis.get_scale().x
				var mat := mi.get_active_material(0) as StandardMaterial3D
				var col := Color(0, 0, 0)
				if mat:
					col = mat.albedo_color
				found.append([sz, dd, mi.mesh.get_class() if mi.mesh else "?", col])
		elif c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm:
				for i in mm.instance_count:
					var xf := mm.get_instance_transform(i)
					var wp: Vector3 = mmi.global_transform * xf.origin
					var dd := Vector2(wp.x - door_pos.x, wp.z - door_pos.z).length()
					if dd < 6.0:
						var s: Vector3 = xf.basis.get_scale()
						found.append([s.x * 2.0, dd, "MultiMesh:" + mm.mesh.get_class(), Color(0.5, 0.5, 0.5)])
		_walk(c, door_pos, found)
