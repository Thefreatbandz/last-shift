class_name PlayerCombat
extends Node
## Phase 2: manual melee combat. Desktop: Space / left-click. Touch: the
## HUD's big ATTACK button. A nail bat lives in the survivor's hand (built
## here as a child of Visual — player_visual.gd itself is untouched) and
## sweeps on each swing. Hits land in a 2.2m frontal arc with knockback and
## emit a small noise pulse. Also emits footstep noise while sprinting.

const SWING_TIME := 0.34
const COOLDOWN := 0.45
const RANGE := 2.2
const ARC_DEG := 65.0
const DAMAGE := 34.0
const MELEE_NOISE_RADIUS := 6.0
const SPRINT_NOISE_RADIUS := 15.0
const SPRINT_NOISE_INTERVAL := 0.45

var _player: PlayerController
var _hud: Hud
var _zombies: ZombieManager
var _noise: NoiseBus
var _health: PlayerHealth
var _visual: Node3D

var _weapon_pivot: Node3D
var _swing_t := 0.0
var _cd := 0.0
var _hit_done := false
var _noise_t := 0.0
var _suppress := 0.0


func suppress_attack(seconds: float) -> void:
	_suppress = maxf(_suppress, seconds)


func setup(player: PlayerController, hud: Hud, zombies: ZombieManager,
		noise: NoiseBus, health: PlayerHealth) -> void:
	_player = player
	_hud = hud
	_zombies = zombies
	_noise = noise
	_health = health
	_visual = player.get_node("Visual") as Node3D
	_build_weapon()


func _build_weapon() -> void:
	# Nail bat carried in the right hand. Pivot near the shoulder so the
	# swing reads from the gameplay camera.
	_weapon_pivot = Node3D.new()
	_weapon_pivot.position = Vector3(0.33, 1.28, -0.06)
	_visual.add_child(_weapon_pivot)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.18)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.45, 0.46, 0.48)
	steel.metallic = 0.7
	steel.roughness = 0.45
	var handle := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.028
	hc.bottom_radius = 0.032
	hc.height = 0.62
	hc.radial_segments = 8
	handle.mesh = hc
	handle.material_override = wood
	_weapon_pivot.add_child(handle)
	for i in 4:
		var nail := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(0.016, 0.016, 0.07)
		nail.mesh = nb
		nail.position = Vector3(0, 0.05 + 0.12 * i, 0.045)
		nail.material_override = steel
		_weapon_pivot.add_child(nail)
	_weapon_pivot.rotation.x = 0.55 # rest: angled down-forward


func try_attack() -> void:
	if _health.is_dead() or _cd > 0.0:
		return
	_cd = COOLDOWN
	_swing_t = SWING_TIME
	_hit_done = false
	_noise.emit_noise(_player.global_position, MELEE_NOISE_RADIUS)


func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_suppress = maxf(0.0, _suppress - delta)
	if _health.is_dead():
		return
	if _suppress <= 0.0 and (Input.is_action_just_pressed("attack") or _hud.consume_attack()):
		try_attack()
	_update_swing(delta)
	_update_sprint_noise(delta)


func _update_swing(delta: float) -> void:
	if _swing_t <= 0.0:
		return
	_swing_t -= delta
	var t := 1.0 - _swing_t / SWING_TIME # 0 -> 1
	# Raise fast, sweep through, settle back.
	var ang := lerpf(-1.9, 0.9, ease(t, 0.6))
	_weapon_pivot.rotation.x = ang
	if not _hit_done and t >= 0.45:
		_hit_done = true
		_apply_hit()
	if _swing_t <= 0.0:
		_weapon_pivot.rotation.x = 0.55


func _apply_hit() -> void:
	var yaw := (_visual as Node3D).rotation.y
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	for z in _zombies.living_zombies():
		var to := z.global_position - _player.global_position
		to.y = 0.0
		if to.length() > RANGE:
			continue
		if fwd.dot(to.normalized()) < cos(deg_to_rad(ARC_DEG)):
			continue
		z.take_damage(DAMAGE, _player.global_position)


func _update_sprint_noise(delta: float) -> void:
	var sprinting := false
	if _hud.touch_mode:
		sprinting = _hud.sprint_held
	else:
		sprinting = Input.is_action_pressed("sprint")
	var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
	if sprinting and planar > 4.0:
		_noise_t += delta
		if _noise_t >= SPRINT_NOISE_INTERVAL:
			_noise_t = 0.0
			_noise.emit_noise(_player.global_position, SPRINT_NOISE_RADIUS)
	else:
		_noise_t = 0.0
