extends SceneTree
## QA for the zombie upgrade pass (Tbandz: "upgrade our zombies"):
##   1. Visual variety actually varies across spawns (walker + brute).
##   2. Walk-cycle phase advances with movement; brutes stomp heavier.
##   3. Attack lunge shows a wind-up telegraph BEFORE the 0.22s damage frame.
##   4. AI balance constants are byte-identical (no balance changes).
##   5. notice() head-snap fires without errors.
## Usage: xvfb-run -a godot --path . --script res://tests/zombie_upgrade_qa.gd

var _booted := false
var _failed := 0
var _passed := 0


func _check(n: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("ZOMBIEUPGRADE_QA FAIL: ", n)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_run()
		print("ZOMBIEUPGRADE_QA done passed=", _passed, " failed=", _failed)
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _run() -> void:
	# ZombieAI references the Sound autoload (not registered in bare
	# --script mode): stub it, then lazy-load the classes.
	var stub := Node.new()
	stub.name = "Sound"
	stub.set_script(load("res://tests/sound_stub.gd"))
	root.add_child(stub)
	var ZV = load("res://scripts/zombie/zombie_visual.gd")
	var ZA = load("res://scripts/zombie/zombie_ai.gd")

	# 1. Visual variety across spawns.
	var keys := {}
	var made := []
	for i in 16:
		var zv = ZV.new()
		root.add_child(zv) # _ready() builds the procedural model
		keys[zv.variant_key()] = true
		made.append(zv)
		if i % 4 == 3:
			zv.set_brute()
			_check("brute_flag_%d" % i, bool(zv.debug_pose()["is_brute"]))
			_check("brute_arms_thicker_%d" % i,
				(zv.get("_arm_l") as Node3D).scale.x > 1.2)
	_check("visual_variety", keys.size() >= 8)
	_check("variant_keys_nonempty", not keys.has(""))
	for zv in made:
		(zv as Node).free()

	# 2. Walk cycle advances; brute stomps heavier (bigger vertical bob).
	var w = ZV.new()
	root.add_child(w)
	var p0: float = w.debug_pose()["phase"]
	for i in 30:
		w.tick(1.0 / 60.0, 2.0, true)
	var p1: float = w.debug_pose()["phase"]
	_check("walk_phase_advances", p1 > p0 + 0.5)
	var b = ZV.new()
	root.add_child(b)
	b.set_brute()
	var lo := 999.0
	var hi := -999.0
	var blo := 999.0
	var bhi := -999.0
	for i in 120:
		w.tick(1.0 / 60.0, 2.0, true)
		b.tick(1.0 / 60.0, 2.0, true)
		var y: float = w.debug_pose()["body_y"]
		var by: float = b.debug_pose()["body_y"]
		lo = minf(lo, y)
		hi = maxf(hi, y)
		blo = minf(blo, by)
		bhi = maxf(bhi, by)
	_check("brute_stomp_heavier", (bhi - blo) > (hi - lo) * 1.2)
	w.free()
	b.free()

	# 3. Lunge telegraph: arms coil above rest BEFORE the 0.22s damage frame.
	var a = ZV.new()
	root.add_child(a)
	a.play_lunge()
	var coiled := false
	for i in 6: # 6 ticks = 0.10s < 0.22s damage frame
		a.tick(1.0 / 60.0, 0.0, false)
		if float(a.debug_pose()["arm_l_x"]) < -1.2:
			coiled = true
	_check("lunge_telegraph_before_damage", coiled)
	a.free()

	# 4. AI balance constants unchanged.
	_check("const_wander_day", ZA.WANDER_DAY == 1.2)
	_check("const_wander_night", ZA.WANDER_NIGHT == 1.8)
	_check("const_chase_day", ZA.CHASE_DAY == 2.7)
	_check("const_chase_night", ZA.CHASE_NIGHT == 3.8)
	_check("const_vision_day", ZA.VISION_DAY == 11.0)
	_check("const_vision_night", ZA.VISION_NIGHT == 13.5)
	_check("const_cone_day", ZA.CONE_DAY == 75.0)
	_check("const_cone_night", ZA.CONE_NIGHT == 90.0)
	_check("const_attack_range", ZA.ATTACK_RANGE == 1.7)
	_check("const_attack_damage", ZA.ATTACK_DAMAGE == 12.0)
	_check("const_attack_cooldown", ZA.ATTACK_COOLDOWN == 1.3)
	_check("const_pound_damage", ZA.POUND_DAMAGE == 8.0)
	_check("const_pound_range", ZA.POUND_RANGE == 2.4)
	_check("const_pound_cooldown", ZA.POUND_COOLDOWN == 1.3)
	_check("const_lose_time", ZA.LOSE_TIME == 4.0)
	_check("const_hear_mult", ZA.HEAR_MULT_NIGHT == 1.4)
	_check("const_max_hp", ZA.MAX_HP == 100.0)

	# 5. notice() head-snap.
	var n = ZV.new()
	root.add_child(n)
	n.notice(-1.0)
	_check("notice_head_snap", int(n.get("_twitch_kind")) == 1)
	_check("notice_direction", float(n.get("_twitch_dir")) < 0.0)
	# The snap must complete with zero residue (differential offsets).
	for i in 40:
		n.tick(1.0 / 60.0, 0.0, false)
	_check("notice_completes", int(n.get("_twitch_kind")) == 0)
	n.free()
	stub.free()
