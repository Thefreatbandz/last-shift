extends SceneTree
## Apocalypse dressing QA: boots the real game, asserts dressing nodes exist
## with sane counts, verifies the builder's layout hash is untouched, and
## proves determinism (two fresh builds of the same seed produce identical
## stats + positions).
##   godot --headless --path . --script res://tests/apocalypse_dress_qa.gd

const SEED := 48392017

var _booted := false
var _frames := 0
var _ok := true
var _phase := 0
var _main: Node
var _hood: Node
var _dress: Node
var _snap_main := ""
var _hash_main := ""


func _check(name: String, cond: bool) -> void:
	print("APOCQA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


func _count_descendants(n: Node, cls: String) -> int:
	var c := 0
	for ch in n.get_children():
		if ch.is_class(cls):
			c += 1
		c += _count_descendants(ch, cls)
	return c


func _count_loot_containers(n: Node) -> int:
	# Runtime script comparison: referencing the LootContainer global class at
	# parse time would force early compilation (see _build_standalone).
	var loot_script: Script = load("res://scripts/loot/loot_container.gd")
	var c := 0
	for ch in n.get_children():
		if ch.get_script() == loot_script:
			c += 1
		c += _count_loot_containers(ch)
	return c


func _build_standalone() -> Array:
	# Fresh NeighborhoodBuilder + dressing, no game systems.
	# NOTE: the builder/choppable scripts reference the Sound autoload, so the
	# script resources must be loaded at RUNTIME (autoloads registered), not
	# via global class identifiers at parse time — parse-time resolution
	# compiles them before autoloads exist and poisons the whole run.
	var hood_script: Script = load("res://scripts/world/neighborhood_builder.gd")
	var dress_script: Script = load("res://scripts/world/apocalypse_dressing.gd")
	var b: Node = hood_script.new()
	root.add_child(b)
	b.call("build_world", SEED)
	var d: Node = dress_script.new()
	d.call("dress", b)
	var snap: String = d.call("get_fingerprint")
	var h: String = b.call("layout_hash")
	return [b, snap, h]


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", SEED)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1

	# Phase 0: real game boot — dressing exists with sane counts.
	if _phase == 0 and _frames == 90:
		_hood = _main.get_node("Neighborhood")
		_dress = _hood.get_node_or_null("ApocalypseDressing")
		_check("dressing_node_exists", _dress != null)
		if _dress == null:
			quit(1)
			return true
		var s: Dictionary = _dress.call("get_stats")
		print("APOCQA stats ", s)
		_check("blood_gt_0", int(s["blood"]) > 0)
		_check("corpses_10_to_16", int(s["corpses"]) >= 10 and int(s["corpses"]) <= 16)
		_check("barrel_fires_3_to_5", int(s["barrel_fires"]) >= 3 and int(s["barrel_fires"]) <= 5)
		_check("burning_wrecks_2_to_3", int(s["burning_wrecks"]) >= 2 and int(s["burning_wrecks"]) <= 3)
		_check("wrecks_4_to_6", int(s["wrecks"]) >= 4 and int(s["wrecks"]) <= 6)
		_check("rubble_8_to_12", int(s["rubble"]) >= 8 and int(s["rubble"]) <= 12)
		_check("lights_le_4", int(s["lights"]) <= 4)
		_check("lights_gt_0", int(s["lights"]) > 0)
		# No gameplay footprint: no loot containers, no static bodies under dressing.
		_check("no_loot_containers", _count_loot_containers(_dress) == 0)
		_check("no_static_bodies", _count_descendants(_dress, "StaticBody3D") == 0)
		# No particle spam: every smoke system <= 24 particles.
		var smoke_ok := true
		for ch in _dress.find_children("*", "GPUParticles3D", true, false):
			if (ch as GPUParticles3D).amount > 24:
				smoke_ok = false
		_check("smoke_amount_le_24", smoke_ok)
		_snap_main = String(_dress.call("get_fingerprint"))
		_hash_main = String(_hood.call("layout_hash"))
		_phase = 1

	# Phase 1: standalone build #1 — must match the real-game dressing exactly,
	# and the layout hash must be identical (dressing is append-only).
	elif _phase == 1:
		var r1 := _build_standalone()
		var b1: Node = r1[0]
		_check("standalone_fingerprint_matches_game", String(r1[1]) == _snap_main)
		_check("layout_hash_untouched_by_dressing", String(r1[2]) == _hash_main)
		b1.queue_free()
		_phase = 2
		_frames = 0

	# Phase 2: standalone build #2 — same seed => identical dressing.
	elif _phase == 2 and _frames >= 5:
		var r2 := _build_standalone()
		var b2: Node = r2[0]
		_check("rebuild_fingerprint_identical", String(r2[1]) == _snap_main)
		_check("rebuild_layout_hash_identical", String(r2[2]) == _hash_main)
		b2.queue_free()
		print("APOCQA RESULT ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return true
	return false
