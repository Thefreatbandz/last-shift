extends SceneTree
## Hunt for large warm-gray spherical objects near house doors.
## Reports any SphereMesh with world radius > 1.2m and grayish (non-green)
## material within 6m of a house door, across seeds 1..20.

var _booted := false
var _seed := 1

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--huntseed="):
				_seed = int(a.trim_prefix("--huntseed="))
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
	var houses: Array = nb.get("houses")
	var doors: Array = []
	for h in houses:
		var hp: Vector3 = (h as Dictionary)["pos"]
		var face := float((h as Dictionary)["face"])
		var d := float((h as Dictionary)["d"])
		doors.append(hp + Vector3(0, 0, face * d * 0.5))
	var hits := 0
	_walk(nb, doors, hits)
	print("BLOBHUNT seed=", _seed, " done")

func _walk(n: Node, doors: Array, hits: int) -> int:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh is SphereMesh:
				var sm := mi.mesh as SphereMesh
				var wr: float = sm.radius * mi.global_transform.basis.get_scale().x
				if wr > 1.2:
					var mat := mi.get_active_material(0) as StandardMaterial3D
					var col := Color(0, 0, 0)
					if mat:
						col = mat.albedo_color
					# grayish, not green: r and b close to g, or r highest
					var grayish := (col.g < col.r + 0.08 and col.g < col.b + 0.12) or col.r > col.g
					if grayish:
						var gp: Vector3 = mi.global_position
						for dr in doors:
							var dd := Vector2(gp.x - dr.x, gp.z - dr.z).length()
							if dd < 6.0:
								hits += 1
								print("BLOBHUNT HIT seed=", _seed, " r=", snappedf(wr, 0.2),
									" color=(", snappedf(col.r,2), ",", snappedf(col.g,2), ",", snappedf(col.b,2), ")",
									" door_dist=", snappedf(dd, 0.1), " y=", snappedf(gp.y, 0.1))
								break
		hits = _walk(c, doors, hits)
	return hits
