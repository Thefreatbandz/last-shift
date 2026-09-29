extends SceneTree
## Regression: hit reactions must push bodies AWAY from each other, and the
## bat swing must be arms-driven with the body planted (no lunge/pitch).
## Sign convention (verified empirically): for a -Z-facing character,
## POSITIVE rotation.x rocks the torso top toward +Z = BACKWARD.
##   godot --headless --path . --script res://tests/hit_direction_qa.gd

var _ok := true


func _check(name: String, cond: bool) -> void:
	print("HITQA ", name, " ", "PASS" if cond else "FAIL")
	if not cond:
		_ok = false


func _process(_delta: float) -> bool:
	_zombie_flinch()
	_player_hurt()
	_player_attack()
	print("HITQA_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


func _zombie_flinch() -> void:
	var z: Node = ZombieVisual.new()
	root.add_child(z) # _ready builds the rig
	# Base shamble pose: hunched at 0.34. Driven through tick() so the base
	# pose runs before the flinch overlay each frame (the real frame flow).
	var body: Node3D = z.get("_body")
	var head: Node3D = z.get("_head")
	z.play_hit_reaction(Vector3.ZERO)
	for i in 9: # t=0.5 -> envelope peak f=1
		z.tick(1.0 / 60.0, 2.0, true)
	_check("zombie_torso_rocks_back", body.rotation.x > 0.34)
	_check("zombie_head_snaps_back", head.rotation.x > 0.18)
	# Shove must still push the zombie away (+Z = behind a -Z facer).
	_check("zombie_shoved_back", body.position.z > 0.0)
	# Run the envelope to completion: no accumulation, no residue.
	for i in 30:
		z.tick(1.0 / 60.0, 2.0, true)
	_check("zombie_no_residue", absf(body.rotation.x - 0.34) < 0.02
			and absf(body.position.z) < 0.01)
	# A second hit mid-flight must not stack: re-trigger at peak and finish.
	z.play_hit_reaction(Vector3.ZERO)
	for i in 9:
		z.tick(1.0 / 60.0, 2.0, true)
	z.play_hit_reaction(Vector3.ZERO)
	for i in 40:
		z.tick(1.0 / 60.0, 2.0, true)
	_check("zombie_hit_no_stack", absf(body.rotation.x - 0.34) < 0.02)
	z.free()


func _player_hurt() -> void:
	var v: Node = PlayerVisual.new()
	root.add_child(v)
	var body: Node3D = v.get("_body")
	v.play_hurt_flinch()
	for i in 13: # t~=0.48 -> envelope peak e~=1
		v.tick(1.0 / 60.0, 0.0, false)
	_check("player_staggers_back", body.rotation.x > 0.05)
	# Full envelope: the overlay must unwind itself exactly (no residue).
	for i in 30:
		v.tick(1.0 / 60.0, 0.0, false)
	_check("player_hurt_no_residue", absf(body.rotation.x - -0.02) < 0.03
			and v.get("_action") == "")
	# Interrupting hurt with a new action crossfades over 0.2s (no pop),
	# then settles clean.
	v.play_hurt_flinch()
	for i in 13:
		v.tick(1.0 / 60.0, 0.0, false)
	var before: float = body.rotation.x
	v.play_attack(0.34)
	v.tick(1.0 / 60.0, 0.0, false)
	_check("hurt_interrupt_crossfade", absf(body.rotation.x - before) < 0.08)
	for i in 40:
		v.tick(1.0 / 60.0, 0.0, false)
	_check("hurt_interrupt_clean", absf(body.rotation.x - -0.02) < 0.05
			and v.get("_action") == "")
	v.free()


func _player_attack() -> void:
	var v: Node = PlayerVisual.new()
	root.add_child(v)
	var pivot := Node3D.new()
	v.attach_weapon(pivot)
	_check("bat_in_right_hand", pivot.get_parent() == v.get("_fore_r"))
	var body: Node3D = v.get("_body")
	var arm_r: Node3D = v.get("_arm_r")
	var arm_l: Node3D = v.get("_arm_l")
	v.play_attack(0.34)
	for i in 5: # t~=0.245: wind-up peak, both arms overhead
		v.tick(1.0 / 60.0, 0.0, false)
	_check("windup_arms_overhead", arm_r.rotation.x > 2.5)
	var tip_wind: Vector3 = v.bat_tip_body()
	_check("windup_bat_above_head", tip_wind.y > 2.0)
	_check("offhand_engaged", absf(arm_l.rotation.x) > 0.3)
	for i in 4: # t~=0.44: mid-strike, the hit frame
		v.tick(1.0 / 60.0, 0.0, false)
	_check("strike_arms_come_down", arm_r.rotation.x < 1.4)
	var tip_hit: Vector3 = v.bat_tip_body()
	_check("downward_strike_arc", tip_hit.y < tip_wind.y - 0.4)
	_check("contact_in_front", tip_hit.z < -0.3)
	_check("contact_height", tip_hit.y > 0.4 and tip_hit.y < 1.7)
	# Wrist whip drove the bat off its rest orientation mid-swing.
	_check("bat_whipped", absf(pivot.rotation.x - v.get("_weapon_rest_x")) > 0.15)
	# Body stays planted: no lunge translation, no forward pitch (idle base
	# leans the torso at -0.02; the swing adds no pitch of its own).
	_check("no_lunge_z", absf(body.position.z) < 0.001)
	_check("no_lunge_x", absf(body.position.x) < 0.001)
	_check("no_forward_pitch", absf(body.rotation.x - -0.02) < 0.06)
	# The off hand could reach the handle through the whole swing: the
	# longest shoulder->grip distance stayed inside the 0.68 arm reach.
	_check("twohand_reach_ok", v.get("_max_grip_d") <= 0.68)
	# After the full action everything settles back to rest.
	for i in 30: # finish the envelope
		v.tick(1.0 / 60.0, 0.0, false)
	_check("action_settles", v.get("_action") == "")
	_check("bat_restored", absf(pivot.rotation.x - v.get("_weapon_rest_x")) < 0.001)
	_check("twist_reset", absf(body.rotation.y) < 0.001)
	_check("offhand_released", absf(arm_l.rotation.x) < 0.05)
	v.free()
