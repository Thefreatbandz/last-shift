class_name TimeManager
extends Node
## Owns the world clock and the day/night environment.
## A full 24h cycle runs in DAY_LENGTH real seconds. Drives the sun,
## the procedural sky, fog and ambient light, and tells the neighborhood
## (street lamps, lit windows) and the player (flashlight) how dark it is.

signal clock_changed(day: int, hour: int, minute: int)

const DAY_LENGTH := 720.0 # real seconds per 24 game hours

const DAY_TOP := Color(0.16, 0.42, 0.78) # deep teal-blue zenith
const DAY_HOR := Color(0.84, 0.68, 0.52) # hazy warm apocalypse horizon
const DUSK_TOP := Color(0.13, 0.11, 0.28)
const DUSK_HOR := Color(1.00, 0.44, 0.18) # ember-orange dusk band
const NIGHT_TOP := Color(0.006, 0.010, 0.036) # deeper blue night
const NIGHT_HOR := Color(0.028, 0.046, 0.105)
const DAY_GND := Color(0.10, 0.12, 0.10)
const NIGHT_GND := Color(0.005, 0.006, 0.010)
const FOG_DAY := Color(0.72, 0.66, 0.58) # warm haze, not blue
const FOG_NIGHT := Color(0.020, 0.030, 0.062)

var day := 1
var time_hours := 9.0 # start mid-morning

var _sun: DirectionalLight3D
var _hood: NeighborhoodBuilder
var _visual: PlayerVisual
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _last_minute := -1
var _built := false # build() runs only once a seeded run starts
var _seed := 0 # world seed: drives deterministic weather below
# Visual rain: a player-following streak field. Weather is a pure function
# of (world_seed, day, hour) — deterministic per seed with no RNG stream
# to keep in sync across save/load. Visual only: no survival effects.
var _rain: GPUParticles3D
var _rain_f := 0.0 # eased 0..1 rain intensity


func build(root: Node3D, sun: DirectionalLight3D, hood: NeighborhoodBuilder, visual: PlayerVisual) -> void:
	_built = true
	_sun = sun
	_hood = hood
	_visual = visual
	_seed = hood.world_seed

	_sky_mat = ProceduralSkyMaterial.new()
	# Big, hazy sun disc — the apocalypse sun hangs visible in the haze.
	_sky_mat.sun_angle_max = 60.0
	_sky_mat.sun_curve = 0.09
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.background_energy_multiplier = 1.0
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Apocalypse grade, pushed: lifted saturation, stronger contrast, and a
	# subtle vignette so the frame reads cinematic on a phone screen.
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.06
	_env.adjustment_contrast = 1.16
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.6
	_env.fog_density = 0.004
	# Subtle vignette: Godot 4 has no Environment vignette, so this is a
	# single full-screen draw on CanvasLayer -1 — above the 3D world,
	# below the HUD (layer 1).
	_build_vignette(root)

	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)

	_build_rain(root)
	_apply()
	_emit_clock(true)


func _process(delta: float) -> void:
	if not _built:
		return # title screen: no run yet, nothing to drive
	time_hours += delta * (24.0 / DAY_LENGTH)
	if time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
	_apply()
	_update_rain(delta)
	_emit_clock(false)


## Vignette overlay: one full-screen radial-gradient draw, CanvasLayer -1
## (above the 3D world, below the HUD). Cinematic frame on phone screens.
func _build_vignette(root: Node) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.01, 0.01, 0.02, 0.38))
	grad.add_point(0.60, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	var layer := CanvasLayer.new()
	layer.layer = -1
	root.add_child(layer)
	var rect := TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture = tex
	layer.add_child(rect)


## Builds the player-following rain streak field (one node, one draw).
func _build_rain(root: Node3D) -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 600
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-20, -15, -20), Vector3(40, 30, 40))
	_rain.amount_ratio = 0.0
	_rain.visible = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 7, 18)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.color = Color(0.62, 0.70, 0.80, 0.42)
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.03, 0.55)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.62, 0.70, 0.80, 0.42)
	streak.material = sm
	_rain.draw_pass_1 = streak
	root.add_child(_rain)


## Stateless weather: ~30% of game-hours rain. Eases in/out; while raining
## the sun dims and the fog thickens.
func _update_rain(delta: float) -> void:
	var hour := int(time_hours)
	var roll := int(abs(hash([_seed, day, hour]))) % 100
	var target := 1.0 if roll < 30 else 0.0
	_rain_f = move_toward(_rain_f, target, delta / 6.0)
	_rain.visible = _rain_f > 0.01
	_rain.amount_ratio = _rain_f
	if _rain.visible:
		_rain.global_position = _visual.global_position + Vector3(0, 7, 0)


func _apply() -> void:
	# Sun path: 06:00 rises (east), 12:00 overhead, 18:00 sets (west).
	# V2: the sun rides a FLATTENED arc (elevation * 0.38) so it hangs low
	# all day — long dramatic shadows, golden-hour mood from morning to
	# dusk. Day/night timing still uses the true elevation (elev), so the
	# 12-minute day length is untouched.
	var ang := time_hours / 24.0 * TAU - PI * 0.5
	var elev := sin(ang)
	var sun_dir := Vector3(cos(ang), sin(ang) * 0.38, 0.35).normalized()
	var daylight := smoothstep(-0.06, 0.22, elev)
	var dusk := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)

	var is_day := elev > -0.02
	var light_dir := sun_dir if is_day else -sun_dir
	# DirectionalLight3D shines along its -Z; aim -Z from the sun toward the scene.
	_sun.look_at(_sun.global_position - light_dir * 100.0, Vector3.UP)
	if is_day:
		# Warm golden sun all day, ember-orange at the edges of the day.
		_sun.light_color = Color(1.0, 0.88, 0.70).lerp(Color(1.0, 0.46, 0.22), dusk)
	else:
		_sun.light_color = Color(0.42, 0.58, 1.0) # cool blue moonlight
	# V2: stronger direct light against LOWER ambient = deep, punchy shadows.
	_sun.light_energy = lerpf(0.24, 1.55, daylight) * (1.0 - 0.35 * _rain_f)

	var top := NIGHT_TOP.lerp(DAY_TOP, daylight).lerp(DUSK_TOP, dusk * 0.65)
	var hor := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk * 0.65)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_bottom_color = NIGHT_GND.lerp(DAY_GND, daylight)
	_sky_mat.ground_horizon_color = hor * 0.55
	_sky_mat.sky_energy_multiplier = lerpf(0.10, 1.0, daylight)
	_sky_mat.ground_energy_multiplier = lerpf(0.06, 0.9, daylight)

	_env.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight)
	_env.fog_density = lerpf(0.016, 0.005, daylight) + 0.012 * _rain_f
	_env.background_energy_multiplier = lerpf(0.18, 1.0, daylight) * (1.0 - 0.25 * _rain_f)
	# V2: cool sky ambient runs LOWER than the warm sun — teal shadows vs
	# orange highlights, the teal-orange apocalypse contrast.
	_env.ambient_light_energy = lerpf(0.55, 0.72, daylight) * (1.0 - 0.20 * _rain_f)

	var night_factor := 1.0 - daylight
	_hood.set_night_factor(night_factor)
	_visual.set_flashlight(daylight < 0.35)


func _emit_clock(force: bool) -> void:
	var hour := int(time_hours)
	var minute := int((time_hours - float(hour)) * 60.0)
	if force or minute != _last_minute:
		_last_minute = minute
		clock_changed.emit(day, hour, minute)
