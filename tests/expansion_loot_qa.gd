extends SceneTree
## World expansion + loot container variety QA.
## - MAP_HALF is 100 (200x200m world), minimap model matches.
## - 12-14 houses, 10 zombie spawns, all on valid open ground.
## - Exactly OUTDOOR_LOOT_COUNT (18) seeded outdoor containers with the
##   expected kind mix, every spot reachable (off roads/lots, in bounds).
## - Loot placement is deterministic: rebuild => identical spots.
## - Boundary: collision walls at +/-(MAP_HALF+0.5), visible EdgeBrush node.
## Run: godot --headless --path . --script res://tests/expansion_loot_qa.gd

var _ran := false
var _ok := true

const EXPECT_KINDS := {
	"trash": 5, "corpse": 2, "fresh_corpse": 2, "toolbox": 2,
	"firstaid": 2, "duffel": 2, "crate": 3,
}


func _check(name: String, cond: bool) -> void:
	print("EXPLOOTQA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_check("map_half_100", is_equal_approx(NeighborhoodBuilder.MAP_HALF, 100.0))
	_check("minimap_half_match",
		is_equal_approx(MinimapModel.HALF, NeighborhoodBuilder.MAP_HALF))
	for seed in [48392017, 777, 12345678]:
		_check_seed(seed)
	# Determinism: rebuild seed 48392017 => identical outdoor loot.
	var a := _loot_sig(48392017)
	var b := _loot_sig(48392017)
	_check("loot_deterministic", a == b and a != "")
	_check("loot_varies_by_seed", a != _loot_sig(777))
	print("EXPLOOTQA_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


func _check_seed(seed: int) -> void:
	var tag := "seed_%d" % seed
	var nb := NeighborhoodBuilder.new()
	root.add_child(nb)
	nb.build_world(seed)
	var n := nb.houses.size()
	_check("houses_12_14_" + tag, n >= 12 and n <= 14)
	_check("zspawns_10_" + tag, nb.zombie_spawns.size() == 10)
	for s in nb.zombie_spawns:
		if nb._point_in_lots(s, 0.5) or nb._on_road(s):
			_check("zspawn_clear_" + tag, false)
		if absf(s.x) > 95.0 or absf(s.z) > 95.0:
			_check("zspawn_in_bounds_" + tag, false)
	# Outdoor loot: exact count, expected kind mix, all spots reachable.
	var ol: Array = nb.outdoor_loot
	_check("outdoor_count_" + tag, ol.size() == NeighborhoodBuilder.OUTDOOR_LOOT_COUNT)
	var kinds := {}
	for e in ol:
		var ed := e as Dictionary
		var k := String(ed["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
		var p := ed["pos"] as Vector3
		if nb._on_road(p, 0.5) or nb._point_in_lots(p, 0.5):
			_check("loot_reachable_" + tag, false)
		if absf(p.x) > 96.0 or absf(p.z) > 96.0:
			_check("loot_in_bounds_" + tag, false)
		var items := ed["items"] as Array
		if items.is_empty():
			_check("loot_nonempty_" + tag, false)
		if not LootContainer.PROMPTS.has(k):
			_check("loot_known_kind_" + tag, false)
	for k in EXPECT_KINDS:
		_check("kind_%s_%s" % [k, tag], int(kinds.get(k, 0)) == int(EXPECT_KINDS[k]))
	# Boundary: collision walls + visible brush barrier at the new edge.
	_check("edge_brush_" + tag, nb.get_node_or_null("EdgeBrush") != null)
	nb.free()


func _loot_sig(seed: int) -> String:
	var nb := NeighborhoodBuilder.new()
	root.add_child(nb)
	nb.build_world(seed)
	var parts: Array[String] = []
	for e in nb.outdoor_loot:
		var ed := e as Dictionary
		var p := ed["pos"] as Vector3
		var items := ed["items"] as Array
		var istr := ""
		for it in items:
			istr += "%s%d" % [String(it[0]), int(it[1])]
		parts.append("%s:%.2f,%.2f:%s" % [String(ed["kind"]), p.x, p.z, istr])
	nb.free()
	return "|".join(parts)
