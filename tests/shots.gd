extends SceneTree
## Captures QA screenshots under Xvfb (software GL is ~0.7fps — be patient).
##   1. title screen (no seed)
##   2. street view, seed A (48392017)
##   3. pause menu with the seed label (seed A)
##   4. street view, seed B (98765432) — visibly different neighborhood
## Usage: xvfb-run -a godot --path . --script res://tests/shots.gd
## Writes to /tmp/shots/*.png.

var _phase := 0
var _frames := 0
var _booted := false
var _main: Node
const OUT := "/home/hatch/workspace/last-shift/qa_shots/seeded"
const WAIT := 40


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("SHOT saved ", name)


func _boot(seed: int = -1) -> void:
	for c in root.get_children():
		if c.name == &"Main":
			root.remove_child(c)
			c.free()
	root.get_node("RunState").set("world_seed", seed)
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	_main.name = &"Main"
	root.add_child(_main)
	current_scene = _main
	print("SHOT booted seed=", seed)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot() # title: no seed
		return false
	_frames += 1
	match _phase:
		0:
			if _frames >= WAIT:
				_shot("1_title")
				_phase = 1
				_frames = 0
				_boot(48392017)
		1:
			if _frames >= WAIT:
				_shot("2_street_seedA")
				_main.hud.show_pause(48392017)
				_phase = 2
				_frames = 0
		2:
			if _frames >= WAIT:
				_shot("3_pause_seedA")
				_phase = 3
				_frames = 0
				_boot(98765432)
		3:
			if _frames >= WAIT:
				_shot("4_street_seedB")
				print("SHOTS_DONE")
				quit(0)
				return true
	return false
