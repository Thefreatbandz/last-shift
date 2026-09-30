extends SceneTree
## Brute close-up only (fresh neutral-pose visual, clear of the wall).
##   xvfb-run -a godot --path . --script res://tests/building_shots5.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _nb
var _rig


func _bld(kind: String) -> Dictionary:
	for b in _nb.buildings:
		var bd := b as Dictionary
		if String(bd["kind"]) == kind:
			return bd
	return {}


func _brute_node() -> Node:
	for z in _main.get_node("Zombies").zombies:
		if z.get("is_brute"):
			return z
	return null


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_rig = _main.get_node("CameraRig")
		return false
	_main.player.get_node("Health").heal(1000.0)
	_frames += 1
	if _frames == 10:
		var p := _bld("police")
		var pp: Vector3 = p["pos"]
		var pf := float(p["face"])
		var spot := pp + Vector3(-6.0, 0.2, pf * 12.0)
		_main.player.global_position = spot
		var d := (pp + Vector3(-6.0, 1.0, pf * 2.0)) - spot
		d.y = 0.0
		_rig.set_yaw_immediate(atan2(-d.x, -d.z))
		_rig.snap()
		var live := _brute_node()
		if live != null:
			live.global_position = pp + Vector3(60.0, 0.3, 60.0)
	elif _frames == 55:
		var p2 := _bld("police")
		var pf2 := float(p2["face"])
		var pp2: Vector3 = _main.player.global_position
		var bv := ZombieVisual.new()
		_main.add_child(bv)
		(bv as ZombieVisual).set_brute()
		bv.global_position = Vector3(pp2.x, 0.0, pp2.z - pf2 * 4.0)
		bv.rotation.y = PI if pf2 > 0.0 else 0.0
	elif _frames == 70:
		DirAccess.make_dir_recursive_absolute(OUT)
		var img := root.get_texture().get_image()
		img.save_png(OUT + "/bld2_brute.png")
		print("BSHOT5 saved bld2_brute")
		quit(0)
		return true
	return false
