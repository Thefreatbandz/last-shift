extends SceneTree
## World-density expansion QA: dirt roads, 4 extra commercial lots, props.
## - get_road_rects() returns 4 rects: 2 asphalt mains + 2 dirt roads (~4m).
## - Dirt roads have brown packed-earth ground meshes (meta "dirt_road").
## - 9 commercial buildings (5 anchors + 4 extras), deterministic per seed.
## - Every building has loot containers wired; grocery extras add zombies.
## - No building footprint overlaps any road rect (dirt included).
## - player_start is never inside a building footprint.
## - Rebuild determinism: same seed => same dirt rects + building layout.
## Run:
##   godot --headless --path . --script res://tests/expansion_v2_qa.gd
## Grep the output for SCRIPT ERROR separately.

var _ran := false
var _ok := true
# Lazy load: NeighborhoodBuilder touches the Sound autoload (via
# ChoppableTree); static class_name refs compile before autoloads register
# in bare --script mode. (prompt_qa.gd precedent.)
var _NB: GDScript

const SEEDS := [48392017, 777, 12345678]


func _check(name: String, cond: bool) -> void:
	print("EXP2QA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_NB = load("res://scripts/world/neighborhood_builder.gd")
	for seed in SEEDS:
		_check_seed(seed)
	_check_determinism()
	print("EXP2QA_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


func _check_seed(seed: int) -> void:
	var tag := "seed_%d" % seed
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	# --- Dirt roads in the road rects (minimap flow included).
	var roads: Array = nb.get_road_rects()
	_check("road_rects_4_" + tag, roads.size() == 4)
	var dirt: Array = nb.get("_dirt_rects")
	_check("dirt_rects_2_" + tag, dirt.size() == 2)
	var ns_dirt := 0
	var ew_dirt := 0
	for dr in dirt:
		var r := dr as Rect2
		if is_equal_approx(r.size.x, 4.0) and r.size.y > 10.0:
			ns_dirt += 1
		elif is_equal_approx(r.size.y, 4.0) and r.size.x > 10.0:
			ew_dirt += 1
		if absf(r.get_center().x) > 100.0 or absf(r.get_center().y) > 100.0:
			_check("dirt_in_bounds_" + tag, false)
	_check("dirt_ns_ew_" + tag, ns_dirt == 1 and ew_dirt == 1)
	# Dirt roads never touch the gas station rect.
	for dr in dirt:
		if (dr as Rect2).intersects(nb.get("_gas_rect")):
			_check("dirt_clear_of_gas_" + tag, false)
	# --- Dirt-colored ground meshes exist for the dirt roads.
	var dirt_meshes := 0
	var dirt_textured := 0
	for mi in _find_dirt_meshes(nb):
		dirt_meshes += 1
		var mat := (mi as MeshInstance3D).get("material_override") as Material
		if mat != null and mat.get("albedo_texture") != null:
			dirt_textured += 1
	_check("dirt_meshes_" + tag, dirt_meshes >= 6) # 2 strips + 4 ruts
	_check("dirt_noise_tex_" + tag, dirt_textured >= 2)
	# --- Buildings: 5 anchors + 4 expansion lots.
	_check("buildings_9_" + tag, nb.buildings.size() == 9)
	var kinds := {}
	for b in nb.buildings:
		var k := String((b as Dictionary)["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	_check("anchors_" + tag,
		kinds.get("police", 0) == 1 and kinds.get("hospital", 0) == 1 \
		and kinds.get("warehouse", 0) == 1)
	_check("expansion_kinds_" + tag,
		int(kinds.get("corner", 0)) + int(kinds.get("grocery", 0)) == 5)
	# --- Loot + zombie spawns wired for every building.
	var zones: Array = (nb.get("interior_zones") as Node).get("zones")
	for b in nb.buildings:
		var bd := b as Dictionary
		var kind := String(bd["kind"])
		var rect := _footprint(bd)
		var wired := false
		for ld in nb.building_loot:
			var lp := (ld as Dictionary)["pos"] as Vector3
			if rect.grow(1.0).has_point(Vector2(lp.x, lp.z)):
				wired = true
				break
			if _in_own_zone(lp, zones, nb.buildings.find(b)):
				wired = true
				break
		_check("loot_wired_%s_%s" % [kind, tag], wired)
		if kind == "grocery":
			var z_ok := false
			for zp in nb.building_zombie_spawns:
				var zv := zp as Vector3
				if rect.grow(1.0).has_point(Vector2(zv.x, zv.z)):
					z_ok = true
					break
			_check("grocery_zspawn_%s" % tag, z_ok)
	# --- No building overlaps any road rect (dirt included).
	for b in nb.buildings:
		var bd := b as Dictionary
		var brect := _footprint(bd)
		for r in roads:
			if (r as Rect2).grow(2.0).intersects(brect):
				_check("bld_off_road_%s_%s" % [String(bd["kind"]), tag], false)
	# --- player_start is never inside a building footprint.
	for b in nb.buildings:
		var bd := b as Dictionary
		if _footprint(bd).grow(1.0).has_point(
				Vector2(nb.player_start.x, nb.player_start.z)):
			_check("start_clear_of_bld_%s" % tag, false)
	nb.free()


func _check_determinism() -> void:
	var a: Node = _NB.new()
	root.add_child(a)
	a.build_world(48392017)
	var b: Node = _NB.new()
	root.add_child(b)
	b.build_world(48392017)
	_check("determinism_roads", a.get_road_rects() == b.get_road_rects())
	_check("determinism_dirt", a.get("_dirt_rects") == b.get("_dirt_rects"))
	var ka := _bld_sig(a)
	_check("determinism_blds", ka != "" and ka == _bld_sig(b))
	_check("hash_varies_by_seed",
		a.layout_hash() != _hash_for_seed(777))
	a.free()
	b.free()


func _bld_sig(nb: Node) -> String:
	var parts: Array[String] = []
	for bd in nb.buildings:
		var d := bd as Dictionary
		var p := d["pos"] as Vector3
		parts.append("%s:%.2f,%.2f" % [String(d["kind"]), p.x, p.z])
	return "|".join(parts)


func _hash_for_seed(seed: int) -> String:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var h: String = nb.layout_hash()
	nb.free()
	return h


func _find_dirt_meshes(nb: Node) -> Array:
	var out: Array = []
	var stack: Array = [nb]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		if n is MeshInstance3D and (n as MeshInstance3D).has_meta("dirt_road"):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _footprint(d: Dictionary) -> Rect2:
	var p := d["pos"] as Vector3
	var w := float(d["w"])
	var dd := float(d["d"])
	return Rect2(p.x - w * 0.5, p.z - dd * 0.5, w, dd)


func _in_own_zone(lp: Vector3, zones: Array, bi: int) -> bool:
	for z in zones:
		var zd := z as Dictionary
		if int(zd["building"]) == bi \
				and (zd["bounds"] as Rect2).grow(0.6).has_point(
					Vector2(lp.x, lp.z)):
			return true
	return false
