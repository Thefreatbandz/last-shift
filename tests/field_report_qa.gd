extends SceneTree
## QA for the Tbandz iPhone field report (2026-09-30):
##  1. Night too dark -> night ambient lifted; real-light count capped.
##  2. "Random spawning zombies" -> initial scatter >= 30m from player start.
##  3. "Haven't found any guns" -> armory pistol + warehouse shotgun are
##     scarcity-exempt (survive wave-5 scarcity); police key exists in a
##     house container; the police station door starts locked (key path).
##  4. Quality pass -> ground patches exist; corpse glow ring is the dim
##     variant.

var _booted := false
var _frames := 0
var _main: Node
var _failed := 0
var _passed := 0


class _WaveStub extends RefCounted:
	var wave_number := 4
	func wave_active() -> bool:
		return true


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FIELDREPORT_QA FAIL: ", name)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_run_unit_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	if _frames == 30:
		_run_scene_checks()
		# Stage the night render: midnight lighting applies next frame.
		_main.get_node("TimeManager").set_time(0.0)
	elif _frames == 32:
		_run_night_brightness_check()
		print("FIELDREPORT_QA done passed=", _passed, " failed=", _failed)
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _run_unit_checks() -> void:
	# LootManager references the Sound autoload, which isn't registered in
	# bare --script mode: stub it, then LAZY-load the classes (prompt_qa
	# pattern — a compile-time class_name reference would trigger the
	# failed compile before the stub exists).
	var stub := Node.new()
	stub.name = "Sound"
	stub.set_script(load("res://tests/sound_stub.gd"))
	root.add_child(stub)
	var LM := load("res://scripts/loot/loot_manager.gd")
	var LC := load("res://scripts/loot/loot_container.gd")
	# 3a. Scarcity exemption: a flagged container keeps its guns at wave 5
	# (wave_number 4 + active night = wave 5), while ammo still thins.
	var lm = LM.new()
	lm.world_seed = 777
	lm.wave_manager = _WaveStub.new()
	var c = LC.new()
	c.container_id = 42
	c.loot = [["pistol", 1], ["ammo_9mm", 12]]
	c.scarcity_exempt_guns = true
	var grant = lm._apply_scarcity(c)
	var has_pistol := false
	var ammo_n := 0
	for e in grant:
		if String(e[0]) == "pistol":
			has_pistol = true
		if String(e[0]) == "ammo_9mm":
			ammo_n = int(e[1])
	_check("exempt_pistol_survives_wave5", has_pistol)
	_check("exempt_ammo_still_thins", ammo_n > 0 and ammo_n < 12)
	# 3b. Non-exempt containers keep the old behavior (guns rollable).
	var c2 = LC.new()
	c2.container_id = 43
	c2.loot = [["pistol", 1]]
	c2.scarcity_exempt_guns = false
	var grant2 = lm._apply_scarcity(c2)
	_check("nonexempt_scarcity_runs", grant2.size() == 1)
	lm.free()
	c.free()
	c2.free()


func _run_scene_checks() -> void:
	var nb: Node = _main.get_node("Neighborhood")
	var iz: Node = nb.get("interior_zones")

	# 1a. Night ambient lifted on the real TimeManager.
	var tm: Node = _main.get_node("TimeManager")
	tm.set_time(0.0) # midnight
	var env: Environment = tm.get("_env")
	_check("night_ambient_lifted", env.ambient_light_energy >= 1.29)
	var smat: ProceduralSkyMaterial = tm.get("_sky_mat")
	_check("night_sky_energy_lifted", smat.sky_energy_multiplier >= 0.57)
	# 1a2. Moon key light carries the night (Tbandz: "lighter night").
	var sun: DirectionalLight3D = tm.get("_sun")
	_check("night_moon_energy", sun.light_energy >= 0.54)

	# 1b. Real-light budget: exterior Spot/Omni lights capped (perf).
	var zone_roots := {}
	for z in iz.get("zones"):
		var zd: Dictionary = z
		zone_roots[zd["root"]] = true
	var real_lights := 0
	var stack: Array = [nb]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if zone_roots.has(n):
			continue # interior zones have their own lantern budget
		if n is SpotLight3D or n is OmniLight3D:
			real_lights += 1
		for ch in n.get_children():
			stack.append(ch)
	print("FIELDREPORT_QA exterior real lights=", real_lights)
	_check("real_light_cap", real_lights <= 14)
	_check("real_lights_exist", real_lights >= 8)

	# 2. Initial scatter never near the player start.
	var pstart: Vector3 = nb.get("player_start")
	var min_d := 1e9
	for p in nb.get("zombie_spawns"):
		var pos: Vector3 = p
		min_d = minf(min_d, pos.distance_to(pstart))
	print("FIELDREPORT_QA min zombie scatter dist=", min_d)
	_check("scatter_offscreen", min_d >= 30.0)

	# 3c. The real armory + warehouse shotgun containers are flagged and
	# hold the guns.
	var loot: Node = _main.get_node("Loot")
	var exempt := []
	for lc in loot.get_containers():
		if lc.get("scarcity_exempt_guns"):
			exempt.append(lc)
	var got_pistol := false
	var got_shotgun := false
	for lc in exempt:
		for e in lc.get("loot"):
			if String(e[0]) == "pistol":
				got_pistol = true
			if String(e[0]) == "shotgun":
				got_shotgun = true
	print("FIELDREPORT_QA exempt containers=", exempt.size())
	_check("exempt_containers_exist", exempt.size() >= 2)
	_check("armory_pistol_guaranteed", got_pistol)
	_check("warehouse_shotgun_guaranteed", got_shotgun)

	# 3d. Police key path: a house container hides the key; the police
	# station door starts locked.
	var has_key := false
	for lc in loot.get_containers():
		for e in lc.get("loot"):
			if String(e[0]) == "police_key":
				has_key = true
	_check("police_key_hidden_in_house", has_key)
	var police_locked := false
	for b in nb.get("buildings"):
		var bd: Dictionary = b
		if String(bd.get("kind", "")) == "police":
			var door: Dictionary = bd["door"]
			if bool(door.get("locked", false)):
				police_locked = true
	_check("police_door_locked", police_locked)

	# 4a. Ground variation patches exist.
	var patch_mats := [nb.get("_m_patch_dirt"), nb.get("_m_patch_dark"),
		nb.get("_m_patch_ash")]
	var patches := 0
	var stack2: Array = [nb]
	while not stack2.is_empty():
		var n2: Node = stack2.pop_back()
		if n2 is MeshInstance3D and patch_mats.has(n2.get("material_override")):
			patches += 1
		for ch in n2.get_children():
			stack2.append(ch)
	print("FIELDREPORT_QA ground patches=", patches)
	_check("ground_patches_exist", patches >= 30)

	# 4b. Corpse glow ring is the dim variant (toned down: bodies, not beacons).
	var LC2 := load("res://scripts/loot/loot_container.gd")
	var dim_mat: StandardMaterial3D = LC2._m_glow_dim
	_check("corpse_glow_dim", dim_mat != null \
		and dim_mat.emission_energy_multiplier < 0.2)


func _run_night_brightness_check() -> void:
	# Rendered-night pixel check: the midnight frame must be meaningfully
	# brighter than the old pitch-black floor (Tbandz: "lighter night").
	# Runs two frames after set_time(0.0) so the env has applied + rendered.
	var img := root.get_texture().get_image()
	img.resize(96, 96)
	var sum := 0.0
	var n := 0
	for y in range(24, 72):
		for x in range(24, 72):
			var c := img.get_pixel(x, y)
			sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			n += 1
	var mean := sum / float(maxi(n, 1))
	print("FIELDREPORT_QA night mean luminance=", mean)
	_check("night_frame_readable", mean >= 0.045)
