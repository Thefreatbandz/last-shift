extends SceneTree
## Render a barrel fire + smoke from a top-down angle at 10:13.
## Tests whether smoke reads as a hard dark blob.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _seed := 48392017

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("SMOKESHOT saved ", n)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", _seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 40:
		_main.get_node("TimeManager").call("set_time", 10.2)
		var nb: Node = _main.get_node("Neighborhood")
		# Find a barrel fire position via the dressing stats, or just use safehouse porch
		var sh: Node = _main.get_node("Safehouse")
		var dp: Vector3 = sh.get("door_pos")
		_main.player.global_position = dp + Vector3(3.0, 0.3, 4.0)
	elif _frames == 100:
		_shot("smoke_test.png")
		quit(0)
		return true
	return false
