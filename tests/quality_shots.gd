extends SceneTree
## Quality-pass screenshots (Tbandz: "more details and a lighter night"):
##   1. quality_night_street.png — midnight street: readable moonlit detail,
##      lamp pools, and a zombie silhouette in frame.
##   2. quality_day_detail.png — daytime dressing/trim detail near buildings.
## Usage: xvfb-run -a godot --path . --script res://tests/quality_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/quality_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _nb: Node
var _tm: Node


func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("QUALITYSHOT saved ", n)


func _lamp_spots() -> Array:
	var spots: Array = []
	var stack: Array = [_nb]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SpotLight3D:
			spots.append((n as Node3D).global_position)
		for ch in n.get_children():
			stack.append(ch)
	return spots


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_tm = _main.get_node("TimeManager")
		return false
	_frames += 1
	match _phase:
		0: # midnight street with lamp pools + zombie silhouette
			if _frames == 20:
				_tm.call("set_time", 0.5) # deep night
				var lamps := _lamp_spots()
				var lp: Vector3 = lamps[0] if lamps.size() > 0 else Vector3(0, 0, 10)
				_main.player.global_position = lp + Vector3(6.0, 0, 6.0)
				# A zombie in frame for its silhouette — 10m out so it
				# doesn't reach the player and trigger the damage flash.
				var zm: Node = _main.get_node("Zombies")
				var zs: Array = zm.get("zombies")
				if zs.size() > 0:
					var z: Node3D = zs[0]
					z.global_position = lp + Vector3(-7.0, 0, 3.0)
			elif _frames == 80:
				_shot("quality_night_street.png")
				_phase = 1
				_frames = 0
		1: # daytime detail: house front with new trim (shutters, awnings,
			# window boxes) + yard dressing, in the real gameplay view
			if _frames == 20:
				_tm.call("set_time", 11.0)
				var h: Dictionary = (_nb.get("houses") as Array)[0]
				var hp: Vector3 = h["pos"]
				var face := float(h["face"])
				var hd := float(h["d"])
				_main.player.global_position = hp + Vector3(1.5, 0, face * (hd * 0.5 + 7.0))
			elif _frames == 70:
				_shot("quality_day_detail.png")
				print("QUALITYSHOT done")
				quit(0)
				return true
	return false
