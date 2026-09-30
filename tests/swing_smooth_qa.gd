extends SceneTree
## Smoothness QA for the two-handed overhead swing + physics/animation pass.
##
## Part 1 (standalone nodes, deterministic): pose-channel jump bounds across
## action transitions and interrupts — the overlay mixer must make every
## interrupt a crossfade, never a pop.
## Part 2 (player stepped manually in empty space; zombie in the booted
## scene): velocity-change bounds — acceleration/deceleration ramps, no
## instant velocity writes.
## Usage: godot --headless --path . --script res://tests/swing_smooth_qa.gd

var _ok := true
var _pivot: Node3D


func _check(name: String, cond: bool) -> void:
	if not cond:
		_ok = false
	print("SMOOTHQA ", name, " ", "PASS" if cond else "FAIL")


func _process(_delta: float) -> bool:
	_player_pose_no_pop()
	_zombie_pose_no_pop()
	_player_velocity_bounds()
	_zombie_velocity_bounds()
	print("SMOOTHQA_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


# ---------------------------------------------------------------- player pose

func _sample_player(v: Node) -> Array:
	var body: Node3D = v.get("_body")
	return [
		body.position.y, body.position.z,
		body.rotation.x, body.rotation.y, body.rotation.z,
		v.get("_leg_l").rotation.x, v.get("_leg_r").rotation.x,
		v.get("_shin_l").rotation.x, v.get("_shin_r").rotation.x,
		v.get("_arm_l").rotation.x, v.get("_arm_r").rotation.x,
		v.get("_fore_l").rotation.x, v.get("_fore_r").rotation.x,
		v.get("_head").rotation.x, v.get("_head").rotation.z,
		v.get("_arm_l").rotation.z, v.get("_arm_r").rotation.z,
		_pivot.rotation.x, _pivot.rotation.z,
	]


func _maxdiff(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, absf(float(a[i]) - float(b[i])))
	return w


func _player_pose_no_pop() -> void:
	var v: Node = PlayerVisual.new()
	root.add_child(v)
	_pivot = Node3D.new()
	v.attach_weapon(_pivot)
	# Brutal interrupt sequence: attack -> hurt -> attack -> kneel ->
	# pickup -> door, all mid-envelope.
	var worst := 0.0
	var prev := _sample_player(v)
	for frame in 150:
		match frame:
			0:
				v.play_attack(0.34)
			10:
				v.play_hurt_flinch()
			20:
				v.play_attack(0.34)
			45:
				v.play_kneel(1.0)
			80:
				v.play_pickup()
			105:
				v.play_door_push()
		v.tick(1.0 / 60.0, 0.0, false)
		var cur := _sample_player(v)
		worst = maxf(worst, _maxdiff(prev, cur))
		prev = cur
	# The overhead chop itself is fast (up to ~0.9 rad/frame at the wrist);
	# anything above 1.2 rad in one frame is a snap, not animation.
	_check("player_no_pose_pop", worst < 1.2)
	# Interrupt continuity, measured precisely: the frame right after an
	# interrupt must match the frame before it (residue crossfade).
	v.play_attack(0.34)
	for i in 12:
		v.tick(1.0 / 60.0, 0.0, false)
	var before := _sample_player(v)
	v.play_hurt_flinch() # interrupt mid-swing
	v.tick(1.0 / 60.0, 0.0, false)
	var after := _sample_player(v)
	_check("player_interrupt_crossfade", _maxdiff(before, after) < 0.08)
	v.free()


# ---------------------------------------------------------------- zombie pose

func _sample_zombie(z: Node) -> Array:
	var body: Node3D = z.get("_body")
	return [
		body.rotation.x, body.rotation.z, body.position.z,
		z.get("_head").rotation.x,
		z.get("_arm_l").rotation.x, z.get("_arm_r").rotation.x,
		z.get("_arm_l").rotation.z, z.get("_arm_r").rotation.z,
		z.get("_leg_l").rotation.x, z.get("_leg_r").rotation.x,
	]


func _zombie_pose_no_pop() -> void:
	var z: Node = ZombieVisual.new()
	root.add_child(z)
	# Flinch interrupt continuity: re-hit at the envelope peak.
	z.play_hit_reaction(Vector3.ZERO)
	for i in 10:
		z.tick(1.0 / 60.0, 2.0, true)
	var before := _sample_zombie(z)
	z.play_hit_reaction(Vector3.ZERO)
	z.tick(1.0 / 60.0, 2.0, true)
	var after := _sample_zombie(z)
	_check("zombie_flinch_crossfade", _maxdiff(before, after) < 0.10)
	# Lunge -> shamble: the shamble phase froze during the lunge, so the
	# exit must crossfade instead of snapping the legs.
	for i in 30:
		z.tick(1.0 / 60.0, 2.0, true)
	z.play_lunge()
	var worst := 0.0
	var prev := _sample_zombie(z)
	for i in 45: # 0.38s lunge + 0.37s of exit blend
		z.tick(1.0 / 60.0, 2.0, true)
		var cur := _sample_zombie(z)
		worst = maxf(worst, _maxdiff(prev, cur))
		prev = cur
	_check("zombie_lunge_exit_blend", worst < 0.6)
	z.free()


# ------------------------------------------------------- player velocity ramp

func _player_velocity_bounds() -> void:
	# Standalone player in empty space: no walls, no floor, no map
	# dependence. Engine physics disabled; stepped manually at 60 Hz.
	# player.gd is loaded dynamically (see the note at the top of this file).
	# Input actions are created by input_setup.gd at runtime in the real
	# game; the --script harness has no scene, so register them here.
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var PlayerScript: GDScript = load("res://scripts/player/player.gd")
	var RigScript: GDScript = load("res://scripts/world/camera_rig.gd")
	var p: Node = PlayerScript.new()
	var vis := PlayerVisual.new()
	vis.name = &"Visual"
	p.add_child(vis)
	root.add_child(p)
	var rig: Node = RigScript.new()
	rig.set("yaw", 0.0)
	p.set("camera_rig", rig)
	p.set_physics_process(false)
	for i in 10:
		p.call("_physics_process", 1.0 / 60.0)
	Input.action_press("move_forward")
	var worst := 0.0
	var prev := Vector2(p.get("velocity").x, p.get("velocity").z)
	for i in 90:
		p.call("_physics_process", 1.0 / 60.0)
		var cur := Vector2(p.get("velocity").x, p.get("velocity").z)
		worst = maxf(worst, (cur - prev).length())
		prev = cur
	var cruise := prev.length()
	Input.action_release("move_forward")
	var worst_stop := 0.0
	for i in 90:
		p.call("_physics_process", 1.0 / 60.0)
		var cur := Vector2(p.get("velocity").x, p.get("velocity").z)
		worst_stop = maxf(worst_stop, (cur - prev).length())
		prev = cur
	# Damped accel (k=1-exp(-14/60)=0.21): first step jumps ~1.1 m/s at most.
	# A hard velocity write would jump the full 5.2 m/s in one step.
	_check("player_accel_bounded", worst < 2.0)
	_check("player_reaches_run_speed", cruise > 4.0 and cruise < 5.4)
	_check("player_decel_bounded", worst_stop < 2.0)
	_check("player_stops", prev.length() < 0.5)
	p.free()
	rig.free()


# ------------------------------------------------------- zombie velocity ramp

func _zombie_velocity_bounds() -> void:
	for c in root.get_children():
		if c.name == &"Main":
			root.remove_child(c)
			c.free()
	root.get_node("RunState").set("world_seed", 48392017)
	var ps := load("res://scenes/main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	main.name = &"Main"
	root.add_child(main)
	current_scene = main
	main.get_node("TimeManager").set("time_hours", 10.0)
	var p: Node = main.get_node("Player")
	var zs: Array = main.get_node("Zombies").living_zombies()
	_check("zombie_present", not zs.is_empty())
	if zs.is_empty():
		return
	var z: Node = zs[0]
	z.set_physics_process(false)
	# 8 m in front of the player, on the floor, chasing.
	z.set("global_position", p.get("global_position") + Vector3(0, 0.5, 8.0))
	z.set("velocity", Vector3.ZERO)
	z.set("state", 2) # CHASE
	z.set("_visible", true)
	z.set("_lose_t", 0.0)
	var worst := 0.0
	var prev := Vector2.ZERO
	for i in 100:
		z._physics_process(1.0 / 60.0)
		var cur := Vector2(z.get("velocity").x, z.get("velocity").z)
		worst = maxf(worst, (cur - prev).length())
		prev = cur
	var chase_speed := prev.length()
	# Damped steering (k=1-exp(-8/60)=0.12): steps change ~0.3 m/s; a hard
	# write would jump the full 2.7 m/s chase speed in one step.
	_check("zombie_steer_bounded", worst < 2.0)
	_check("zombie_reaches_chase_speed", chase_speed > 1.5 and chase_speed < 4.0)
	# ATTACK stop must ease out, not zero in one frame. Park the zombie
	# inside attack range so it stays in ATTACK (beyond 2.38 m it would
	# correctly re-chase), and pin the attack cooldown so the test player
	# takes no damage.
	z.set("global_position", p.get("global_position") + Vector3(0, 0.0, 1.2))
	z.set("state", 3) # ATTACK
	z.set("_attack_cd", 999.0)
	var worst_stop := 0.0
	for i in 40:
		z._physics_process(1.0 / 60.0)
		var cur := Vector2(z.get("velocity").x, z.get("velocity").z)
		worst_stop = maxf(worst_stop, (cur - prev).length())
		prev = cur
	_check("zombie_attack_stop_eased", worst_stop < 1.0)
	_check("zombie_attack_stops", prev.length() < 0.5)
