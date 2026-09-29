extends SceneTree
## QA for the arms-driven zombie swipe (Tbandz: "the zombie swings and kinda
## swung his body"). Drives ZombieVisual.play_lunge() through its 0.38s
## envelope and asserts:
##  - both arms move materially (claw swipe),
##  - the torso holds its base hunch (no forward rock, no twist),
##  - the body doesn't bob, the legs stay planted, the head stays put.
## Run: godot --headless --path . --script res://tests/swipe_qa.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var ok := true
	ok = _run_case("swipe", ok)
	print("SWIPEQA_RESULT ok=", ok)
	quit(0 if ok else 1)
	return true


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("SWIPEQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond


func _run_case(tag: String, ok: bool) -> bool:
	var zv: Node3D = ZombieVisual.new()
	root.add_child(zv)
	# Settle into the idle base pose.
	for _i in 30:
		zv.tick(1.0 / 60.0, 0.0, false)
	var body: Node3D = zv.get("_body")
	var arm_l: Node3D = zv.get("_arm_l")
	var arm_r: Node3D = zv.get("_arm_r")
	var leg_l: Node3D = zv.get("_leg_l")
	var leg_r: Node3D = zv.get("_leg_r")
	var head: Node3D = zv.get("_head")
	var base_arm_l := arm_l.rotation.x
	var base_arm_r := arm_r.rotation.x

	zv.play_lunge()
	var d_arm_l := 0.0
	var d_arm_r := 0.0
	var d_body_rx := 0.0
	var d_body_rz := 0.0
	var d_body_py := 0.0
	var d_leg_l := 0.0
	var d_leg_r := 0.0
	var d_head := 0.0
	# Walk the full 0.38s envelope at 60fps.
	for _i in 24:
		zv.tick(1.0 / 60.0, 0.0, false)
		d_arm_l = maxf(d_arm_l, absf(arm_l.rotation.x - base_arm_l))
		d_arm_r = maxf(d_arm_r, absf(arm_r.rotation.x - base_arm_r))
		d_body_rx = maxf(d_body_rx, absf(body.rotation.x - 0.34))
		d_body_rz = maxf(d_body_rz, absf(body.rotation.z))
		d_body_py = maxf(d_body_py, absf(body.position.y))
		d_leg_l = maxf(d_leg_l, absf(leg_l.rotation.x))
		d_leg_r = maxf(d_leg_r, absf(leg_r.rotation.x))
		d_head = maxf(d_head, absf(head.rotation.x - 0.18))
	zv.free()

	ok = _check(tag + "_arms_move_l", d_arm_l > 0.5, ok)
	ok = _check(tag + "_arms_move_r", d_arm_r > 0.5, ok)
	ok = _check(tag + "_torso_no_rock", d_body_rx < 0.05, ok)
	ok = _check(tag + "_torso_no_twist", d_body_rz < 0.05, ok)
	ok = _check(tag + "_body_no_bob", d_body_py < 0.05, ok)
	ok = _check(tag + "_legs_planted", d_leg_l < 0.05 and d_leg_r < 0.05, ok)
	ok = _check(tag + "_head_steady", d_head < 0.05, ok)
	return ok
