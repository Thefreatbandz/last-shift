extends SceneTree
## Probe: does searching a real container grant loot end-to-end?
## Usage: xvfb-run -a godot --headless --path . --script res://tests/probe_search_grant.gd

var _booted := false
var _frames := 0
var _main: Node
var _lm: Node
var _inv: Node
var _player: Node
var _target: Node = null
var _before := {}

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 60:
		_lm = _main.get_node("Loot")
		_inv = _main.get_node("Inventory")
		_player = _main.get_node("Player")
		var cs: Array = _lm.call("get_containers")
		print("PROBE containers=", cs.size())
		for c in cs:
			var loot: Array = c.get("loot")
			if loot.size() > 0:
				_target = c
				break
		if _target == null:
			print("PROBE FAIL: no container with loot")
			quit(1)
			return true
		print("PROBE target loot=", _target.get("loot"), " searched=", _target.get("searched"))
		for k in (_inv.get("items") as Dictionary).keys():
			_before[k] = _inv.call("count", k)
		# Stand right on top of it so the search can't cancel from distance.
		(_target as Node3D).set("searched", false)
		(_player as Node3D).global_position = (_target as Node3D).global_position + Vector3(0.5, 0, 0)
		_lm.call("_on_search", _target)
		print("PROBE search started searching=", _lm.get("_searching"), " t=", _lm.get("_search_t"))
	elif _frames == 90:
		print("PROBE mid searching=", _lm.get("_searching"), " t=", _lm.get("_search_t"),
			" dist=", (_player as Node3D).global_position.distance_to((_target as Node3D).global_position))
	elif _frames == 60 + 200:
		var after := {}
		for k in (_inv.get("items") as Dictionary).keys():
			after[k] = _inv.call("count", k)
		print("PROBE before=", _before)
		print("PROBE after=", after)
		print("PROBE target searched=", _target.get("searched"))
		var gained := false
		for k in after.keys():
			if int(after[k]) > int(_before.get(k, 0)):
				gained = true
		print("PROBE RESULT gained_loot=", gained)
		quit(0 if gained else 1)
		return true
	return false
