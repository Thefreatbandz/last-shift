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
	# Base shamble pose: hunched at 0.34, head at 0.18.
	var body: Node3D = z.get("_body")
	var head: Node3D = z.get("_head")
	body.rotation.x = 0.34
	head.rotation.x = 0.18
	z.play_hit_reaction(Vector3.ZERO)
	z._apply_flinch(0.15) # half of FLINCH_TIME -> envelope peak f=1
	_check("zombie_torso_rocks_back", body.rotation.x > 0.34)
	_check("zombie_head_snaps_back", head.rotation.x > 0.18)
	# Shove must still push the zombie away (+Z = behind a -Z facer).
	_check("zombie_shoved_back", body.position.z > 0.0)
	# Run the envelope to completion: no accumulation, no residue.
	for i in 6:
		z._apply_flinch(0.05)
	_check("zombie_no_residue", absf(body.rotation.x - 0.34) < 0.01
			and absf(head.rotation.x - 0.18) < 0.01
			and absf(body.position.z) < 0.001)
	# A second hit mid-flight must not stack: re-trigger at peak and finish.
	z.play_hit_reaction(Vector3.ZERO)
	z._apply_flinch(0.15)
	z.play_hit_reaction(Vector3.ZERO)
	for i in 6:
		z._apply_flinch(0.05)
	_check("zombie_hit_no_stack", absf(body.rotation.x - 0.34) < 0.01)
	z.free()


func _player_hurt() -> void:
	var v: Node = PlayerVisual.new()
	root.add_child(v)
	var body: Node3D = v.get("_body")
	body.rotation.x = -0.02 # idle base
	v.play_hurt_flinch()
	v._apply_action(0.225) # half of 0.45 -> envelope peak e=1
	_check("player_staggers_back", body.rotation.x > 0.0)
	# Full envelope: the overlay must unwind itself exactly (no residue).
	for i in 4:
		v._apply_action(0.1)
	_check("player_hurt_no_residue", absf(body.rotation.x - -0.02) < 0.02
			and v.get("_action") == "")
	# Interrupting hurt with a new action must not leave residue either.
	v.play_hurt_flinch()
	v._apply_action(0.225)
	v.play_attack(0.34)
	_check("hurt_interrupt_clean", absf(body.rotation.x - -0.02) < 0.02)
	for i in 4:
		v._apply_action(0.1)
	v.free()


func _player_attack() -> void:
	var v: Node = PlayerVisual.new()
	root.add_child(v)
	var pivot := Node3D.new()
	v.attach_weapon(pivot)
	_check("bat_in_right_hand", pivot.get_parent() == v.get("_fore_r"))
	var body: Node3D = v.get("_body")
	var arm_r: Node3D = v.get("_arm_r")
	v.play_attack(0.34)
	v._apply_action(0.34 * 0.62) # t=0.62: sweep complete
	# Arm drove the swing forward (positive = toward -Z/front).
	_check("arm_swings_weapon", arm_r.rotation.x > 0.3)
	# Body stays planted: no lunge translation, no forward pitch.
	_check("no_lunge_z", absf(body.position.z) < 0.001)
	_check("no_lunge_x", absf(body.position.x) < 0.001)
	_check("no_forward_pitch", absf(body.rotation.x) < 0.05)
	# Wrist snap moved the bat off its rest orientation mid-swing.
	_check("bat_swept", absf(pivot.rotation.x - v.get("_weapon_rest_x")) > 0.05)
	# After the full action everything settles back to rest.
	v._apply_action(0.34) # finish the envelope
	_check("action_settles", v.get("_action") == "")
	_check("bat_restored", absf(pivot.rotation.x - v.get("_weapon_rest_x")) < 0.001)
	_check("twist_reset", absf(body.rotation.y) < 0.001)
	v.free()
