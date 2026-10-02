extends SceneTree
## Zombie-upgrade screenshots (Tbandz visual QA):
##   1. zombie_walker_closeup.png — upgraded walker, daylight, mid-shamble.
##   2. zombie_brute.png — brute, daylight, bulkier silhouette.
##   3. zombie_night_eyes.png — night: eye glow reads in the dark.
## Usage: xvfb-run -a godot --path . --script res://tests/zombie_upgrade_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _zv: Node
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D


func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + n + ".png")
	print("ZSHOT saved ", n)


func _make_stage() -> void:
	var world := WorldEnvironment.new()
	_env = Environment.new()
	world.environment = _env
	root.add_child(world)
	_sun = DirectionalLight3D.new()
	root.add_child(_sun)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.15, 0.13)
	ground.material_override = gm
	root.add_child(ground)
	var ZV = load("res://scripts/zombie/zombie_visual.gd")
	_zv = ZV.new()
	_zv.rotation.y = PI # face the camera (model faces -z)
	_zv.set_target_yaw(PI) # tick() eases rotation.y toward this; keep it
	root.add_child(_zv)


func _day() -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.62, 0.70)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.75, 0.78, 0.82)
	_env.ambient_light_energy = 1.0
	_sun.light_energy = 1.3
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.rotation = Vector3(-0.7, 0.5, 0.0)


func _night() -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.015, 0.02, 0.04)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.25, 0.30, 0.45)
	_env.ambient_light_energy = 0.35
	_sun.light_energy = 0.25
	_sun.light_color = Color(0.6, 0.7, 0.95)
	_sun.rotation = Vector3(-0.9, -0.4, 0.0)


func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		_make_stage()
		return false
	_frames += 1
	match _phase:
		0: # Walker close-up, daylight, mid-shamble.
			_day()
			_cam.position = Vector3(0.35, 1.2, 1.9)
			_cam.look_at(Vector3(0, 0.95, 0))
			_zv.tick(delta, 2.0, true)
			if _frames == 75:
				_shot("zombie_walker_closeup")
				_phase = 1
				_frames = 0
		1: # Brute, daylight.
			if _frames == 1:
				_zv.set_brute() # once: set_brute() adds gear meshes
			_cam.position = Vector3(0.5, 1.35, 2.4)
			_cam.look_at(Vector3(0, 1.0, 0))
			_zv.tick(delta, 2.0, true)
			if _frames == 75:
				_shot("zombie_brute")
				_phase = 2
				_frames = 0
		2: # Night: eye glow. Fresh walker (not the brute) so the face and
			# eyes read; the brute's helmet would hide them.
			if _frames == 1:
				_zv.free()
				var ZV2 = load("res://scripts/zombie/zombie_visual.gd")
				_zv = ZV2.new()
				_zv.rotation.y = PI
				_zv.set_target_yaw(PI)
				root.add_child(_zv)
			_night()
			_cam.position = Vector3(0.3, 1.15, 1.6)
			_cam.look_at(Vector3(0, 1.0, 0))
			_zv.tick(delta, 0.0, false)
			if _frames == 60:
				_shot("zombie_night_eyes")
				print("ZSHOTS done")
				quit(0)
				return true
	return false
