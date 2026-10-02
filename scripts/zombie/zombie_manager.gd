class_name ZombieManager
extends Node3D
## Phase 2: owns the walker pack. Spawns PACK_SIZE zombies scattered around
## the neighborhood (away from the player start), routes NoiseBus pulses to
## them, applies cheap pairwise separation, drives the night eye-glow, and
## resets the pack when the player respawns.

const ZOMBIE_SCENE := preload("res://scenes/zombie/zombie.tscn")
const PACK_SIZE := 10 # scaled with the expanded map (was 6 on the old map)
const SEPARATION_DIST := 1.6

# Scatter points: supplied by the seeded neighborhood — open ground, away
# from the player start and the safehouse porch. Exactly PACK_SIZE entries.
var _spawns: Array[Vector3] = []

var zombies: Array[ZombieAI] = []

var _player: PlayerController
var _time_manager: TimeManager
var _noise: NoiseBus
var barricades: BarricadeManager: # wave loop: zombies pound boarded doors
	set(v):
		barricades = v
		# The initial pack spawns in setup(), before main.gd assigns this.
		# Propagate so day-1 zombies can pound too.
		for z in zombies:
			if is_instance_valid(z):
				z.barricades = v

# Loot loop: ~1 in 3 kills drops ammo or a crafting part at the corpse.
# Set via set_drop_context after the LootManager exists (it is built after
# zombies in the bootstrap). Own RNG stream, seeded from the world seed.
var loot: LootManager
var _drng := RandomNumberGenerator.new()
var _drops_on := false
const DROP_CHANCE := 0.34


func set_drop_context(lm: LootManager, wseed: int) -> void:
	loot = lm
	_drng.seed = wseed * 131 + 17
	_drops_on = true

# Phase 3: workbench "Board Barricade" — zombies get gently pushed out of
# this circle, reducing pressure near the claimed safehouse.
var _ward_on := false
var _ward_center := Vector3.ZERO
var _ward_radius := 0.0


func set_ward(center: Vector3, radius: float) -> void:
	_ward_on = true
	_ward_center = center
	_ward_radius = radius


func setup(player: PlayerController, tm: TimeManager, noise: NoiseBus,
		spawns: Array[Vector3], brutes: Array[Vector3] = [],
		indoor: Array[Vector3] = []) -> void:
	_player = player
	_time_manager = tm
	_noise = noise
	_spawns = spawns
	_noise.noise_emitted.connect(_on_noise)
	_spawn_pack()
	# Building types: Brutes only in designated high-risk interiors
	# (police station), regular walkers in other interiors (hospital wards…).
	for bp in brutes:
		var bz := _spawn_at(bp)
		bz.make_brute()
	for ip in indoor:
		_spawn_at(ip)


func _spawn_at(pos: Vector3) -> ZombieAI:
	var z := ZOMBIE_SCENE.instantiate() as ZombieAI
	add_child(z)
	z.global_position = pos
	z.barricades = barricades
	z.setup(_player, _time_manager)
	z.died.connect(_on_zombie_died)
	zombies.append(z)
	return z


func _on_zombie_died(z: ZombieAI) -> void:
	if not _drops_on or loot == null:
		return
	var item := _roll_drop()
	if item.is_empty():
		return
	loot.add_container(z.global_position, [item], "drop")


## One drop roll: [] ~66% of the time, else [id, n]. Own RNG stream.
func _roll_drop() -> Array:
	if _drng.randf() >= DROP_CHANCE:
		return []
	var r := _drng.randf()
	var item: Array
	if r < 0.30:
		item = ["ammo_9mm", _drng.randi_range(3, 6)]
	elif r < 0.50:
		item = ["shells", _drng.randi_range(2, 4)]
	elif r < 0.75:
		item = ["scrap", _drng.randi_range(1, 2)]
	else:
		item = ["cloth", _drng.randi_range(1, 2)]
	return [item]


func _spawn_pack() -> void:
	for i in PACK_SIZE:
		var z := ZOMBIE_SCENE.instantiate() as ZombieAI
		add_child(z)
		if _spawns.size() > i:
			z.global_position = _spawns[i]
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
		if is_instance_valid(z) and not z.is_queued_for_deletion() and not z.is_dead():
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
	if _ward_on:
		for z in live:
			var to := z.global_position - _ward_center
			to.y = 0.0
			var wd := to.length()
			if wd < _ward_radius and wd > 0.01:
				z.velocity += to / wd * (_ward_radius - wd) * 2.5
