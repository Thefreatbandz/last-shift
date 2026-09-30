extends SceneTree
## Wave-survival regression suite.
## - Short day length (360s) preserved from the wave pivot.
## - Wave scaling, brute gating, deterministic forest-edge spawns, dawn
##   transition, wave completion without waiting on corpse fade.
## - Nail-bat timing/damage UNCHANGED; machete/axe profiles correct.
## - Barricade: 3 visual stages, zombie pounding damages, repair costs wood.
## - Pistol/shotgun ammo + reload; gun noise wired through NoiseBus.
## - Bandage / health kit / painkiller effects correct.
## - Sleep refused during an active night wave.
## Run: godot --headless --path . --script res://tests/wave_qa.gd
## Grep the output for SCRIPT ERROR separately.
## NOTE: classes that touch the Sound autoload are never named here; the
## --script compiler can't see autoloads, so everything goes through
## get_node/get/set/call duck-typing and source-text checks.

const EPS := 0.05

var _booted := false
var _frames := 0
var _ok := true
var _main: Node


func _check(label: String, cond: bool) -> void:
	if cond:
		print("WAVEQA PASS ", label)
	else:
		_ok = false
		print("WAVEQA FAIL ", label)


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_static_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 45:
		_live_checks_a()
	elif _frames == 60:
		_live_checks_b()
	elif _frames == 90:
		_live_checks_c()
	elif _frames == 140:
		_live_checks_d()
	elif _frames == 160:
		_live_checks_e()
		print("WAVEQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


# ------------------------------------------------------------- static checks

func _static_checks() -> void:
	var tm := _src("res://scripts/world/time_manager.gd")
	_check("day_length_360", tm.contains("const DAY_LENGTH := 360.0"))
	var wm := _src("res://scripts/world/wave_manager.gd")
	_check("wave_size_formula", wm.contains("mini(8 + 4 * night, 36)"))
	_check("brute_gate_w3", wm.contains("if night < 3:") and wm.contains("mini(1 + night / 4, 3)"))
	# The day counter is owned by TimeManager (midnight wrap). The wave must
	# never touch it, or every night would double-increment the day.
	_check("wave_no_day_touch", not wm.contains("day += 1"))
	var pc := _src("res://scripts/combat/player_combat.gd")
	_check("bat_swing_0.34", pc.contains("const SWING_TIME := 0.34"))
	_check("bat_cooldown_0.45", pc.contains("const COOLDOWN := 0.45"))
	_check("bat_damage_34", pc.contains("const DAMAGE := 34.0"))
	_check("bat_range_2.2", pc.contains("const RANGE := 2.2"))
	_check("bat_arc_65", pc.contains("const ARC_DEG := 65.0"))
	_check("bat_stamina_8", pc.contains("\"stamina\": 8.0"))
	_check("bat_noise_6", pc.contains("MELEE_NOISE_RADIUS := 6.0"))
	var wp := _src("res://scripts/combat/weapon_manager.gd")
	_check("bat_profile_matches", wp.contains("\"swing\": 0.34") and wp.contains("\"damage\": 34.0"))
	_check("machete_profile", wp.contains("\"swing\": 0.26") and wp.contains("\"damage\": 26.0"))
	_check("axe_profile", wp.contains("\"swing\": 0.42") and wp.contains("\"damage\": 52.0"))
	_check("pistol_profile", wp.contains("\"damage\": 45.0") and wp.contains("\"mag\": 12"))
	_check("shotgun_profile", wp.contains("\"pellets\": 6") and wp.contains("\"damage\": 16.0"))
	var rc := _src("res://scripts/combat/ranged_combat.gd")
	_check("gun_noise_bus", rc.contains("emit_noise") and rc.contains("g[\"noise\"]"))
	var bm := _src("res://scripts/world/barricade_manager.gd")
	_check("barricade_cost", bm.contains("BUILD_WOOD := 3") and bm.contains("BUILD_SCRAP := 1"))
	_check("repair_cost", bm.contains("REPAIR_WOOD := 2"))
	_check("barricade_stages", bm.contains("_update_stage"))
	var zsrc := _src("res://scripts/zombie/zombie_ai.gd")
	_check("zombie_pounding", bm.contains("func pound(") and zsrc.contains("POUND_COOLDOWN := 1.3") and zsrc.contains("POUND_DAMAGE := 8.0"))
	var sh := _src("res://scripts/safehouse/safehouse.gd")
	_check("sleep_blocked_source", sh.contains("wave_active()") and sh.contains("CAN'T SLEEP"))
	var sv := _src("res://scripts/survival/survival_stats.gd")
	_check("hunger_48h", sv.contains("100.0 / 48.0"))
	_check("thirst_36h", sv.contains("100.0 / 36.0"))
	var ld := _src("res://scripts/loot/loot_defs.gd")
	_check("med_heals", ld.contains("BANDAGE: 25.0") and ld.contains("HEALTH_KIT: 70.0"))
	_check("med_use_times", ld.contains("BANDAGE: 1.2") and ld.contains("HEALTH_KIT: 3.5"))
	_check("painkiller_regen", ld.contains("PAINKILLER_REGEN_MULT := 1.8") and ld.contains("PAINKILLER_REGEN_SECS := 60.0"))


# ---------------------------------------------------------------- live: A

func _live_checks_a() -> void:
	var waves: Node = _main.get_node("Waves")
	var barricades: Node = _main.get_node("Barricades")
	var weapons: Node = _main.get_node("Weapons")
	var ranged: Node = _main.get_node("Ranged")
	_check("nodes_wired", waves != null and barricades != null and weapons != null and ranged != null)
	_check("phase_day", String(waves.get("phase")) == "day")
	_check("wave_0", int(waves.get("wave_number")) == 0)
	_check("not_wave_active", not bool(waves.call("wave_active")))
	_check("size_w1", int(waves.call("wave_size", 1)) == 12)
	_check("size_w2", int(waves.call("wave_size", 2)) == 16)
	_check("size_w3", int(waves.call("wave_size", 3)) == 20)
	_check("size_w8_capped", int(waves.call("wave_size", 8)) == 36)
	_check("size_w10_capped", int(waves.call("wave_size", 10)) == 36)
	_check("brutes_w1", int(waves.call("wave_brutes", 1)) == 0)
	_check("brutes_w2", int(waves.call("wave_brutes", 2)) == 0)
	_check("brutes_w3", int(waves.call("wave_brutes", 3)) == 1)
	_check("brutes_w6", int(waves.call("wave_brutes", 6)) == 2)
	_check("brutes_w9_capped", int(waves.call("wave_brutes", 9)) == 3)
	# Nail-bat def unchanged through the weapon routing.
	var combat: Node = _main.get_node("Player").get_node("Combat")
	var bat: Dictionary = combat.call("_melee_def")
	_check("live_bat_damage", is_equal_approx(float(bat["damage"]), 34.0))
	_check("live_bat_swing", is_equal_approx(float(bat["swing"]), 0.34))
	_check("live_bat_cooldown", is_equal_approx(float(bat["cooldown"]), 0.45))
	_check("live_bat_range", is_equal_approx(float(bat["range"]), 2.2))
	_check("live_bat_arc", is_equal_approx(float(bat["arc"]), 65.0))
	# Weapon ownership gating.
	_check("pistol_locked", not bool(weapons.call("can_equip", "pistol")))
	var inv: Node = _main.get_node("Inventory")
	inv.call("add", "pistol", 1)
	_check("pistol_unlocked", bool(weapons.call("can_equip", "pistol")))
	_check("equip_pistol", bool(weapons.call("equip", "pistol")))
	_check("pistol_current", String(weapons.get("current")) == "pistol")
	var mag: Dictionary = ranged.get("mag")
	_check("pistol_mag_12", int(mag["pistol"]) == 12)
	_check("weapon_display", String(weapons.call("display")) == "PISTOL 12/0")
	# Melee unlocks + profiles.
	_check("machete_locked", not bool(weapons.call("equip", "machete")))
	inv.call("add", "machete", 1)
	inv.call("add", "fire_axe", 1)
	_check("equip_machete", bool(weapons.call("equip", "machete")))
	var md: Dictionary = combat.call("_melee_def")
	_check("live_machete", is_equal_approx(float(md["damage"]), 26.0) and is_equal_approx(float(md["swing"]), 0.26))
	_check("equip_axe", bool(weapons.call("equip", "fire_axe")))
	var ad: Dictionary = combat.call("_melee_def")
	_check("live_axe", is_equal_approx(float(ad["damage"]), 52.0) and is_equal_approx(float(ad["swing"]), 0.42))
	weapons.call("equip", "bat")
	# Start a timed bandage heal; B checks the result.
	var health: Node = _main.get_node("Player").get_node("Health")
	health.set("hp", 40.0)
	inv.call("add", "bandage", 1)
	_check("bandage_use_starts", bool(inv.call("use", "bandage")))
	inv.set("_use_t", 0.02)


# ---------------------------------------------------------------- live: B

func _live_checks_b() -> void:
	var inv: Node = _main.get_node("Inventory")
	var health: Node = _main.get_node("Player").get_node("Health")
	_check("bandage_heals_25", is_equal_approx(float(health.get("hp")), 65.0))
	# Painkillers: heal + stamina-regen boost.
	inv.call("add", "painkillers", 1)
	_check("painkiller_use_starts", bool(inv.call("use", "painkillers")))
	inv.set("_use_t", 0.02)
	# Barricade: build on door h5, verify 3 damage stages, repair, break.
	var barricades: Node = _main.get_node("Barricades")
	var st: Dictionary = barricades.get("_st")
	var s: Dictionary = st["h5"]
	inv.call("add", "wood", 3)
	inv.call("add", "scrap", 1)
	barricades.call("_try_build", "h5", s)
	_check("build_hp_100", is_equal_approx(float(s["hp"]), 100.0))
	_check("build_cost_wood", int(inv.call("count", "wood")) == 0)
	_check("build_cost_scrap", int(inv.call("count", "scrap")) == 0)
	_check("stage0_4_planks", _visible_planks(s) == 4)
	barricades.call("pound", "h5", 40.0)
	_check("pound_damages", is_equal_approx(float(s["hp"]), 60.0))
	_check("stage1_3_planks", _visible_planks(s) == 3)
	barricades.call("pound", "h5", 40.0)
	_check("stage2_2_planks", _visible_planks(s) == 2)
	inv.call("add", "wood", 2)
	barricades.call("_try_repair", "h5", s)
	_check("repair_heals_50", is_equal_approx(float(s["hp"]), 70.0))
	_check("repair_costs_wood", int(inv.call("count", "wood")) == 0)
	barricades.call("pound", "h5", 200.0)
	_check("boards_break", s["boards"] == null)
	_check("door_hp_after_boards", is_equal_approx(float(s["door_hp"]), 60.0))
	# Sleep is refused while a wave is active.
	var waves: Node = _main.get_node("Waves")
	var safehouse: Node = _main.get_node("Safehouse")
	waves.set("phase", "night")
	safehouse.call("sleep")
	_check("sleep_blocked_wave", not bool(safehouse.get("_sleeping")))
	waves.set("phase", "day")


func _visible_planks(s: Dictionary) -> int:
	var boards: Node = s["boards"]
	if boards == null:
		return 0
	var n := 0
	for c in boards.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible \
				and String((c as Node).name).begins_with("plank"):
			n += 1
	return n


# ---------------------------------------------------------------- live: C

func _live_checks_c() -> void:
	var inv: Node = _main.get_node("Inventory")
	var health: Node = _main.get_node("Player").get_node("Health")
	var survival: Node = _main.get_node("Survival")
	_check("painkiller_heals_30", is_equal_approx(float(health.get("hp")), 95.0))
	_check("painkiller_boost", is_equal_approx(float(survival.get("_stamina_boost_mult")), 1.8))
	# Health kit: slow, big heal.
	health.set("hp", 10.0)
	inv.call("add", "health_kit", 1)
	_check("healthkit_use_starts", bool(inv.call("use", "health_kit")))
	inv.set("_use_t", 0.02)
	# Wave spawn: deterministic, forest-edge ring, wave-1 size, no brutes.
	var waves: Node = _main.get_node("Waves")
	var player: Node = _main.get_node("Player")
	waves.call("_spawn_wave", 1)
	var wv: Array = waves.get("wave_zombies")
	_check("wave1_size", wv.size() == 12)
	var brutes := 0
	for z in wv:
		if bool(z.get_meta("brute", false)):
			brutes += 1
	_check("wave1_no_brutes", brutes == 0)
	var sig_a := _spawn_sig(wv)
	var pp: Vector3 = player.get("global_position")
	var ring_ok := true
	for z in wv:
		var d: float = (z.get("global_position") as Vector3 - pp).length()
		if d < 75.0 or d > 96.0:
			ring_ok = false
	_check("spawn_ring_80_94", ring_ok)
	_clear_wave_zombies(waves)
	waves.call("_spawn_wave", 1)
	var wv2: Array = waves.get("wave_zombies")
	_check("spawn_deterministic", _spawn_sig(wv2) == sig_a)
	# Night wave -> kill everything -> dawn must come without corpse-fade wait.
	waves.set("phase", "night")
	waves.set("_spawned_this_night", true)
	for z in wv2:
		z.call("take_damage", 99999.0, z.get("global_position"))
	_check("kills_register_dead", int(waves.call("zombies_remaining")) == 0)


func _spawn_sig(wv: Array) -> String:
	var parts: PackedStringArray = []
	for z in wv:
		var p: Vector3 = z.get("global_position")
		parts.append("%d,%d" % [roundi(p.x * 10.0), roundi(p.z * 10.0)])
	parts.sort()
	return ",".join(parts)


func _clear_wave_zombies(waves: Node) -> void:
	var zm: Node = _main.get_node("Zombies")
	var zl: Array = zm.get("zombies")
	var wv: Array = waves.get("wave_zombies")
	for z in wv:
		zl.erase(z)
		z.queue_free()
	wv.clear()


# ---------------------------------------------------------------- live: D

func _live_checks_d() -> void:
	var health: Node = _main.get_node("Player").get_node("Health")
	_check("healthkit_heals_70", is_equal_approx(float(health.get("hp")), 80.0))
	var waves: Node = _main.get_node("Waves")
	_check("wave_cleared_to_day", String(waves.get("phase")) == "day")
	_check("wave_number_1", int(waves.get("wave_number")) == 1)
	var tm: Node = _main.get_node("TimeManager")
	# The clock keeps ticking after the dawn jump, so allow a small window.
	var _th: float = float(tm.get("time_hours"))
	_check("dawn_time_6_30", _th >= 6.5 and _th < 7.0)
	# Gun reload: mag/ammo accounting.
	var inv: Node = _main.get_node("Inventory")
	var ranged: Node = _main.get_node("Ranged")
	var weapons: Node = _main.get_node("Weapons")
	weapons.call("equip", "pistol")
	var mag: Dictionary = ranged.get("mag")
	mag["pistol"] = 5
	inv.call("add", "ammo_9mm", 12)
	_check("reload_starts", bool(ranged.call("start_reload")))
	ranged.set("_reload_t", 0.02)


# ---------------------------------------------------------------- live: E

func _live_checks_e() -> void:
	var ranged: Node = _main.get_node("Ranged")
	var inv: Node = _main.get_node("Inventory")
	var weapons: Node = _main.get_node("Weapons")
	var mag: Dictionary = ranged.get("mag")
	_check("reload_refills_mag", int(mag["pistol"]) == 12)
	_check("reload_consumes_ammo", int(inv.call("count", "ammo_9mm")) == 5)
	_check("weapon_display_ammo", String(weapons.call("display")) == "PISTOL 12/5")
	_check("reload_flag_clear", String(ranged.get("_reloading")) == "")
	# Empty mag + no reserve -> no reload, and firing is denied loudly.
	mag["pistol"] = 0
	inv.call("add", "ammo_9mm", -int(inv.call("count", "ammo_9mm")))
	_check("reload_denied_no_ammo", not bool(ranged.call("start_reload")))
