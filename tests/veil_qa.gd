extends SceneTree
## Veil QA: doorway veil visible when player outside, hidden when inside.
## Roof visibility follows the same inside/outside contract.

var _booted := false
var _frames := 0
var _main: Node
var _ok := true


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
	if _frames == 90:
		var hood = _main.neighborhood
		var h: Dictionary = hood.houses[0]
		var pos: Vector3 = h["pos"]
		var face: float = h["face"]
		var d: float = h["d"]
		var veil: MeshInstance3D = (h["door"] as Dictionary)["veil"]
		var roof: Node3D = h["roof"]
		# Outside: veil visible, roof visible.
		_main.player.global_position = pos + Vector3(0, 0, face * (d * 0.5 + 3.0))
		_main.player.velocity = Vector3.ZERO
	elif _frames == 95:
		var hood = _main.neighborhood
		var h: Dictionary = hood.houses[0]
		var veil: MeshInstance3D = (h["door"] as Dictionary)["veil"]
		var roof: Node3D = h["roof"]
		_ok = _check("veil_visible_outside", veil.visible, _ok)
		_ok = _check("roof_visible_outside", roof.visible, _ok)
		# Move inside.
		var pos: Vector3 = h["pos"]
		_main.player.global_position = pos + Vector3(0, 0, -1.0)
		_main.player.velocity = Vector3.ZERO
	elif _frames == 100:
		var hood = _main.neighborhood
		var h: Dictionary = hood.houses[0]
		var veil: MeshInstance3D = (h["door"] as Dictionary)["veil"]
		var roof: Node3D = h["roof"]
		_ok = _check("veil_hidden_inside", not veil.visible, _ok)
		_ok = _check("roof_hidden_inside", not roof.visible, _ok)
		# Commercial: veil present and visible from outside.
		var b: Dictionary = hood.buildings[0]
		var bveil: MeshInstance3D = (b["door"] as Dictionary)["veil"]
		_ok = _check("commercial_veil_visible_outside", bveil.visible, _ok)
		print("VEILQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("VEILQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
