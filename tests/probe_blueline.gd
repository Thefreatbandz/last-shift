extends SceneTree
## Diagnostic: project streetlight pole positions to screen space to
## identify the blue vertical bar in the night screenshot.
## Usage: xvfb-run -a godot --path . --script res://tests/probe_blueline.gd

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
		var tm = _main.get_node("TimeManager")
		tm.call("set_time", 0.0)
		var nb = _main.get_node("Neighborhood")
		var pole_mat: Material = nb.get("_m_pole")
		# Same player placement as the fieldreport night shot.
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
	elif _frames == 110:
		var nb2 = _main.get_node("Neighborhood")
		var pole_mat2: Material = nb2.get("_m_pole")
		var cam3d: Camera3D = _main.get_node("CameraRig/Camera3D")
		var pp: Vector3 = _main.player.global_position
		print("BLUELINE player=", pp)
		var stack2: Array = [nb2]
		var count := 0
		while not stack2.is_empty() and count < 100:
			var n2: Node = stack2.pop_back()
			if n2 is MeshInstance3D:
				var mi2 := n2 as MeshInstance3D
				var wp2: Vector3 = mi2.global_position
				if wp2.x > -2.0 and wp2.x < 1.0 and wp2.z > 70.0 and wp2.z < 73.0:
					var mat2: Material = mi2.get("material_override")
					var mcol := Color.BLACK
					if mat2 != null and mat2 is StandardMaterial3D:
						mcol = (mat2 as StandardMaterial3D).albedo_color
					print("BLUELINE mesh=", mi2.mesh.get_class(),
						" mat_color=", mcol, " world=", wp2)
					count += 1
			for ch in n2.get_children():
				stack2.append(ch)
		quit(0)
		return true
	return false
