extends SceneTree
## Screenshot staging for the loot/drop/wood pass:
##   1. wood_tree.png    — choppable dead tree, player beside it
##   2. wood_lumber.png  — lumber pile by the warehouse
##   3. wood_armory.png  — police armory container (pistol visible in loot)
##   4. wood_drop.png    — zombie drop pickup (kills until one appears)
## Usage: xvfb-run -a godot --path . --script res://tests/loot_wood_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/wood_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _player: Node
var _loot: Node
var _phase := 0


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("WSHOT saved ", name)


func _tp(p: Vector3) -> void:
	(_player as Node3D).global_position = Vector3(p.x, 0.3, p.z)
	_player.set("velocity", Vector3.ZERO)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		_player = _main.get_node("Player")
		_loot = _main.get_node("Loot")
		return false
	_frames += 1
	if _frames == 60:
		var trees: Array = _main.get_node("Neighborhood").get("choppable_trees")
		var tp: Vector3 = (trees[0] as Node3D).global_position
		_tp(tp + Vector3(2.5, 0, 2.5))
		_phase = 1
	elif _phase == 1 and _frames == 80:
		_shot("wood_tree")
		_phase = 2
	elif _phase == 2 and _frames == 95:
		_ensure_drop() # open ground by the tree: drop lands by the corpse
		_phase = 3
	elif _phase == 3 and _frames == 120:
		_shot("wood_drop")
		_phase = 4
	elif _phase == 4 and _frames == 135:
		var lp := _lumber_spot()
		_tp(lp + _wh_outward(lp) * 3.5) # step outside, away from the wall
		# Turn the camera to face the warehouse: pile framed against it.
		_main.get_node("CameraRig").call("set_yaw_immediate", PI)
		_phase = 5
	elif _phase == 5 and _frames == 160:
		_shot("wood_lumber")
		_phase = 6
	elif _phase == 6 and _frames == 175:
		_main.get_node("CameraRig").call("set_yaw_immediate", 0.0)
		_tp(_gun_spot() + Vector3(0, 0, 3.5))
		_phase = 7
	elif _phase == 7 and _frames == 200:
		_shot("wood_armory")
		_phase = 8
	elif _phase == 8 and _frames == 215:
		print("WSHOT done")
		quit(0)
		return true
	return false


func _lumber_spot() -> Vector3:
	for c in _loot.call("get_containers"):
		if String(c.get("kind")) == "lumber":
			return (c as Node3D).global_position
	return Vector3.ZERO


## Horizontal direction from the nearest warehouse to the pile (out front).
func _wh_outward(p: Vector3) -> Vector3:
	var best := Vector3(0, 0, 1)
	var best_d := 1e9
	var hood: Node = _main.get_node("Neighborhood")
	for b in hood.get("buildings"):
		var bd := b as Dictionary
		if String(bd.get("kind", "")) != "warehouse":
			continue
		var bp := bd["pos"] as Vector3
		var d: float = bp.distance_to(p)
		if d < best_d:
			best_d = d
			var o := p - bp
			o.y = 0.0
			best = o.normalized() if o.length() > 0.01 else best
	return best


func _gun_spot() -> Vector3:
	for c in _loot.call("get_containers"):
		for e in c.get("loot"):
			var id := String(e[0])
			if id == "pistol" or id == "shotgun":
				return (c as Node3D).global_position
	return Vector3.ZERO


func _ensure_drop() -> void:
	# Kill nearby zombies in place (near-zero impulse: they crumple where
	# they stand) until a drop appears (seeded ~1/3); fall back to staging
	# one manually so the visual is always captured.
	var zs: Node = _main.get_node("Zombies")
	var pp: Vector3 = (_player as Node3D).global_position
	var kill_spot: Vector3 = pp + Vector3(0, 0.3, -2.5)
	var kills := 0
	for z in zs.call("living_zombies"):
		if kills >= 5:
			break
		var zp: Vector3 = (z as Node3D).global_position
		if zp.distance_to(pp) > 40.0:
			continue
		(z as Node3D).global_position = kill_spot
		z.call("take_damage", 99999.0, kill_spot, 0.01)
		kills += 1
	var has_drop := false
	for c in _loot.call("get_containers"):
		if String(c.get("kind")) == "drop":
			has_drop = true
			_tp((c as Node3D).global_position + Vector3(0, 0, 3.2))
	if not has_drop:
		_loot.call("add_container", kill_spot, [["ammo_9mm", 5]], "drop")
		_tp(kill_spot + Vector3(0, 0, 3.2))
