extends SceneTree
## Detail + zombie-animation + interior-loot QA.
## - Zombie combat numbers UNCHANGED: attack envelope 0.38s, AI hit trigger
##   0.22s, walk/chase speeds, damage, range, cooldown, flinch/death times,
##   brute multipliers all identical to before the animation quality pass.
## - Interior loot: every non-safehouse house has 3 containers (corner +
##   bedroom duffel + back-corner junk), the safehouse has 2 (corner + junk).
## - All interior containers sit inside their house footprint; kinds pair
##   sensibly (bedroom = duffel, junk = crate/trash).
## - House loot is deterministic: positions are a pure function of the
##   builder's house dicts (no RNG in the placement block) and the builder
##   layout hash is unchanged.
## - Commercial loot pairs with its building (grocery -> food, hospital ->
##   meds, etc.).
## Run: godot --headless --path . --script res://tests/detail_anim_loot_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEEDS := [48392017, 777, 12345]
const EPS := 0.05

var _booted := false
var _frames := 0
var _ok := true
var _main: Node
var _nb: Node # live NeighborhoodBuilder from the booted main scene
# Lazy load: NeighborhoodBuilder touches the Sound autoload (via
# ChoppableTree); static class_name refs compile before autoloads register
# in bare --script mode. (prompt_qa.gd precedent.)
var _NB: GDScript


func _check(label: String, cond: bool) -> void:
	if cond:
		print("DETQA PASS ", label)
	else:
		_ok = false
		print("DETQA FAIL ", label)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_static_anim_checks()
		_NB = load("res://scripts/world/neighborhood_builder.gd")
		_builder_determinism_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 45:
		_live_loot_checks()
		print("DETQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


# ---------------------------------------------------------------- static anim
func _static_anim_checks() -> void:
	# zombie_ai.gd is checked via source text, NOT the class_name: naming the
	# class in a --script test poisons its compile (it references the Sound
	# autoload, which the --script compiler can't see). Speeds, damage,
	# range, cooldown, hit trigger, brute multipliers: never touched.
	var asrc := FileAccess.get_file_as_string(
		"res://scripts/zombie/zombie_ai.gd")
	_check("wander_day_1.2", asrc.contains("const WANDER_DAY := 1.2"))
	_check("wander_night_1.8", asrc.contains("const WANDER_NIGHT := 1.8"))
	_check("chase_day_2.7", asrc.contains("const CHASE_DAY := 2.7"))
	_check("chase_night_3.8", asrc.contains("const CHASE_NIGHT := 3.8"))
	_check("attack_range_1.7", asrc.contains("const ATTACK_RANGE := 1.7"))
	_check("attack_damage_12", asrc.contains("const ATTACK_DAMAGE := 12.0"))
	_check("attack_cooldown_1.3", asrc.contains("const ATTACK_COOLDOWN := 1.3"))
	_check("max_hp_100", asrc.contains("const MAX_HP := 100.0"))
	_check("ai_hit_trigger_0.22", asrc.contains("_attack_hit_t = 0.22"))
	_check("brute_hp_220", asrc.contains("max_hp = 220.0"))
	_check("brute_spd_1.22", asrc.contains("spd_mult = 1.22"))
	_check("brute_dmg_1.5", asrc.contains("dmg_mult = 1.5"))
	# zombie_visual.gd has no autoload references, so the class is safe to
	# touch: attack envelope still exactly 0.38s, flinch 0.30s, death 0.45s.
	_check("flinch_time_0.30", is_equal_approx(ZombieVisual.FLINCH_TIME, 0.30))
	_check("dead_time_0.45", is_equal_approx(ZombieVisual.DEAD_TIME, 0.45))
	var zv := ZombieVisual.new()
	zv.play_lunge()
	_check("lunge_envelope_0.38", is_equal_approx(zv.get("_lunge_t"), 0.38))
	zv.free()
	var vsrc := FileAccess.get_file_as_string(
		"res://scripts/zombie/zombie_visual.gd")
	_check("visual_lunge_0.38", vsrc.contains("_lunge_t = 0.38"))
	_check("no_body_lunge", not vsrc.contains("position.z = -"))


# ------------------------------------------------- builder determinism
func _builder_determinism_checks() -> void:
	for seed in SEEDS:
		var a: Node = _NB.new()
		root.add_child(a)
		a.build_world(seed)
		var b: Node = _NB.new()
		root.add_child(b)
		b.build_world(seed)
		_check("layout_hash_stable_%d" % seed, a.layout_hash() == b.layout_hash())
		_check("house_dicts_identical_%d" % seed,
			_house_sig(a) == _house_sig(b) and _house_sig(a) != "")
		a.free()
		b.free()
	# The house-loot block in main.gd must not consume RNG: positions are a
	# pure function of the house dicts, so identical dicts => identical loot.
	var msrc := FileAccess.get_file_as_string("res://scripts/main.gd")
	var start := msrc.find("# Interior-loot density")
	var end := msrc.find("# Building types: seeded interior loot")
	var block := msrc.substr(start, end - start)
	_check("loot_block_no_rng",
		not block.contains("_rng") and not block.contains("_vrng")
		and not block.contains("randf") and not block.contains("randi"))


func _house_sig(nb: Node) -> String:
	var parts: PackedStringArray = []
	for hi in nb.houses.size():
		var d := nb.houses[hi] as Dictionary
		var p := d["pos"] as Vector3
		parts.append("%d|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [
			hi, 1 if hi == nb.safehouse_index else 0, p.x, p.y, p.z,
			float(d["w"]), float(d["d"]), float(d["face"])])
	return "|".join(parts)


# ---------------------------------------------------------------- live loot
func _live_loot_checks() -> void:
	_nb = _main.get_node("Neighborhood")
	var loot := _main.get_node("Loot")
	var containers: Array = loot.get_containers()
	# Index containers by rounded XZ for lookup.
	var by_xz := {}
	for c in containers:
		var p := (c as Node3D).global_position
		by_xz["%d,%d" % [int(round(p.x * 100.0)), int(round(p.z * 100.0))]] = c
	var houses: Array = _nb.houses
	_check("houses_present", houses.size() >= 12)
	for hi in houses.size():
		var h := houses[hi] as Dictionary
		var hp := h["pos"] as Vector3
		var hw := float(h["w"])
		var hd := float(h["d"])
		var hf := float(h["face"])
		var is_sh: bool = hi == _nb.safehouse_index
		var rect := Rect2(hp.x - hw * 0.5, hp.z - hd * 0.5, hw, hd)
		# Expected spots, mirroring main.gd's placement formulas exactly.
		var expected: Array = []
		expected.append({"off": Vector3(-hw * 0.5 + 1.0, 0, hf * (hd * 0.5 - 1.2)),
			"kind": "crate"})
		if not is_sh:
			var bedx := -(hw * 0.5 - 1.35)
			var bedz := -hf * (hd * 0.5 - 1.75)
			expected.append({"off": Vector3(bedx + 0.55, 0, bedz + hf * 1.15),
				"kind": "duffel"})
		var ck := "crate" if hi % 3 != 2 else "trash"
		expected.append({"off": Vector3(-0.5, 0, -hf * (hd * 0.5) + hf * 0.9),
			"kind": ck})
		var found := 0
		for e in expected:
			var wp: Vector3 = hp + (e["off"] as Vector3)
			var key := "%d,%d" % [int(round(wp.x * 100.0)), int(round(wp.z * 100.0))]
			var c: Node = by_xz.get(key)
			if c == null:
				_check("house_%d_has_%s_at_expected" % [hi, String(e["kind"])], false)
				continue
			found += 1
			_check("house_%d_%s_kind" % [hi, String(e["kind"])],
				String((c as Node).get("kind")) == String(e["kind"]))
			var cp := (c as Node3D).global_position
			_check("house_%d_%s_inside" % [hi, String(e["kind"])],
				rect.grow(EPS).has_point(Vector2(cp.x, cp.z)))
			# Reachable: the player can stand adjacent (inside-footprint +
			# not buried in a wall is guaranteed by the inside check and the
			# clearance analysis in main.gd).
		_check("house_%d_loot_count_%d" % [hi, expected.size()],
			found == expected.size())
	_commercial_pairing_checks()


func _commercial_pairing_checks() -> void:
	# Every commercial loot entry pairs sensibly with its building kind.
	var bld := _nb # NeighborhoodBuilder
	var entries: Array = bld.building_loot
	_check("commercial_loot_present", entries.size() >= 10)
	var grocery_food := 0
	var grocery_total := 0
	var corner_general := 0
	var corner_total := 0
	var hospital_meds := 0
	var hospital_total := 0
	for e in entries:
		var d := e as Dictionary
		var pos := d["pos"] as Vector3
		var bkind := _building_kind_at(pos)
		var items: Array = d["items"]
		var names: Array = []
		for it in items:
			names.append(String((it as Array)[0]))
		if bkind == "grocery":
			grocery_total += 1
			if names.has("canned_food") or names.has("water"):
				grocery_food += 1
		elif bkind == "corner":
			# Corner stores are general stores: food/water/medicine up
			# front, scrap/cloth in the back (building_types.gd).
			corner_total += 1
			if names.has("canned_food") or names.has("water") \
					or names.has("medicine") or names.has("scrap") \
					or names.has("cloth"):
				corner_general += 1
		elif bkind == "hospital":
			hospital_total += 1
			if names.has("medicine") or names.has("bandage") or names.has("medkit"):
				hospital_meds += 1
	_check("grocery_loot_is_food",
		grocery_total >= 3 and grocery_food == grocery_total)
	_check("corner_loot_is_general_goods",
		corner_total >= 2 and corner_general == corner_total)
	_check("hospital_loot_is_meds",
		hospital_total >= 2 and hospital_meds >= 2)


func _building_kind_at(pos: Vector3) -> String:
	for b in _nb.buildings:
		var d := b as Dictionary
		var bp := d["pos"] as Vector3
		var w := float(d["w"])
		var dd := float(d["d"])
		if Rect2(bp.x - w * 0.5, bp.z - dd * 0.5, w, dd).grow(0.5) \
				.has_point(Vector2(pos.x, pos.z)):
			return String(d["kind"])
	# Zone phase: zoned buildings keep their loot in the hidden zone.
	# Map zone positions back to the owning exterior building kind.
	var iz: Node = _nb.get("interior_zones")
	if iz != null:
		for z in iz.get("zones"):
			var zd := z as Dictionary
			var zb := zd["bounds"] as Rect2
			if zb.grow(0.6).has_point(Vector2(pos.x, pos.z)):
				return String(zd["kind"])
	return ""
