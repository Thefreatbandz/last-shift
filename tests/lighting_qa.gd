extends SceneTree
## Lighting QA: the night visibility pass (Tbandz: "nights too dark, keep
## the mood"). Asserts:
##   1. Night ambient/bg/sky floors are ABOVE the old values but still dark.
##   2. Flashlight energy 8.0 / range 34 / angle 42 (third small buff).
##   3. Every zone kind interior has 1-2 real warm OmniLight3Ds (cap 2),
##      no shadows, lantern props exist, and the TimeManager's night factor
##      actually reaches the lanterns (day vs night energy differs).
##   4. Lantern placement is deterministic (same seed -> same spots).
## Run:
##   godot --headless --path . --script res://tests/lighting_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEEDS := [48392017, 12345, 777]

var _ok := true
var _booted := false
# Lazy-loaded classes: in bare --script SceneTree mode the test script's
# static class_name dependencies compile before autoload singletons are
# registered, so anything touching the Sound autoload (NeighborhoodBuilder,
# InteriorZones) must be loaded here instead. (interior_qa.gd precedent.)
var _NB: GDScript
var _IZ: GDScript
var _TM: GDScript
var _PV: GDScript


func _check(label: String, cond: bool) -> void:
	if cond:
		print("LIGHTQA PASS ", label)
	else:
		_ok = false
		print("LIGHTQA FAIL ", label)


func _process(_delta: float) -> bool:
	if _booted:
		return false
	_booted = true
	_NB = load("res://scripts/world/neighborhood_builder.gd")
	_IZ = load("res://scripts/world/interior_zones.gd")
	_TM = load("res://scripts/world/time_manager.gd")
	_PV = load("res://scripts/player/player_visual.gd")
	_flashlight_checks()
	for seed in SEEDS:
		_seed_checks(seed)
	_lantern_determinism()
	print("LIGHTQA_RESULT ok=", _ok)
	quit(0 if _ok else 1)
	return true


# ------------------------------------------------------- flashlight -----

func _flashlight_checks() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var pv: Node = _PV.new()
	holder.add_child(pv)
	pv.set_flashlight(true)
	var fl: SpotLight3D = pv._flashlight
	_check("flash_energy", fl.light_energy == 8.0)
	_check("flash_range", fl.spot_range == 34.0)
	_check("flash_angle_kept", fl.spot_angle == 42.0)
	pv.set_flashlight(false)
	_check("flash_off", pv._flashlight.light_energy == 0.0)
	holder.free()


# ------------------------------------------------------- night floors ---

func _seed_checks(seed: int) -> void:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	holder.add_child(sun)
	var pv: Node = _PV.new()
	holder.add_child(pv)
	var tm: Node = _TM.new()
	holder.add_child(tm)
	tm.build(holder, sun, nb, pv)

	# Night: lifted again per the 2026-09-30 field report ("pitch black
	# outside the flashlight"). Ambient source is the sky, which stays
	# dark — the energy lift only brings moonlit silhouettes into read.
	tm.set_time(0.0)
	var env: Environment = tm._env
	_check("night_ambient_%d" % seed, env.ambient_light_energy > 0.95)
	_check("night_ambient_still_dark_%d" % seed, env.ambient_light_energy < 1.20)
	_check("night_bg_%d" % seed, env.background_energy_multiplier >= 0.40)
	_check("night_bg_still_dark_%d" % seed,
		env.background_energy_multiplier < 0.60)
	var sky: ProceduralSkyMaterial = tm._sky_mat
	_check("night_sky_%d" % seed, sky.sky_energy_multiplier >= 0.30)
	_check("night_sky_still_dark_%d" % seed, sky.sky_energy_multiplier < 0.45)
	_check("fog_night_lift_%d" % seed, env.fog_light_color.r > 0.024)
	_check("fog_night_still_dark_%d" % seed, env.fog_light_color.r < 0.10)
	_check("sun_is_moonlight_%d" % seed, sun.light_energy < 0.30)

	# Day sanity: still bright, and day >= night (ordering preserved).
	tm.set_time(12.0)
	_check("day_ambient_%d" % seed, env.ambient_light_energy > 0.75)
	_check("day_bg_%d" % seed, env.background_energy_multiplier > 0.9)
	_check("sun_day_%d" % seed, sun.light_energy > 1.4)

	_zone_light_checks(nb, tm, seed)
	nb.free()
	holder.free()


# ------------------------------------------------------- zone lanterns ---

func _zone_light_checks(nb: Node, tm: Node, seed: int) -> void:
	var iz: Node = nb.interior_zones
	_check("zones_built_%d" % seed, iz != null and iz.zones.size() > 0)
	if iz == null or iz.zones.is_empty():
		return
	for z in iz.zones:
		var zd := z as Dictionary
		var kind := String(zd["kind"])
		var zroot: Node3D = zd["root"]
		var lights := zroot.find_children("*", "OmniLight3D", true, false)
		_check("zone_lights_1to2_%s_%d" % [kind, seed],
			lights.size() >= 1 and lights.size() <= 2)
		var lanterns := zroot.find_children("lantern_*", "Node3D", true, false)
		_check("zone_lantern_props_%s_%d" % [kind, seed], lanterns.size() >= 1)
		for l in lights:
			var ol := l as OmniLight3D
			_check("light_no_shadow_%s_%d" % [kind, seed],
				not ol.shadow_enabled)
			_check("light_warm_%s_%d" % [kind, seed],
				ol.light_color == Color(1.0, 0.72, 0.45))
			_check("light_short_range_%s_%d" % [kind, seed],
				ol.omni_range <= 9.5)
	# The TimeManager's night factor must actually reach the lanterns.
	tm.set_time(0.0)
	for z in iz.zones:
		var zd := z as Dictionary
		var zroot: Node3D = zd["root"]
		for l in zroot.find_children("*", "OmniLight3D", true, false):
			var ol := l as OmniLight3D
			_check("lantern_night_energy_%s_%d" % [String(zd["kind"]), seed],
				ol.light_energy > 1.5)
	tm.set_time(12.0)
	for z in iz.zones:
		var zd := z as Dictionary
		var zroot: Node3D = zd["root"]
		for l in zroot.find_children("*", "OmniLight3D", true, false):
			var ol := l as OmniLight3D
			_check("lantern_day_energy_%s_%d" % [String(zd["kind"]), seed],
				ol.light_energy < 1.0)


## Same seed twice -> identical lantern positions (dedicated RNG stream).
func _lantern_determinism() -> void:
	var spots_a := _lantern_spots(48392017)
	var spots_b := _lantern_spots(48392017)
	_check("lantern_deterministic", spots_a == spots_b and not spots_a.is_empty())


func _lantern_spots(seed: int) -> Array:
	var nb: Node = _NB.new()
	root.add_child(nb)
	nb.build_world(seed)
	var out: Array = []
	for z in nb.interior_zones.zones:
		var zroot: Node3D = (z as Dictionary)["root"]
		for l in zroot.find_children("lantern_*", "Node3D", true, false):
			out.append((l as Node3D).global_position)
	nb.free()
	return out
