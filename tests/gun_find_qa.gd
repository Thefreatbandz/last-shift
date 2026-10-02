extends SceneTree
## QA for the gun-findability fix (2026-10-02):
##  1. Dead-officer corpse with a pistol sits ~3.5m OUTSIDE the police
##     station's locked exterior door (no key/lockpick needed), in a navy
##     uniform, scarcity-exempt — across 3 seeds.
##  2. "POLICE STATION / ARMORY INSIDE" proximity hint banner fires exactly
##     once when the player first comes within 15m (unit + in-scene check).
##  3. Day-1 "FIND WEAPONS" banner shows at run start.
##  4. Determinism: same seed => same officer position; seed_qa stays green.
## Run:
##   godot --headless --path . --script res://tests/gun_find_qa.gd

const SEEDS := [48392017, 777, 12345678]
const CHECK_FRAME := 12 # loot/flags all settle in _ready; check early
const FRAMES_PER_SEED := 65 # 3 seeds * 65 + determinism recheck ≈ 260 frames

var _passed := 0
var _failed := 0
var _frames := 0
var _seed_idx := -1 # -1 = unit checks pending
var _main: Node = null
var _seed0_officer_pos := Vector3.ZERO
var _recheck_done := false
var _player_start := Vector3.ZERO


class _HudStub extends RefCounted:
	var banners: Array = []
	func show_banner(main_text: String, sub_text: String,
			duration := 4.0) -> void:
		banners.append([main_text, sub_text, duration])


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("GUNFIND_QA FAIL: ", name)


func _process(_delta: float) -> bool:
	if _seed_idx < 0:
		_seed_idx = 0
		_run_unit_checks()
		_boot(SEEDS[_seed_idx])
		return false
	_frames += 1
	if _frames == CHECK_FRAME:
		_run_scene_checks(SEEDS[_seed_idx])
	elif _frames >= FRAMES_PER_SEED:
		_advance()
	return false


func _boot(seed: int) -> void:
	_frames = 0
	root.get_node("RunState").set("world_seed", seed)
	var ps := load("res://scenes/main.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	current_scene = _main


func _advance() -> void:
	_main.queue_free()
	_main = null
	if _seed_idx == 0 and not _recheck_done:
		# Determinism recheck: rebuild seed 0 and compare the officer spot.
		_recheck_done = true
		_boot(SEEDS[0])
		return
	_seed_idx += 1
	if _seed_idx >= SEEDS.size():
		print("GUNFIND_QA done passed=", _passed, " failed=", _failed)
		quit(1 if _failed > 0 else 0)
		return
	_boot(SEEDS[_seed_idx])


func _run_unit_checks() -> void:
	# Sound-autoload stub (field_report_qa pattern — bare --script mode).
	var stub := Node.new()
	stub.name = "Sound"
	stub.set_script(load("res://tests/sound_stub.gd"))
	root.add_child(stub)
	var IZ := load("res://scripts/world/interior_zones.gd")
	var iz = IZ.new()
	var hs := _HudStub.new()
	iz._hud = hs
	iz._police_door_pos = Vector3(100, 0, 50)
	iz._has_police_door = true
	# Far: stays quiet.
	iz.police_hint_tick(Vector3(100, 0, 80)) # 30m out
	_check("hint_quiet_beyond_15m",
		hs.banners.is_empty() and not bool(iz.get("_police_hint_shown")))
	# Near: fires with the right copy.
	iz.police_hint_tick(Vector3(100, 0, 62)) # 12m out
	_check("hint_fires_within_15m",
		hs.banners.size() == 1 and bool(iz.get("_police_hint_shown")))
	_check("hint_main_text", String(hs.banners[0][0]) == "POLICE STATION")
	_check("hint_sub_key_or_lockpick",
		String(hs.banners[0][1]).contains("LOCKPICK"))
	# Again: still exactly one banner.
	iz.police_hint_tick(Vector3(100, 0, 55))
	iz.police_hint_tick(Vector3(100, 0, 58))
	_check("hint_fires_exactly_once", hs.banners.size() == 1)
	# No cached door (builder-only context): never fires, never errors.
	var iz2 = IZ.new()
	iz2._hud = hs
	iz2.police_hint_tick(Vector3.ZERO)
	_check("hint_no_door_no_fire", hs.banners.size() == 1)
	iz.free()
	iz2.free()


func _run_scene_checks(seed: int) -> void:
	var nb: Node = _main.get_node("Neighborhood")
	var iz: Node = nb.get("interior_zones")
	var loot: Node = _main.get_node("Loot")
	var hud: Node = _main.get_node("HUD")
	_player_start = _main.get_node("Player").global_position

	# Police zone record: exterior door + face + far-zone bounds.
	var pdoor := Vector3.ZERO
	var pbounds := Rect2()
	var pface := 1.0
	for z in iz.get("zones"):
		var zd: Dictionary = z
		if String(zd.get("kind", "")) == "police":
			pdoor = zd["door_pos"]
			pbounds = zd["bounds"]
			pface = float(zd["face"])
	_check("police_zone_exists", pdoor != Vector3.ZERO)

	# The officer corpse: exactly one, holding the pistol.
	var officers := []
	for lc in loot.get_containers():
		if String(lc.get("kind")) == "officer_corpse":
			officers.append(lc)
	_check("officer_corpse_exactly_one", officers.size() == 1)
	if officers.is_empty():
		return
	var oc = officers[0]
	var opos: Vector3 = oc.global_position
	var d := opos.distance_to(pdoor)
	print("GUNFIND_QA seed=", seed, " officer_door_dist=", snappedf(d, 0.01))
	_check("officer_2_to_6m_from_door", d >= 2.0 and d <= 6.0)
	# Outside the (far-offset) zone bounds rect...
	_check("officer_outside_zone_bounds",
		not pbounds.has_point(Vector2(opos.x, opos.z)))
	# ...and outside the real police building footprint (the point of it).
	var bpos := Vector3.ZERO
	var bw := 0.0
	var bd := 0.0
	for b in nb.get("buildings"):
		var bdd: Dictionary = b
		if String(bdd.get("kind", "")) == "police":
			bpos = bdd["pos"]
			bw = float(bdd["w"])
			bd = float(bdd["d"])
	var lx := opos.x - bpos.x
	var lz := opos.z - bpos.z
	_check("officer_outside_footprint",
		absf(lx) > bw * 0.5 + 0.5 or absf(lz) > bd * 0.5 + 0.5)
	# Contents: pistol + 6x 9mm, scarcity-exempt like the armory.
	var has_pistol := false
	var ammo := 0
	for e in oc.get("loot"):
		if String(e[0]) == "pistol":
			has_pistol = true
		if String(e[0]) == "ammo_9mm":
			ammo = int(e[1])
	_check("officer_has_pistol", has_pistol)
	_check("officer_has_6_ammo", ammo == 6)
	_check("officer_scarcity_exempt", bool(oc.get("scarcity_exempt_guns")))
	_check("officer_navy_uniform", bool(oc.get("_officer")))
	_check("officer_prompt_corpse",
		String(load("res://scripts/loot/loot_container.gd") \
			.prompt_for("officer_corpse")) == "SEARCH CORPSE")

	# Locked-door/key mechanics untouched.
	var locked := false
	var has_key := false
	for b in nb.get("buildings"):
		var bdd2: Dictionary = b
		if String(bdd2.get("kind", "")) == "police":
			if bool((bdd2["door"] as Dictionary).get("locked", false)):
				locked = true
	for lc in loot.get_containers():
		for e in lc.get("loot"):
			if String(e[0]) == "police_key":
				has_key = true
	_check("police_door_still_locked", locked)
	_check("police_key_still_hidden", has_key)

	# Armory pistol inside the compound still exists (untouched).
	var armory_pistols := 0
	for lc in loot.get_containers():
		if String(lc.get("kind")) == "officer_corpse":
			continue
		if not bool(lc.get("scarcity_exempt_guns")):
			continue
		for e in lc.get("loot"):
			if String(e[0]) == "pistol":
				armory_pistols += 1
	_check("armory_pistol_untouched", armory_pistols >= 1)

	# Day-1 banner is up at run start.
	var toast: Label = hud.get("_toast")
	var toast_sub: Label = hud.get("_toast_sub")
	_check("day1_banner_main", toast.text == "FIND WEAPONS")
	_check("day1_banner_sub", String(toast_sub.text).contains("ARMORY"))

	# Proximity-hint wiring: door cached, flag clear before approach.
	_check("police_door_cached", bool(iz.get("_has_police_door")))
	_check("hint_flag_clear_at_start", not bool(iz.get("_police_hint_shown")))

	# Determinism recheck hook: seed 0's officer spot must match exactly.
	if seed == SEEDS[0]:
		if _seed0_officer_pos == Vector3.ZERO and not _recheck_done:
			_seed0_officer_pos = opos
		elif _recheck_done:
			_check("officer_pos_deterministic", opos == _seed0_officer_pos)

	# Walk the player up to the locked doors: 12m out along the face, then
	# drive one InteriorZones physics tick directly (headless idle frames
	# outrun real-time physics ticks; this tests the real wiring path).
	var player: Node = _main.get_node("Player")
	player.global_position = pdoor + Vector3(0, 0, pface * 12.0)
	iz._physics_process(1.0 / 60.0)
	_check("hint_fires_in_scene", bool(iz.get("_police_hint_shown")))
	_check("hint_banner_text", toast.text == "POLICE STATION")
	# Back home: the rest of the smoke run proceeds normally, and the
	# latch means the banner can never re-fire.
	player.global_position = _player_start
	iz._physics_process(1.0 / 60.0)
	_check("hint_flag_stays_set", bool(iz.get("_police_hint_shown")))
