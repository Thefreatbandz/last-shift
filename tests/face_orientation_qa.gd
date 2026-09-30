extends SceneTree
## Face-orientation QA: verifies the zombie face features sit on the front
## of the head and stay there (no animation residue twists the head), plus
## related orientation-residue audits for player + Brute.
## Logic checks run headless; set RENDER=1 with xvfb-run for screenshots.
##   godot --headless --path . --script res://tests/face_orientation_qa.gd
##   xvfb-run -a godot --path . --script res://tests/face_orientation_qa.gd
## Grep the output for SCRIPT ERROR separately.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"
const RENDER := false # flipped to true by the render pass via --script + env

var _booted := false
var _frames := 0
var _ok := true
var _checks := 0
var _render_nodes: Array = []


func _chk(name: String, cond: bool, detail := "") -> void:
	_checks += 1
	if cond:
		print("FACEQA pass: ", name)
	else:
		_ok = false
		print("FACEQA FAIL: ", name, " ", detail)


func _force_twitch(z: Node) -> void:
	# Freeze a head-snap twitch mid-flight, as if the zombie just left idle.
	z.set("_twitch_kind", 1)
	z.set("_twitch_dur", 0.5)
	z.set("_twitch_el", 0.22)
	z.set("_twitch_dir", 1.0)
	z.set("_twitch_prev", 0.0)
	z.set("_twitch_t", 999.0)


func _head_yaw(z: Node) -> float:
	return (z.get("_head") as Node3D).rotation.y


func _logic_checks() -> void:
	var dt := 1.0 / 60.0
	# A. Twitch frozen mid-flight, then SHAMBLE: head yaw must return to 0.
	var z: Node = ZombieVisual.new()
	root.add_child(z)
	_force_twitch(z)
	for i in 15: # idle advances the twitch halfway (head visibly twisted)
		z.tick(dt, 0.0, false)
	var twisted: float = _head_yaw(z)
	_chk("twitch twists head in idle (sanity)", absf(twisted) > 0.05,
		"yaw=" + str(twisted))
	for i in 180: # chase: previously the twitch froze here forever
		z.tick(dt, 3.0, true)
	_chk("head yaw returns to 0 after shamble", absf(_head_yaw(z)) < 0.01,
		"yaw=" + str(_head_yaw(z)))
	# B. Same via LUNGE.
	_force_twitch(z)
	for i in 15:
		z.tick(dt, 0.0, false)
	z.play_lunge()
	for i in 60:
		z.tick(dt, 0.0, true)
	for i in 60:
		z.tick(dt, 0.0, false)
	_chk("head yaw returns to 0 after lunge", absf(_head_yaw(z)) < 0.01,
		"yaw=" + str(_head_yaw(z)))
	# C. Same via DEATH (corpses kept the twisted head before).
	_force_twitch(z)
	for i in 15:
		z.tick(dt, 0.0, false)
	z.play_death()
	for i in 90:
		z.tick_dead(dt)
	_chk("head yaw returns to 0 on corpse", absf(_head_yaw(z)) < 0.01,
		"yaw=" + str(_head_yaw(z)))
	z.queue_free()
	# D. Flinch must not permanently shove the body backward.
	var z2: Node = ZombieVisual.new()
	root.add_child(z2)
	z2.play_hit_reaction(Vector3.ZERO)
	for i in 60:
		z2.tick(dt, 0.0, false)
	var pz: float = (z2.get("_body") as Node3D).position.z
	_chk("flinch body offset relaxes to 0", absf(pz) < 0.01, "z=" + str(pz))
	z2.queue_free()
	# E. Brute: no duplicated meshes in the hit-flash list.
	var b: Node = ZombieVisual.new()
	root.add_child(b)
	(b as ZombieVisual).set_brute()
	var meshes: Array = b.get("_meshes")
	var seen := {}
	var dups := 0
	for m in meshes:
		if seen.has(m):
			dups += 1
		seen[m] = true
	_chk("brute hit-flash list has no duplicates", dups == 0,
		"dups=" + str(dups) + " total=" + str(meshes.size()))
	b.queue_free()
	# F. Player: interrupting the door-push must not stick the hip offset.
	var p: Node = PlayerVisual.new()
	root.add_child(p)
	p.play_door_push()
	for i in 20:
		p.tick(dt, 0.0, false)
	p.play_hurt_flinch() # interrupts the door push mid-envelope
	for i in 60:
		p.tick(dt, 0.0, false)
	var ppz: float = (p.get("_body") as Node3D).position.z
	_chk("player hip offset cleared after action interrupt", absf(ppz) < 0.001,
		"z=" + str(ppz))
	p.queue_free()
	print("FACEQA_LOGIC ok=", _ok, " checks=", _checks)


func _render_setup() -> Array:
	# Camera + lights + three subjects facing the camera (front = -Z, so
	# rotate PI to face +Z where the camera sits).
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.2, 1.35, 3.4)
	root.add_child(cam)
	cam.look_at(Vector3(0.1, 1.05, 0.0))
	cam.make_current()
	var walker: Node = ZombieVisual.new()
	walker.position = Vector3(-1.1, 0, 0)
	walker.rotation.y = PI
	root.add_child(walker)
	var brute: Node = ZombieVisual.new()
	brute.position = Vector3(0.1, 0, 0)
	brute.rotation.y = PI
	root.add_child(brute) # add first: set_brute needs _ready done
	(brute as ZombieVisual).set_brute()
	var player: Node = PlayerVisual.new()
	player.position = Vector3(1.3, 0, 0)
	player.rotation.y = PI
	root.add_child(player)
	return [walker, brute, player, env, sun, cam]


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("FACEQA shot saved: ", name)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_logic_checks()
		if not RENDER:
			print("FACEQA_RESULT ok=", _ok)
			quit(0 if _ok else 1)
			return true
		_render_nodes = _render_setup()
		return false
	_frames += 1
	if RENDER and _frames == 40:
		_shot("face_front_check")
		for n in _render_nodes:
			(n as Node).queue_free()
		_render_nodes.clear()
	if RENDER and _frames == 46:
		print("FACEQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false
