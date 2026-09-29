class_name ZombieManager
extends Node3D
## Phase 2: owns the walker pack. Spawns 6 zombies scattered around the
## neighborhood (away from the player start), routes NoiseBus pulses to
## them, applies cheap pairwise separation, drives the night eye-glow, and
## resets the pack when the player respawns.

const ZOMBIE_SCENE := preload("res://scenes/zombie/zombie.tscn")
const PACK_SIZE := 6
const SEPARATION_DIST := 1.6

# Scatter points: streets and lots, clear of houses/cars/fences, away from
# the player spawn at (-6, -10).
const SPAWNS := [
	Vector3(-40, 0.3, -6),
	Vector3(-18, 0.3, 10),
	Vector3(10, 0.3, -6),
	Vector3(-52, 0.3, 16),
	Vector3(16, 0.3, 14),
	Vector3(-30, 0.3, -4),
]

var zombies: Array[ZombieAI] = []

var _player: PlayerController
var _time_manager: TimeManager
var _noise: NoiseBus


func setup(player: PlayerController, tm: TimeManager, noise: NoiseBus) -> void:
	_player = player
	_time_manager = tm
	_noise = noise
	_noise.noise_emitted.connect(_on_noise)
	_spawn_pack()


func _spawn_pack() -> void:
	for i in PACK_SIZE:
		var z := ZOMBIE_SCENE.instantiate() as ZombieAI
		add_child(z)
		z.global_position = SPAWNS[i % SPAWNS.size()]
		z.setup(_player, _time_manager)
		zombies.append(z)


func _on_noise(pos: Vector3, radius: float) -> void:
	for z in zombies:
		if is_instance_valid(z):
			z.on_noise(pos, radius)


func reset_all() -> void:
	for z in zombies:
		if is_instance_valid(z):
			z.reset()


func living_zombies() -> Array[ZombieAI]:
	var out: Array[ZombieAI] = []
	for z in zombies:
		if is_instance_valid(z) and not z.is_queued_for_deletion():
			out.append(z)
	return out


func _process(_delta: float) -> void:
	# Night eye-glow (one static call — cheap, shared material).
	var ang := _time_manager.time_hours / 24.0 * TAU - PI * 0.5
	var night_f := 1.0 - smoothstep(-0.06, 0.22, sin(ang))
	ZombieVisual.set_eye_glow(night_f * 2.4)


func _physics_process(_delta: float) -> void:
	# Pairwise separation so the pack doesn't stack (n=6: trivial).
	var live := living_zombies()
	for i in live.size():
		for j in range(i + 1, live.size()):
			var a := live[i]
			var b := live[j]
			var d := a.global_position - b.global_position
			d.y = 0.0
			var dist := d.length()
			if dist < SEPARATION_DIST and dist > 0.01:
				var push := d / dist * (SEPARATION_DIST - dist) * 2.0
				a.velocity += push
				b.velocity -= push
