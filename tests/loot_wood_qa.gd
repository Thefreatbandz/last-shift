extends SceneTree
## Loot pool + zombie drops + wood economy regression suite.
## - Zombie drops: ~1 in 3 kills, ammo or crafting part, via LootManager.
## - Choppable dead trees: 16 per neighborhood, 2 chops -> felled, 2-3 wood.
## - Melee swings chop trees in the arc (combat wired to choppables).
## - Lumber piles by the warehouse; warehouse loot wood-heavy.
## - Wave scarcity: ammo shrinks / guns may vanish at higher waves, crafting
##   untouched. Deterministic (seeded, no randomize()).
## - Barricade (3 wood) payable from one tree or one lumber pile.
## Run: godot --headless --path . --script res://tests/loot_wood_qa.gd
## NOTE: Sound autoload is invisible to --script; duck-type everything.

var _booted := false
var _frames := 0
var _ok := true
var _main: Node


func _check(label: String, cond: bool) -> void:
	if cond:
		print("LOOTQA PASS ", label)
	else:
		_ok = false
		print("LOOTQA FAIL ", label)


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_static_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 45:
		_live_checks_a()
	elif _frames == 60:
		_live_checks_b()
		print("LOOTQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


# ------------------------------------------------------------- static checks

func _static_checks() -> void:
	var zai := _src("res://scripts/zombie/zombie_ai.gd")
	_check("died_signal", zai.contains("signal died"))
	var zm := _src("res://scripts/zombie/zombie_manager.gd")
	_check("drop_chance", zm.contains("DROP_CHANCE := 0.34"))
	_check("drop_context", zm.contains("func set_drop_context"))
	_check("roll_drop", zm.contains("func _roll_drop"))
	var ct := _src("res://scripts/world/choppable_tree.gd")
	_check("tree_class", ct.contains("class_name ChoppableTree"))
	_check("tree_felled_signal", ct.contains("signal felled"))
	_check("tree_hp2", ct.contains("hp := 2") or ct.contains("hp = 2"))
	var nb := _src("res://scripts/world/neighborhood_builder.gd")
	_check("tree_stream", nb.contains("_crng.seed = seed ^ 0x5EED71"))
	_check("tree_build", nb.contains("func _build_choppables"))
	_check("tree_cleared", nb.contains("choppable_trees.clear()"))
	var pc := _src("res://scripts/combat/player_combat.gd")
	_check("combat_choppables", pc.contains("var choppables"))
	_check("combat_chop_call", pc.contains("tree.chop()"))
	var lm := _src("res://scripts/loot/loot_manager.gd")
	_check("scarcity_fn", lm.contains("func _apply_scarcity"))
	_check("scarcity_guns", lm.contains("SCARCE_GUNS"))
	_check("scarcity_ammo", lm.contains("SCARCE_AMMO"))
	var lc := _src("res://scripts/loot/loot_container.gd")
	_check("drop_kind", lc.contains("\"drop\": \"TAKE\""))
	_check("lumber_kind", lc.contains("\"lumber\": \"TAKE LUMBER\""))
	_check("drop_build", lc.contains("func _build_drop"))
	_check("lumber_build", lc.contains("func _build_lumber"))
	var bt := _src("res://scripts/world/building_types.gd")
	_check("lumber_piles", bt.contains("\"lumber\""))
	# Zone phase: warehouse/police loot lives in the hidden zones now.
	var iz := _src("res://scripts/world/interior_zones.gd")
	_check("warehouse_wood", iz.contains("[\"scrap\", 3], [\"wood\", 3]"))
	_check("police_lockpick", iz.contains("[\"lockpick\", 1]"))
	var mg := _src("res://scripts/main.gd")
	_check("main_drop_wire", mg.contains("set_drop_context"))
	_check("main_tree_wire", mg.contains("_on_tree_felled"))
	_check("main_scarcity_wire", mg.contains("loot.wave_manager = waves"))
	var bm := _src("res://scripts/world/barricade_manager.gd")
	_check("barricade_cost_3wood", bm.contains("BUILD_WOOD := 3"))
	for p in ["res://scripts/world/choppable_tree.gd",
			"res://scripts/zombie/zombie_manager.gd",
			"res://scripts/loot/loot_manager.gd",
			"res://scripts/world/neighborhood_builder.gd"]:
		_check("no_randomize_" + p.get_file(), not _src(p).contains("randomize()"))


# ---------------------------------------------------------------- live: A

func _live_checks_a() -> void:
	var hood: Node = _main.get_node("Neighborhood")
	var trees: Array = hood.get("choppable_trees")
	_check("tree_count_16", trees.size() == 16)
	var zombies: Node = _main.get_node("Zombies")
	_check("drops_on", bool(zombies.get("_drops_on")))
	# Drop rate sanity: 400 rolls should land ~34% (loose 25-45% band).
	var drops := 0
	var seen_ammo := false
	var seen_part := false
	for i in 400:
		var d: Array = zombies.call("_roll_drop")
		if d.is_empty():
			continue
		drops += 1
		var item: Array = d[0]
		var id := String(item[0])
		var n := int(item[1])
		if id == "ammo_9mm" or id == "shells":
			seen_ammo = true
			_check("drop_n_%d_%s" % [i, id], n >= 2 and n <= 6)
		else:
			seen_part = true
			_check("drop_n_%d_%s" % [i, id], (id == "scrap" or id == "cloth") and n >= 1 and n <= 2)
	_check("drop_rate", drops >= 100 and drops <= 180)
	_check("drop_ammo_seen", seen_ammo)
	_check("drop_part_seen", seen_part)
	# Lumber piles exist wherever the warehouse landed.
	var loot: Node = _main.get_node("Loot")
	var lumber := 0
	for c in loot.call("get_containers"):
		if String(c.get("kind")) == "lumber":
			lumber += 1
	_check("lumber_piles", lumber >= 2)


# ---------------------------------------------------------------- live: B

func _live_checks_b() -> void:
	var hood: Node = _main.get_node("Neighborhood")
	var trees: Array = hood.get("choppable_trees")
	var tree: Node = trees[0]
	var inv: Node = _main.get_node("Inventory")
	var before := int(inv.call("count", "wood"))
	tree.call("chop")
	_check("tree_hp1", int(tree.get("hp")) == 1 and not bool(tree.get("felled_flag")))
	tree.call("chop")
	_check("tree_felled", bool(tree.get("felled_flag")))
	var gained := int(inv.call("count", "wood")) - before
	_check("tree_wood_3", gained == 3)
	# One tree pays for exactly one door barricade (BUILD_WOOD := 3).
	var loot: Node = _main.get_node("Loot")
	var waves: Node = _main.get_node("Waves")
	# Scarcity: wave 1 untouched, wave 4+ shrinks ammo and may drop guns.
	var armory: Array = [["pistol", 1], ["ammo_9mm", 12], ["shells", 8], ["scrap", 2]]
	var w1: Array = loot.call("_apply_scarcity", armory, 3)
	_check("scarcity_w1_full", str(w1) == str(armory))
	waves.set("wave_number", 4)
	var w4: Array = loot.call("_apply_scarcity", armory, 3)
	var ammo4 := 0
	var gun4 := false
	for e in w4:
		if String(e[0]) == "ammo_9mm":
			ammo4 = int(e[1])
		if String(e[0]) == "pistol":
			gun4 = true
	_check("scarcity_ammo_shrinks", ammo4 >= 1 and ammo4 < 12)
	# Across many container ids at wave 5, some guns must be picked clean.
	var keeps := 0
	for cid in 40:
		var g: Array = loot.call("_apply_scarcity", [["shotgun", 1]], cid)
		if String(g[0][0]) == "shotgun":
			keeps += 1
	_check("scarcity_guns_thin", keeps >= 4 and keeps <= 28)
	waves.set("wave_number", 0)
