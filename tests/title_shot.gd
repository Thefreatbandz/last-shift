extends SceneTree
## Screenshot the title screen (with the new apocalypse backdrop).

var _booted := false
var _frames := 0


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", -1)
		var ps := load("res://scenes/main.tscn") as PackedScene
		var m := ps.instantiate()
		root.add_child(m)
		current_scene = m
		return false
	_frames += 1
	if _frames == 120:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/title_new.png")
		print("TITLE shot saved")
		quit(0)
		return true
	return false
