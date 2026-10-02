extends SceneTree
## Render a compound interior with a zombie inside (for visual QA).

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _seed := 48392017

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("IZSHOT saved ", n)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--izseed="):
				_seed = int(a.trim_prefix("--izseed="))
		root.get_node("RunState").set("world_seed", _seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 40:
		var nb: Node = _main.get_node("Neighborhood")
		var iz: Node = nb.get("interior_zones")
		var zones: Array = iz.get("zones")
		for z in zones:
			var zd: Dictionary = z
			if String(zd["kind"]) == "office_small":
				# Put the player inside; the zone becomes visible.
				# (spawn_in is 2.2m inside — clear of the exit trigger.)
				var spawn_in := zd["spawn_in"] as Vector3
				_main.player.global_position = spawn_in + Vector3(0, 0.1, 0)
				# Spawn a zombie inside the zone for the shot (passive, far).
				var zm: Node = _main.get_node("Zombies")
				zm._spawn_at(spawn_in + Vector3(-3.0, 0.3, -2.0))
				print("IZSHOT zone at ", (zd["origin"] as Vector3))
				break
	elif _frames == 100:
		print("IZSHOT player at ", _main.player.global_position)
		var nb2: Node = _main.get_node("Neighborhood")
		var iz2: Node = nb2.get("interior_zones")
		var pz: Dictionary = iz2.zone_at(_main.player.global_position)
		print("IZSHOT player zone: ", pz.get("kind", "NONE"))
		_shot("compound_interior.png")
		quit(0)
		return true
	return false
