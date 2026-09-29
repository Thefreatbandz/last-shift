class_name TimeManager
extends Node
## Owns the world clock and the day/night environment.
## A full 24h cycle runs in DAY_LENGTH real seconds. Drives the sun,
## the procedural sky, fog and ambient light, and tells the neighborhood
## (street lamps, lit windows) and the player (flashlight) how dark it is.

signal clock_changed(day: int, hour: int, minute: int)

const DAY_LENGTH := 720.0 # real seconds per 24 game hours

const DAY_TOP := Color(0.25, 0.50, 0.85)
const DAY_HOR := Color(0.75, 0.82, 0.90)
const DUSK_TOP := Color(0.16, 0.14, 0.30)
const DUSK_HOR := Color(0.95, 0.42, 0.22)
const NIGHT_TOP := Color(0.008, 0.012, 0.030)
const NIGHT_HOR := Color(0.030, 0.050, 0.100)
const DAY_GND := Color(0.10, 0.12, 0.10)
const NIGHT_GND := Color(0.005, 0.006, 0.010)
const FOG_DAY := Color(0.65, 0.72, 0.80)
const FOG_NIGHT := Color(0.020, 0.030, 0.060)

var day := 1
var time_hours := 9.0 # start mid-morning

var _sun: DirectionalLight3D
var _hood: NeighborhoodBuilder
var _visual: PlayerVisual
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _last_minute := -1


func build(root: Node3D, sun: DirectionalLight3D, hood: NeighborhoodBuilder, visual: PlayerVisual) -> void:
	_sun = sun
	_hood = hood
	_visual = visual

	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sun_angle_max = 30.0
	_sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.background_energy_multiplier = 1.0
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.4
	_env.fog_density = 0.004

	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)

	_apply()
	_emit_clock(true)


func _process(delta: float) -> void:
	time_hours += delta * (24.0 / DAY_LENGTH)
	if time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
	_apply()
	_emit_clock(false)


func _apply() -> void:
	# Sun path: 06:00 rises (east), 12:00 overhead, 18:00 sets (west).
	var ang := time_hours / 24.0 * TAU - PI * 0.5
	var elev := sin(ang)
	var sun_dir := Vector3(cos(ang), sin(ang), 0.35).normalized()
	var daylight := smoothstep(-0.06, 0.22, elev)
	var dusk := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)

	var is_day := elev > -0.02
	var light_dir := sun_dir if is_day else -sun_dir
	# DirectionalLight3D shines along its -Z; aim -Z from the sun toward the scene.
	_sun.look_at(_sun.global_position - light_dir * 100.0, Vector3.UP)
	if is_day:
		_sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.50, 0.28), dusk)
	else:
		_sun.light_color = Color(0.50, 0.65, 0.95) # moonlight
	_sun.light_energy = lerpf(0.18, 1.30, daylight)

	var top := NIGHT_TOP.lerp(DAY_TOP, daylight).lerp(DUSK_TOP, dusk * 0.65)
	var hor := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk * 0.65)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_bottom_color = NIGHT_GND.lerp(DAY_GND, daylight)
	_sky_mat.ground_horizon_color = hor * 0.55
	_sky_mat.sky_energy_multiplier = lerpf(0.10, 1.0, daylight)
	_sky_mat.ground_energy_multiplier = lerpf(0.06, 0.9, daylight)

	_env.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight)
	_env.fog_density = lerpf(0.016, 0.004, daylight)
	_env.background_energy_multiplier = lerpf(0.18, 1.0, daylight)
	_env.ambient_light_energy = lerpf(0.55, 1.0, daylight)

	var night_factor := 1.0 - daylight
	_hood.set_night_factor(night_factor)
	_visual.set_flashlight(daylight < 0.35)


func _emit_clock(force: bool) -> void:
	var hour := int(time_hours)
	var minute := int((time_hours - float(hour)) * 60.0)
	if force or minute != _last_minute:
		_last_minute = minute
		clock_changed.emit(day, hour, minute)
