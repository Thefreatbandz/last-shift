class_name AudioManager
extends Node
## LAST SHIFT procedural sound system — autoload "Sound".
## All audio is synthesized (assets/audio/*.wav, mono 22050Hz).
##   Sound.play("click")              — 2D / UI sounds
##   Sound.play_3d("groan1", pos)     — world sounds (distance-culled)
##   Sound.bind_time(time_manager)    — day/night ambience crossfade
##   Sound.set_heartbeat(true/false)  — low-HP heartbeat loop
## Pooled voices (no per-frame allocations), modest max distances.

const POOL_2D := 8
const POOL_3D := 10
const MAX_3D_DIST := 32.0
const AMB_DAY_DB := -20.0
const AMB_NIGHT_DB := -18.0

const NAMES: Array[String] = [
	"swoosh", "thwack", "zombie_die", "hurt",
	"groan1", "groan2", "groan3", "groan4", "snarl", "shuffle1", "shuffle2",
	"step1", "step2", "pickup", "search", "eat", "craft", "door", "claim",
	"click", "inv_open", "inv_close", "craft_ok", "death",
	"gunshot", "shotgun", "reload", "pound", "barricade_break", "heal",
	"amb_day", "amb_night", "heartbeat",
]

# Per-sound base volume trims (dB). Ambience/heartbeat handled separately.
# QA mix pass: thwack was clipping-hot at -2 (now -10 + softer attack);
# groans/snarl lifted so zombies read as an early-warning system.
const TRIM := {
	"swoosh": -6.0, "thwack": -10.0, "zombie_die": -5.0, "hurt": -4.0,
	"groan1": -4.0, "groan2": -4.0, "groan3": -4.0, "groan4": -4.0,
	"snarl": -4.0, "shuffle1": -10.0, "shuffle2": -10.0,
	"step1": -9.0, "step2": -9.0, "pickup": -6.0, "search": -7.0,
	"eat": -7.0, "craft": -5.0, "door": -6.0, "claim": -7.0,
	"click": -8.0, "inv_open": -8.0, "inv_close": -8.0,
	"craft_ok": -6.0, "death": -6.0,
	"gunshot": -5.0, "shotgun": -4.0, "reload": -7.0, "pound": -7.0,
	"barricade_break": -5.0, "heal": -7.0,
}

var _s := {}
var _p2d: Array[AudioStreamPlayer] = []
var _p3d: Array[AudioStreamPlayer3D] = []
var _i2d := 0
var _i3d := 0
var _warned := {}
var _time: TimeManager
var _amb_day: AudioStreamPlayer
var _amb_night: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _heart_on := false


func _ready() -> void:
	for n in NAMES:
		var stream := load("res://assets/audio/%s.wav" % n) as AudioStreamWAV
		if stream == null:
			push_warning("Sound: missing assets/audio/%s.wav" % n)
			continue
		_s[n] = stream
	# Seamless loops for ambience + heartbeat.
	# NOTE: loop_end is derived from get_length() * mix_rate, NOT
	# get_data().size(): the importer stores samples compressed (QOA), so
	# the byte count is not the sample count.
	for n in ["amb_day", "amb_night", "heartbeat"]:
		if _s.has(n):
			var w := _s[n] as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * float(w.mix_rate))
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_p2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = MAX_3D_DIST
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		add_child(p)
		_p3d.append(p)
	_amb_day = _make_loop_player("amb_day", AMB_DAY_DB)
	_amb_night = _make_loop_player("amb_night", AMB_NIGHT_DB)
	_heart = _make_loop_player("heartbeat", -6.0)


func _make_loop_player(sound_name: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if _s.has(sound_name):
		p.stream = _s[sound_name]
	p.volume_db = db - 60.0 # start silent, fade in via _process
	add_child(p)
	p.play()
	return p


func play(sound_name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _s.has(sound_name):
		_warn_missing(sound_name)
		return
	var p := _p2d[_i2d]
	_i2d = (_i2d + 1) % POOL_2D
	p.stream = _s[sound_name]
	p.volume_db = float(TRIM.get(sound_name, 0.0)) + vol_db
	p.pitch_scale = pitch
	p.play()


func play_3d(sound_name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0,
		max_dist := MAX_3D_DIST) -> void:
	if not _s.has(sound_name):
		_warn_missing(sound_name)
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(pos) > max_dist:
		return # inaudible: save the voice
	var p := _p3d[_i3d]
	_i3d = (_i3d + 1) % POOL_3D
	p.stream = _s[sound_name]
	p.volume_db = float(TRIM.get(sound_name, 0.0)) + vol_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.global_position = pos
	p.play()


func bind_time(tm: TimeManager) -> void:
	_time = tm


func set_heartbeat(on: bool) -> void:
	_heart_on = on


func _warn_missing(sound_name: String) -> void:
	if not _warned.has(sound_name):
		_warned[sound_name] = true
		push_warning("Sound.play: unknown sound '%s'" % sound_name)


func _process(delta: float) -> void:
	# Day/night ambience crossfade. Same daylight math as TimeManager.
	var day_f := 1.0
	if _time != null:
		var ang := _time.time_hours / 24.0 * TAU - PI * 0.5
		day_f = 1.0 - smoothstep(-0.06, 0.22, sin(ang))
		day_f = 1.0 - day_f # 1 = full day
	var k := 1.0 - exp(-0.8 * delta)
	_amb_day.volume_db = lerpf(_amb_day.volume_db, AMB_DAY_DB + lerpf(-24.0, 0.0, day_f), k)
	_amb_night.volume_db = lerpf(_amb_night.volume_db, AMB_NIGHT_DB + lerpf(-24.0, 0.0, 1.0 - day_f), k)
	_heart.volume_db = lerpf(_heart.volume_db, -6.0 if _heart_on else -66.0, 1.0 - exp(-4.0 * delta))
