extends SceneTree
## Regression: searching a container MUST grant its loot into the inventory
## and MUST show the unmissable HUD pickup toast. Covers both the direct
## search path (_on_search) and the full touch path (interact acquire ->
## try_interact), so a silent/empty search can never ship again.
##   godot --headless --path . --script res://tests/loot_grant_qa.gd

var _booted := false
var _frames := 0
var _main: Node
var _ok := true
var _phase := 0
var _lm: Node
var _inv: Node
var _player: Node
var _hud: Node
var _interact: Node
var _target: Node = null
var _target2: Node = null
var _before := {}
var _toast_seen := false # latched: pickup toast was visible at any frame
var _toast_text := ""


func _check(name: String, cond: bool) -> void:
	print("LOOTQA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


func _pick_target() -> Node:
	var cs: Array = _lm.call("get_containers")
	for c in cs:
		if (c.get("loot") as Array).size() > 0 and not bool(c.get("searched")):
			return c
	return null


func _snapshot_inv() -> Dictionary:
	var d := {}
	for k in (_inv.get("items") as Dictionary).keys():
		d[k] = _inv.call("count", k)
	return d


func _gained(before: Dictionary) -> bool:
	for k in (_inv.get("items") as Dictionary).keys():
		if int(_inv.call("count", k)) > int(before.get(k, 0)):
			return true
	return false


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	# Latch: was the pickup toast ever visible since the search started?
	if (_phase == 1 or _phase == 3 or _phase == 4) and _hud != null:
		var tl: Control = _hud.get("_pickup_label")
		if tl != null and tl.visible:
			_toast_seen = true
			_toast_text = String(tl.get("text"))
	# Phase 0 sweep: NO container anywhere may ship with empty loot — a
	# completed search must always grant something (or say NOTHING FOUND).
	if _phase == 0 and _frames == 30:
		_lm = _main.get_node("Loot")
		_inv = _main.get_node("Inventory")
		_player = _main.get_node("Player")
		_hud = _main.get_node("HUD")
		_interact = _main.get_node("Interact")
		var all_have_loot := true
		for c in (_lm.call("get_containers") as Array):
			if (c.get("loot") as Array).is_empty():
				all_have_loot = false
				print("LOOTQA empty container kind=", c.get("kind"),
					" pos=", (c as Node3D).global_position)
		_check("no_empty_loot_containers", all_have_loot)
	# Phase 1: direct search path.
	if _phase == 0 and _frames == 60:
		_target = _pick_target()
		_check("container_with_loot_found", _target != null)
		if _target == null:
			quit(1)
			return true
		_before = _snapshot_inv()
		(_player as Node3D).global_position = \
			(_target as Node3D).global_position + Vector3(0.5, 0, 0)
		_lm.call("_on_search", _target)
		_check("search_started", bool(_lm.get("_searching")))
		_phase = 1
	elif _phase == 1 and _frames >= 60 + 240: # SEARCH_TIME=1.5s + margin
		_check("container_marked_searched", bool(_target.get("searched")))
		_check("inventory_gained_items", _gained(_before))
		_check("pickup_toast_shown", _toast_seen)
		_check("pickup_toast_names_items", _toast_text.contains("+"))
		_toast_seen = false
		_toast_text = ""
		_phase = 2
	# Phase 2: full interact path (acquire -> try_interact like USE button).
	elif _phase == 2 and _frames == 60 + 300:
		_target2 = _pick_target()
		_check("second_container_found", _target2 != null)
		if _target2 == null:
			quit(1)
			return true
		_before = _snapshot_inv()
		(_player as Node3D).global_position = \
			(_target2 as Node3D).global_position + Vector3(0.5, 0, 0)
		_phase = 3
	elif _phase == 3 and _frames >= 60 + 420:
		_interact.call("try_interact")
		_check("interact_started_search", bool(_lm.get("_searching")))
		_phase = 4
	elif _phase == 4 and _frames >= 60 + 700:
		_check("interact_container_searched", bool(_target2.get("searched")))
		_check("interact_granted_items", _gained(_before))
		_check("interact_pickup_toast_shown", _toast_seen)
		print("LOOTQA RESULT ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return true
	return false
