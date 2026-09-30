extends SceneTree
## Xvfb screenshot staging for the minimap:
##   1. gameplay with the corner minimap (fog partially revealed by travel)
##   2. expanded map overlay (seed label + legend)
##   3. corner minimap near a zombie (red dots visible)
## Usage: xvfb-run -a godot --path . --script res://tests/minimap_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/minimap_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"
const WAIT := 50

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("MSHOT saved ", name)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 777001)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _phase:
		0:
			# Let the world settle, then travel to reveal fog in 3 spots.
			if _frames == WAIT:
				_main.player.global_position = Vector3(30, 0, -20)
			elif _frames == WAIT + 25:
				_main.player.global_position = Vector3(-25, 0, 25)
			elif _frames == WAIT + 50:
				_main.player.global_position = Vector3(10, 0, 5)
			elif _frames == WAIT + 80:
				_shot("minimap_corner")
				_main.get("_minimap_view").set_expanded(true)
				_phase = 1
				_frames = 0
		1:
			if _frames >= 25:
				_shot("minimap_expanded")
				_main.get("_minimap_view").set_expanded(false)
				# Park next to a zombie so red dots show on the corner map.
				var z0: Vector3 = _main.get_node("Zombies").living_zombies()[0].global_position
				_main.player.global_position = z0 + Vector3(6, 0, 0)
				_phase = 2
				_frames = 0
		2:
			if _frames >= 40:
				_shot("minimap_zombies")
				print("MSHOT done")
				quit(0)
				return true
	return false
