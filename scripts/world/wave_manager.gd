class_name WaveManager
extends Node
## Wave-survival loop. Days are short (~3 min of daylight): loot, barricade,
## craft, repair. At dusk a warning banner fires; at nightfall the wave
## spawns at the forest edge and converges on the player. The night ends
## when the wave is cleared — the clock jumps to dawn, the wave counter
## increments, and the next day begins. Escalation: bigger packs each
## night, brutes from night 3.
##
## Determinism: wave spawns use a dedicated RNG seeded with
## (world_seed, wave_number) — the layout RNG stream is never touched.

signal wave_started(n: int)
signal wave_cleared(n: int)

const DUSK_HOUR := 17.0 # warning banner
const NIGHTFALL_HOUR := 18.0 # wave spawns
const DAWN_HOUR := 6.5 # clock jumps here when a wave is cleared
const HOLD_HOUR := 5.9 # clock holds here if the wave isn't cleared by dawn
const SPAWN_RING_MIN := 80.0
const SPAWN_RING_MAX := 94.0

var wave_number := 0 # waves survived so far; next wave is wave_number + 1
var phase := "day" # day | dusk | night
var wave_zombies: Array[ZombieAI] = []

var _tm: TimeManager
var _hood: NeighborhoodBuilder
var _player: PlayerController
var _zombies: ZombieManager
var _hud: Hud
var _dusk_fired := false
var _spawned_this_night := false


## Pure escalation formulas (unit-testable, no scene needed).
static func wave_size(night: int) -> int:
	return mini(8 + 4 * night, 36)


static func wave_brutes(night: int) -> int:
	if night < 3:
		return 0
	return mini(1 + night / 4, 3)


func setup(tm: TimeManager, hood: NeighborhoodBuilder, player: PlayerController,
		zombies: ZombieManager, hud: Hud) -> void:
	_tm = tm
	_hood = hood
	_player = player
	_zombies = zombies
	_hud = hud


func wave_active() -> bool:
	return phase == "night"


func zombies_remaining() -> int:
	var n := 0
	for z in wave_zombies:
		if is_instance_valid(z) and not z.is_queued_for_deletion() and not z.is_dead():
			n += 1
	return n


func _physics_process(_delta: float) -> void:
	if _tm == null:
		return
	var h := _tm.time_hours
	match phase:
		"day":
			if h >= DUSK_HOUR and h < 20.0:
				phase = "dusk"
				_dusk_fired = true
				_spawned_this_night = false
				var n := wave_number + 1
				_hud.show_banner("NIGHT FALLS", "WAVE %d INCOMING — GET INSIDE" % n, 4.0)
				Sound.play("snarl", -4.0, 0.7)
				wave_started.emit(n)
		"dusk":
			if h >= NIGHTFALL_HOUR or h < 12.0:
				# h < 12 catches the 18->24->0 wrap on slow frames.
				phase = "night"
				if not _spawned_this_night:
					_spawned_this_night = true
					_spawn_wave(wave_number + 1)
		"night":
			_hud.set_wave(wave_number + 1, zombies_remaining())
			if zombies_remaining() == 0 and _spawned_this_night:
				_clear_wave()
			elif h >= 6.0 and h < 12.0 and zombies_remaining() > 0:
				# Wave not cleared by dawn: hold the dark until it is.
				_tm.time_hours = HOLD_HOUR


func _spawn_wave(n: int) -> void:
	wave_zombies.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _hood.world_seed * 7919 + n * 131 + 17
	var pp := _player.global_position
	var count := wave_size(n)
	for i in count:
		var p := _edge_spawn(rng, pp)
		var z := _zombies._spawn_at(p)
		z.on_noise(pp, 120.0) # the wave knows where you are
		wave_zombies.append(z)
	for b in wave_brutes(n):
		var p := _edge_spawn(rng, pp)
		var z := _zombies._spawn_at(p)
		z.make_brute()
		z.on_noise(pp, 120.0)
		wave_zombies.append(z)
	Sound.play("groan1", -2.0, 0.8)


func _edge_spawn(rng: RandomNumberGenerator, pp: Vector3) -> Vector3:
	# Forest-edge ring around the player; rejection-sampled off roads/lots
	# and outside the map bounds (clamping would shorten the ring toward
	# the player when they hug the edge).
	for _i in 40:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
		var p := pp + Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) > 95.0 or absf(p.z) > 95.0:
			continue
		if _hood.bx_on_road(p, 1.0) or _hood.bx_point_in_lots(p, 1.0):
			continue
		return Vector3(p.x, 0.3, p.z)
	# Fallback (player wedged where no ring point fits): ring point toward
	# the map center — always in bounds, keeps the intended distance.
	var to_c := Vector3(-pp.x, 0.0, -pp.z)
	if to_c.length() < 0.05:
		to_c = Vector3(1, 0, 0)
	var q := pp + to_c.normalized() * ((SPAWN_RING_MIN + SPAWN_RING_MAX) * 0.5)
	return Vector3(q.x, 0.3, q.z)


func _clear_wave() -> void:
	wave_number += 1
	phase = "day"
	wave_zombies.clear()
	# No day increment here: TimeManager already advanced the calendar at
	# midnight, which every wave spans (18:00 -> 6:30).
	_tm.set_time(DAWN_HOUR)
	_hud.set_wave(0, 0)
	_hud.show_banner("WAVE %d SURVIVED" % wave_number, "DAY %d — FORTIFY AND LOOT" % _tm.day, 4.0)
	Sound.play("craft_ok", -2.0, 1.2)
	wave_cleared.emit(wave_number)
