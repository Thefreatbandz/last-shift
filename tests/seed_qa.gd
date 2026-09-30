extends SceneTree
## Headless QA for seeded neighborhoods: determinism, layout invariants,
## rebuild stability (no leaks). Run:
##   godot --headless --path . --script res://tests/seed_qa.gd
## (tests/ is not exported; it lives only in the repo.)

var _ran := false
# Lazy load: NeighborhoodBuilder touches the Sound autoload (via
# ChoppableTree); static class_name refs compile before autoloads register
# in bare --script mode. (prompt_qa.gd precedent.)
var _NB: GDScript


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_NB = load("res://scripts/world/neighborhood_builder.gd")
	var ok := true
	# 1. Determinism: same seed => identical layout hash.
	var h1 := _hash_for(48392017)
	var h2 := _hash_for(48392017)
	ok = _check("determinism", h1 != "" and h1 == h2, ok)
	# 2. Distinct seeds => distinct neighborhoods.
	ok = _check("distinct_seeds", _hash_for(777) != h1, ok)
	# 2b. Interior variation is seeded too: same seed => same interior hash,
	# different seeds => (almost surely) different interior hashes.
	var ih1 := _interior_hash_for(48392017)
	ok = _check("interior_determinism",
		ih1 != "" and ih1 == _interior_hash_for(48392017), ok)
	ok = _check("interior_varies", ih1 != _interior_hash_for(777), ok)
	# 3. Layout invariants on several seeds.
	for seed in [48392017, 777, 12345678, 42, 99999999]:
		ok = _check_invariants(seed, ok)
	# 4. Rebuild same seed twice on one instance: identical node count.
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(555)
	var c1: int = nb.get_child_count()
	nb.build_world(555)
	var c2: int = nb.get_child_count()
	ok = _check("rebuild_stable", c1 > 100 and c1 == c2, ok)
	nb.free()
	print("SEEDQA_RESULT ok=", ok)
	quit(0 if ok else 1)
	return true


func _hash_for(seed: int) -> String:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var h: String = nb.layout_hash()
	nb.free()
	return h


func _interior_hash_for(seed: int) -> String:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var h: String = nb.interior_hash()
	nb.free()
	return h


func _zone_origins_for(seed: int, _tag: String) -> Array:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var out: Array = []
	for z in (nb.get("interior_zones") as Node).get("zones"):
		out.append((z as Dictionary)["origin"])
	nb.free()
	return out


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("SEEDQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond


func _check_invariants(seed: int, ok: bool) -> bool:
	var tag := "seed_%d" % seed
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var n: int = nb.houses.size()
	ok = _check("houses_12_14_" + tag, n >= 12 and n <= 14, ok)
	ok = _check("safehouse_idx_" + tag,
		nb.safehouse_index >= 0 and nb.safehouse_index < n, ok)
	ok = _check("zspawns_" + tag, nb.zombie_spawns.size() == 10, ok)
	for s in nb.zombie_spawns:
		if nb._point_in_lots(s, 0.5) or nb._on_road(s):
			ok = _check("zspawn_clear_" + tag, false, ok)
		if s.distance_to(nb.player_start) < 15.0:
			ok = _check("zspawn_far_from_start_" + tag, false, ok)
		if s.distance_to(nb.safehouse_porch) < 9.0:
			ok = _check("zspawn_far_from_porch_" + tag, false, ok)
	# Player start == safehouse porch, on open walkable ground.
	ok = _check("start_at_porch_" + tag,
		nb.player_start.distance_to(nb.safehouse_porch) < 1.0, ok)
	ok = _check("porch_off_road_" + tag, not nb._on_road(nb.safehouse_porch, 0.5), ok)
	for i in nb._lot_rects.size():
		if i == nb.safehouse_index:
			continue
		if (nb._lot_rects[i] as Rect2).grow(1.0).has_point(
				Vector2(nb.safehouse_porch.x, nb.safehouse_porch.z)):
			ok = _check("porch_clear_of_others_" + tag, false, ok)
	# Every house: valid door pivot + roof, door clear of roads.
	for h in nb.houses:
		var hd := h as Dictionary
		var door := hd["door"] as Dictionary
		if not is_instance_valid(door["pivot"]):
			ok = _check("door_pivot_" + tag, false, ok)
		if not is_instance_valid(hd["roof"]):
			ok = _check("roof_" + tag, false, ok)
		if nb._on_road(door["pos"], 1.0):
			ok = _check("door_off_road_" + tag, false, ok)
	# Safehouse bookkeeping agrees.
	var sh := nb.houses[nb.safehouse_index] as Dictionary
	ok = _check("sh_door_pos_" + tag,
		nb.safehouse_door_pos.distance_to((sh["door"] as Dictionary)["pos"]) < 0.01, ok)
	ok = _check("sh_door_flag_" + tag, bool((sh["door"] as Dictionary)["safehouse"]), ok)
	ok = _check("boards_" + tag, nb.safehouse_boards.size() > 0, ok)
	# Commercial buildings: 5 kinds (police, hospital, grocery, a 4th
	# rotating kind, + the v2 warehouse); anchored kinds always present.
	ok = _check("buildings_5_" + tag, nb.buildings.size() == 5, ok)
	var kinds := {}
	for b in nb.buildings:
		kinds[String((b as Dictionary)["kind"])] = true
	ok = _check("bld_police_" + tag, kinds.has("police"), ok)
	ok = _check("bld_hospital_" + tag, kinds.has("hospital"), ok)
	ok = _check("bld_grocery_" + tag, kinds.has("grocery"), ok)
	ok = _check("bld_names_" + tag,
		String((nb.buildings[0] as Dictionary)["name"]) != "", ok)
	for b in nb.buildings:
		var bd := b as Dictionary
		var bdoor := bd["door"] as Dictionary
		if not is_instance_valid(bdoor["pivot"]):
			ok = _check("bld_pivot_" + tag, false, ok)
		if not is_instance_valid(bd["roof"]):
			ok = _check("bld_roof_" + tag, false, ok)
		if String(bd["kind"]) == "police" and not bool(bdoor.get("locked", false)):
			ok = _check("police_locked_" + tag, false, ok)
		if String(bd["kind"]) != "police" and bool(bdoor.get("locked", false)):
			ok = _check("only_police_locked_" + tag, false, ok)
	# Brutes only in the police station; interior walkers in other buildings.
	ok = _check("brutes_2_" + tag, nb.brute_spawns.size() == 2, ok)
	ok = _check("indoor_z_" + tag, nb.building_zombie_spawns.size() >= 4, ok)
	# Zone phase: brutes spawn inside the police hidden zone, not the
	# exterior footprint. Check them against the zone bounds.
	var pzb := Rect2()
	for z in (nb.get("interior_zones") as Node).get("zones"):
		var zd := z as Dictionary
		if String(zd["kind"]) == "police":
			pzb = zd["bounds"] as Rect2
	for bs in nb.brute_spawns:
		var bp := Vector2((bs as Vector3).x, (bs as Vector3).z)
		if not pzb.grow(0.6).has_point(bp):
			ok = _check("brutes_in_police_" + tag, false, ok)
	ok = _check("interior_hash_" + tag, nb.interior_hash() != "", ok)
	# Zone origins are deterministic: same seed => same origins, and they
	# follow the documented far-zone layout (1200 + zi*500, 1200).
	var origins: Array = []
	for z in (nb.get("interior_zones") as Node).get("zones"):
		origins.append((z as Dictionary)["origin"])
	ok = _check("zone_origins_stable_" + tag,
		origins == _zone_origins_for(seed, tag), ok)
	for zi in origins.size():
		var want := Vector3(1200.0 + float(zi) * 500.0, 0.0, 1200.0)
		if (origins[zi] as Vector3).distance_to(want) > 0.01:
			ok = _check("zone_origin_formula_" + tag, false, ok)
	# No lot overlaps another lot or a road (the generator's own guarantee).
	var rects: Array = nb._lot_rects
	for i in rects.size():
		for r in nb._road_rects:
			if (r as Rect2).grow(2.0).intersects(rects[i]):
				ok = _check("lot_off_road_" + tag, false, ok)
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				ok = _check("lots_disjoint_" + tag, false, ok)
	nb.free()
	return ok
