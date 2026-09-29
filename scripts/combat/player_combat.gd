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
var _survival: SurvivalStats
var _visual: Node3D
var _blood: BloodFX
var _camera_rig: CameraRig

var _weapon_pivot: Node3D
var _swoosh: MeshInstance3D
var _swoosh_mat: StandardMaterial3D
var _swing_t := 0.0
var _cd := 0.0
var _hit_done := false
var _noise_t := 0.0
var _suppress := 0.0
var _hitstop_gen := 0

# Phase 3: workbench "Spiked Bat" upgrade.
var _damage_bonus := 0.0
var _spiked := false


func add_damage_bonus(amount: float) -> void:
	_damage_bonus += amount


func add_spikes() -> void:
	if _spiked or _weapon_pivot == null:
		return
	_spiked = true
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.50, 0.51, 0.53)
	steel.metallic = 0.75
	steel.roughness = 0.35
	# Long spikes driven through the bat at angles.
	for i in 6:
		var spike := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.02, 0.02, 0.16)
		spike.mesh = sm
		spike.position = Vector3(0, -0.05 + 0.11 * i, 0.0)
		spike.rotation.x = 0.5 + 0.22 * float(i % 3)
		spike.rotation.y = 0.9 * float(i)
		spike.material_override = steel
		_weapon_pivot.add_child(spike)


func suppress_attack(seconds: float) -> void:
	_suppress = maxf(_suppress, seconds)


func setup(player: PlayerController, hud: Hud, zombies: ZombieManager,
		noise: NoiseBus, health: PlayerHealth, survival: SurvivalStats) -> void:
	_player = player
	_hud = hud
	_zombies = zombies
	_noise = noise
	_health = health
	_survival = survival
	_visual = player.get_node("Visual") as Node3D
	_camera_rig = player.camera_rig
	_blood = BloodFX.new()
	_player.add_child(_blood) # BloodFX._ready sets top_level itself
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
	# Swoosh streak: a thin quad in the swing plane, flashed mid-swing.
	_swoosh_mat = StandardMaterial3D.new()
	_swoosh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_swoosh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_swoosh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_swoosh_mat.albedo_color = Color(1, 1, 1, 0)
	var sq := PlaneMesh.new()
	sq.size = Vector2(0.85, 0.30)
	_swoosh = MeshInstance3D.new()
	_swoosh.mesh = sq
	_swoosh.material_override = _swoosh_mat
	_swoosh.rotation.z = PI * 0.5 # quad normal -> swing axis
	_swoosh.position = Vector3(0.03, 0.42, 0)
	_swoosh.visible = false
	_weapon_pivot.add_child(_swoosh)


func try_attack() -> void:
	if _health.is_dead() or _cd > 0.0:
		return
	if _survival != null and not _survival.try_attack_cost():
		return # gassed: blocked with HUD/audio feedback, no cooldown burned
	_cd = COOLDOWN
	_swing_t = SWING_TIME
	_hit_done = false
	Sound.play("swoosh")
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
	_update_swoosh(t)
	if not _hit_done and t >= 0.45:
		_hit_done = true
		_apply_hit()
	if _swing_t <= 0.0:
		_weapon_pivot.rotation.x = 0.55
		_swoosh.visible = false


func _update_swoosh(t: float) -> void:
	# Streak flashes across the middle of the swing, then fades.
	if t > 0.20 and t < 0.78:
		_swoosh.visible = true
		var st := clampf((t - 0.20) / 0.58, 0.0, 1.0)
		_swoosh_mat.albedo_color.a = 0.5 * sin(st * PI)
	else:
		_swoosh.visible = false


func _apply_hit() -> void:
	var yaw := (_visual as Node3D).rotation.y
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var hit_any := false
	var killed_any := false
	for z in _zombies.living_zombies():
		var to := z.global_position - _player.global_position
		to.y = 0.0
		if to.length() > RANGE:
			continue
		if fwd.dot(to.normalized()) < cos(deg_to_rad(ARC_DEG)):
			continue
		var died: bool = z.take_damage(DAMAGE + _damage_bonus, _player.global_position)
		_blood.burst(z.global_position + Vector3(0, 1.25, 0))
		if died:
			_blood.splat(z.global_position) # persistent ground splat
		Sound.play_3d("thwack", z.global_position)
		hit_any = true
		killed_any = killed_any or died
	if hit_any:
		_do_hit_stop()
		_camera_rig.add_trauma(0.55 if killed_any else 0.30)


## Hit-stop: freeze the world ~70ms on connect. The timer ignores
## time_scale so it always restores; the generation counter guards
## against overlapping swings restoring too early.
func _do_hit_stop() -> void:
	_hitstop_gen += 1
	var gen := _hitstop_gen
	Engine.time_scale = 0.06
	await get_tree().create_timer(0.07, true, false, true).timeout
	if gen == _hitstop_gen:
		Engine.time_scale = 1.0


func _update_sprint_noise(delta: float) -> void:
	# Noise only when actually sprinting (stamina-gated), not just holding it.
	var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
	if _player.sprint_active and planar > 4.0:
		_noise_t += delta
		if _noise_t >= SPRINT_NOISE_INTERVAL:
			_noise_t = 0.0
			_noise.emit_noise(_player.global_position, SPRINT_NOISE_RADIUS)
	else:
		_noise_t = 0.0
