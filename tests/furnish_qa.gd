extends SceneTree
## Furnishing pass QA: tailored furniture in every compound zone.
## Builder phase (no scene): per-kind furniture counts, signature sets,
## spawn-area clearance, loot reachability, lantern light cap, corpse
## variant detail, determinism across rebuilds.
## Run:
##   godot --headless --path . --script res://tests/furnish_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEEDS := [48392017, 12345, 777]
const MIN_FURN := {"police": 14, "hospital": 16, "warehouse": 12,
	"office_tall": 12, "office_small": 10}
const SIG := {
	"police": ["evidence_locker", "wanted_board"],
	"hospital": ["iv_stand", "gurney"],
	"warehouse": ["workbench", "tire_stack"],
	"office_tall": ["conf_table", "water_cooler"],
	"office_small": ["water_cooler", "meeting_table"],
}
const FSET_META := "fset"

var _booted := false
var _ok := true
var _NB: GDScript
var _LC: GDScript # LootContainer (no Sound dependency; safe to load)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("FURNQ PASS ", label)
	else:
		_ok = false
		print("FURNQ FAIL ", label)


func _process(_delta: float) -> bool:
	if _booted:
		return true
	_booted = true
	_NB = load("res://scripts/world/neighborhood_builder.gd")
	_LC = load("res://scripts/loot/loot_container.gd")
	for seed in SEEDS:
		_builder_checks(seed)
	_corpse_checks()
	print("FURNQ_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


func _furn_nodes(zone: Dictionary) -> Array:
	var out: Array = []
	var stack: Array = [(zone["root"] as Node)]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta("furniture"):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _fsets(zone: Dictionary) -> Dictionary:
	var out := {}
	for n in _furn_nodes(zone):
		if (n as Node).has_meta(FSET_META):
			out[String((n as Node).get_meta(FSET_META))] = true
	return out


func _solids(zone: Dictionary) -> Array:
	# Furniture-tagged StaticBody3D centers (local to zone root).
	var out: Array = []
	for n in _furn_nodes(zone):
		if (n as Node) is StaticBody3D:
			out.append((n as Node3D).position)
	return out


func _builder_checks(seed: int) -> void:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var iz: Node = nb.get("interior_zones")
	_check("zones_exist_%d" % seed, iz != null)
	if iz == null:
		nb.free()
		return
	var zones: Array = iz.get("zones")
	_check("has_zones_%d" % seed, zones.size() >= 3)
	# Lantern real-light budget: cap 2 per zone.
	var lights: Array = iz.get("_lantern_lights")
	_check("lantern_cap_%d" % seed, lights.size() <= 2 * zones.size())
	var kinds := {}
	for z in zones:
		var zd := z as Dictionary
		var kind := String(zd["kind"])
		kinds[kind] = true
		var furn := _furn_nodes(zd)
		_check("furn_count_%s_%d" % [kind, seed],
			furn.size() >= int(MIN_FURN.get(kind, 10)))
		var fsets := _fsets(zd)
		for sig in (SIG.get(kind, []) as Array):
			_check("fset_%s_%s_%d" % [kind, String(sig), seed],
				fsets.has(String(sig)))
		# Spawn area clear: no solid furniture center within 1.5m of
		# spawn_in (anti-stuck; entry/exit triggers already QA'd live).
		var spawn: Vector3 = zd["spawn_in"]
		var origin: Vector3 = zd["origin"]
		var local_spawn := spawn - origin
		var blocked := false
		for sp in _solids(zd):
			var lp := sp as Vector3
			if Vector2(lp.x - local_spawn.x, lp.z - local_spawn.z).length() < 1.5:
				blocked = true
		_check("spawn_clear_%s_%d" % [kind, seed], not blocked)
		# Loot reachable: every zone loot pos >= 0.6m (XZ) from the
		# nearest solid furniture center.
		var loots: Array = []
		for li in (nb.get("building_loot") as Array):
			var lp := ((li as Dictionary)["pos"] as Vector3) - origin
			var b: Rect2 = zd["bounds"]
			if b.has_point(Vector2(lp.x + origin.x, lp.z + origin.z)):
				loots.append(lp)
		var reach := true
		for lpv in loots:
			var lp2 := lpv as Vector3
			for sp in _solids(zd):
				var lp3 := sp as Vector3
				if Vector2(lp2.x - lp3.x, lp2.z - lp3.z).length() < 0.6:
					reach = false
		_check("loot_reach_%s_%d" % [kind, seed], not loots.is_empty() and reach)
	# Every zoned kind got the "furnished" interior tag (hash determinism
	# still holds: tags are deterministic per seed).
	var parts: Array = nb.get("_interior_parts")
	var tags := {}
	for t in parts:
		tags[String(t)] = true
	for k in kinds.keys():
		_check("furn_tag_%s_%d" % [String(k), seed],
			tags.has("zone|%s|furnished" % String(k)))
	# Snapshot plain data BEFORE freeing (nodes die with the builder).
	var snap_counts: Array = []
	var snap_fsets: Array = []
	for z in zones:
		var zd := z as Dictionary
		snap_counts.append(_furn_nodes(zd).size())
		var fk: Array = _fsets(zd).keys()
		fk.sort()
		snap_fsets.append(fk)
	nb.free()
	# Determinism: rebuild, compare per-zone furniture counts + sig sets.
	var nb2: Node = _NB.new()
	root.add_child(nb2)
	nb2.build_world(seed)
	var iz2: Node = nb2.get("interior_zones")
	var z2: Array = iz2.get("zones")
	_check("rebuild_zone_count_%d" % seed, z2.size() == zones.size())
	if z2.size() == snap_counts.size():
		for i in z2.size():
			var zd2 := z2[i] as Dictionary
			_check("rebuild_furn_%d_%d" % [i, seed],
				_furn_nodes(zd2).size() == int(snap_counts[i]))
			var fk2: Array = _fsets(zd2).keys()
			fk2.sort()
			_check("rebuild_fset_%d_%d" % [i, seed], fk2 == snap_fsets[i])
	nb2.free()


func _corpse_checks() -> void:
	# Lootable corpses: clothing color varies by container_id, tears and
	# limb variation are deterministic, every 4th id gets a shoe, fresh
	# ones keep the blood pool.
	var mats := {}
	var shoes := 0
	var pools := 0
	for ci in 8:
		var c: Node3D = _LC.new()
		c.set("container_id", ci)
		var fresh := ci % 2 == 0
		c.call("build", [["scrap", 1]], "fresh_corpse" if fresh else "corpse")
		root.add_child(c)
		var torso_mat := ""
		for ch in c.get_children():
			if ch is MeshInstance3D:
				var mi := ch as MeshInstance3D
				# Torso is the 0.55x0.28x1.05 box at y~0.16.
				var bm := mi.mesh as BoxMesh
				if bm != null and absf(bm.size.x - 0.55) < 0.01 \
						and absf(mi.position.y - 0.16) < 0.01:
					torso_mat = String((mi.material_override as Material).resource_name) \
						if (mi.material_override as Material).resource_name != "" \
						else str(mi.material_override.get_instance_id())
		mats[torso_mat] = true
		# Shoe: small dark box near the feet (only some ids).
		var has_shoe := false
		for ch in c.get_children():
			if ch is MeshInstance3D:
				var mi := ch as MeshInstance3D
				var bm := mi.mesh as BoxMesh
				if bm != null and absf(bm.size.x - 0.14) < 0.01 \
						and absf(bm.size.z - 0.32) < 0.01:
					has_shoe = true
		if ci % 4 == 0:
			_check("corpse_shoe_%d" % ci, has_shoe)
			shoes += 1
		# Blood pool: cylinder mesh for fresh corpses.
		var has_pool := false
		for ch in c.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
				has_pool = true
		if fresh:
			_check("corpse_pool_%d" % ci, has_pool)
			pools += 1
		# Rebuild same id: identical child count (deterministic).
		var c2: Node3D = _LC.new()
		c2.set("container_id", ci)
		c2.call("build", [["scrap", 1]], "fresh_corpse" if fresh else "corpse")
		_check("corpse_stable_%d" % ci,
			c2.get_child_count() == c.get_child_count())
		c2.free()
		c.free()
	_check("corpse_cloth_varies", mats.size() >= 2)
	_check("corpse_shoes_some", shoes > 0)
	_check("corpse_pools_fresh", pools == 4)
