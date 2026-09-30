extends SceneTree
## Probe 2: full interact path — teleport player to a container, let the
## interact manager acquire it, call try_interact() like the USE button does.
## Usage: xvfb-run -a godot --headless --path . --script res://tests/probe_interact.gd

var _booted := false
var _frames := 0
var _phys := 0
var _main: Node
var _lm: Node
var _inv: Node
var _player: Node
var _interact: Node
var _target: Node = null
var _phase := 0
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
	if _phase == 0 and _frames == 60:
		_lm = _main.get_node("Loot")
		_inv = _main.get_node("Inventory")
		_player = _main.get_node("Player")
		_interact = _main.get_node("Interact")
		var cs: Array = _lm.call("get_containers")
		for c in cs:
			var loot: Array = c.get("loot")
			if loot.size() > 0:
				_target = c
				break
		(_player as Node3D).global_position = (_target as Node3D).global_position + Vector3(0.5, 0, 0)
		for k in (_inv.get("items") as Dictionary).keys():
			_before[k] = _inv.call("count", k)
		print("PROBE2 standing by container, waiting for interact acquire")
		_phase = 1
	elif _phase == 1 and _frames >= 120:
		print("PROBE2 current=", _interact.get("_current"))
		_interact.call("try_interact")
		print("PROBE2 try_interact called, searching=", _lm.get("_searching"))
		_phase = 2
	elif _phase == 2 and _frames >= 600:
		var after := {}
		for k in (_inv.get("items") as Dictionary).keys():
			after[k] = _inv.call("count", k)
		var gained := false
		for k in after.keys():
			if int(after[k]) > int(_before.get(k, 0)):
				gained = true
		print("PROBE2 before=", _before, " after=", after)
		print("PROBE2 searched=", _target.get("searched"), " gained=", gained)
		quit(0 if gained else 1)
		return true
	return false
