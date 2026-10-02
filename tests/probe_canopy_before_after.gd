extends SceneTree
## Before/after: house with nearest tree canopy, morning, roof on.
## Usage: xvfb-run -a godot --path . --script res://tests/probe_canopy_before_after.gd -- --shotseed=N --shotname=NAME

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _main: Node
var _nb: Node
var _tm: Node
var _seed := 48392017
var _name := "canopy_test"

func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("CSHOT saved ", n)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shotseed="):
				_seed = int(a.trim_prefix("--shotseed="))
			if a.begins_with("--shotname="):
				_name = a.trim_prefix("--shotname=")
		root.get_node("RunState").set("world_seed", _seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_tm = _main.get_node("TimeManager")
		return false
	_frames += 1
	if _frames == 40:
		_tm.call("set_time", 10.2)
		var spot := _nearest_tree_house()
		_main.player.global_position = spot
	elif _frames == 100:
		_shot(_name + ".png")
		quit(0)
		return true
	return false

func _nearest_tree_house() -> Vector3:
	var houses: Array = _nb.get("houses")
	var canopies: Array = []
	_collect(_nb, canopies)
	var best := Vector3.ZERO
	var best_d := 1e9
	for h in houses:
		var hp: Vector3 = (h as Dictionary)["pos"]
		var face := float((h as Dictionary)["face"])
		var d := float((h as Dictionary)["d"])
		for c in canopies:
			var dd := Vector2(c.x - hp.x, c.z - hp.z).length()
			if dd < best_d:
				best_d = dd
				best = hp + Vector3(0, 0.3, face * (d * 0.5 + 5.0))
	print("CSHOT nearest canopy dist=", snappedf(best_d, 0.1))
	return best

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m := c as MeshInstance3D
			if m.mesh is SphereMesh:
				var gs: Vector3 = m.global_transform.basis.get_scale()
				if (m.mesh as SphereMesh).radius * gs.x > 0.8:
					var gp: Vector3 = m.global_position
					if gp.y > 1.5 and gp.y < 6.0:
						out.append(gp)
		_collect(c, out)
