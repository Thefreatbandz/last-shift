extends SceneTree
## Field-report verification shots: night street with the new lighting
## (ambient lift + streetlight pools + porch light + barrel fires) and a
## daytime detail shot (corpse with dimmer glow ring, ground patches).
## Also used to hunt the blue vertical line from Tbandz's night screenshot.
## Usage: xvfb-run -a godot --path . --script res://tests/fieldreport_shots.gd

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		var stub := Node.new()
		stub.name = "Sound"
		stub.set_script(load("res://tests/sound_stub.gd"))
		root.add_child(stub)
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 30:
		_night_setup()
	elif _frames == 110:
		DirAccess.make_dir_recursive_absolute(OUT)
		var img := root.get_texture().get_image()
		img.save_png(OUT + "/fieldreport_night.png")
		print("FRSHOT saved fieldreport_night.png")
		_day_setup()
	elif _frames == 170:
		var img2 := root.get_texture().get_image()
		img2.save_png(OUT + "/fieldreport_day.png")
		print("FRSHOT saved fieldreport_day.png")
		quit(0)
		return true
	return false


func _night_setup() -> void:
	var tm = _main.get_node("TimeManager")
	tm.call("set_time", 0.0) # midnight
	var nb = _main.get_node("Neighborhood")
	var spot: Node3D = null
	var stack: Array = [nb]
	while not stack.is_empty() and spot == null:
		var n: Node = stack.pop_back()
		if n is SpotLight3D:
			spot = n
		for ch in n.get_children():
			stack.append(ch)
	if spot != null:
		var p: Vector3 = spot.global_position
		p.y = 0.2
		_main.player.global_position = p + Vector3(4.5, 0, 4.5)
	var cam = _main.get_node("CameraRig")
	if cam.has_method("snap"):
		cam.call("snap")


func _day_setup() -> void:
	var tm = _main.get_node("TimeManager")
	tm.call("set_time", 12.0) # noon
	# Stand near a corpse container: shows the dimmer glow ring + patches.
	var loot = _main.get_node("Loot")
	var corpse: Node3D = null
	for lc in loot.call("get_containers"):
		if String(lc.get("kind")) == "corpse":
			corpse = lc
			break
	if corpse != null:
		var p: Vector3 = corpse.global_position
		p.y = 0.2
		_main.player.global_position = p + Vector3(4.0, 0, 4.0)
	var cam = _main.get_node("CameraRig")
	if cam.has_method("snap"):
		cam.call("snap")
