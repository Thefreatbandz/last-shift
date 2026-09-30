extends SceneTree
## QA for the arms-driven zombie swipe (Tbandz: "the zombie swings and kinda
## swung his body"). Drives ZombieVisual.play_lunge() through its 0.38s
## envelope and asserts the attack SHAPE:
##  - both arms coil UP (wind-up anticipation) then snap DOWN past rest,
##  - the torso holds its base hunch (no forward rock, no twist),
##  - the body never drifts (no forward/lateral motion; only a small
##    vertical dip as it drops into the swipe),
##  - the legs stay planted, the head moves with the strike but recovers.
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
	var min_arm_l := base_arm_l
	var min_arm_r := base_arm_r
	var max_arm_l := base_arm_l
	var max_arm_r := base_arm_r
	var d_body_rx := 0.0
	var d_body_rz := 0.0
	var d_body_px := 0.0
	var d_body_pz := 0.0
	var max_dip := 0.0
	var d_leg_l := 0.0
	var d_leg_r := 0.0
	var end_head := 0.18
	# Walk the full 0.38s envelope at 60fps.
	for _i in 24:
		zv.tick(1.0 / 60.0, 0.0, false)
		min_arm_l = minf(min_arm_l, arm_l.rotation.x)
		min_arm_r = minf(min_arm_r, arm_r.rotation.x)
		max_arm_l = maxf(max_arm_l, arm_l.rotation.x)
		max_arm_r = maxf(max_arm_r, arm_r.rotation.x)
		d_body_rx = maxf(d_body_rx, absf(body.rotation.x - 0.34))
		d_body_rz = maxf(d_body_rz, absf(body.rotation.z))
		d_body_px = maxf(d_body_px, absf(body.position.x))
		d_body_pz = maxf(d_body_pz, absf(body.position.z))
		max_dip = maxf(max_dip, absf(body.position.y))
		d_leg_l = maxf(d_leg_l, absf(leg_l.rotation.x))
		d_leg_r = maxf(d_leg_r, absf(leg_r.rotation.x))
		end_head = head.rotation.x
	zv.free()

	ok = _check(tag + "_arms_wind_up", min_arm_l < base_arm_l - 0.5 \
		and min_arm_r < base_arm_r - 0.5, ok)
	ok = _check(tag + "_arms_strike_down", max_arm_l > base_arm_l + 0.3 \
		and max_arm_r > base_arm_r + 0.3, ok)
	ok = _check(tag + "_torso_no_rock", d_body_rx < 0.05, ok)
	ok = _check(tag + "_torso_no_twist", d_body_rz < 0.05, ok)
	ok = _check(tag + "_body_no_drift", d_body_px < 0.05 and d_body_pz < 0.05, ok)
	ok = _check(tag + "_body_dip_small", max_dip < 0.12, ok)
	ok = _check(tag + "_legs_planted", d_leg_l < 0.05 and d_leg_r < 0.05, ok)
	ok = _check(tag + "_head_recovers", absf(end_head - 0.18) < 0.1, ok)
	return ok
