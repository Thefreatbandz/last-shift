class_name PlayerCombat
extends Node
## Phase 2: manual melee combat. Desktop: Space / left-click. Touch: the
## HUD's big ATTACK button. A nail bat lives in the survivor's right hand
## (built here, mounted on the forearm by PlayerVisual.attach_weapon) and
## the arms drive each swing. Hits land in a 2.2m frontal arc with knockback
## and emit a small noise pulse. Also emits footstep noise while sprinting.
##
## Wave loop: the WeaponManager owns the equipped weapon (nail bat /
## machete / fire axe melee profiles; pistol / shotgun fired through
## RangedCombat). The bat's numbers below stay the mechanical truth —
## WeaponManager mirrors them — so the original feel is unchanged when no
## manager is wired (or the bat is equipped).

const SWING_TIME := 0.34
const COOLDOWN := 0.45
const RANGE := 2.2
const ARC_DEG := 65.0
const DAMAGE := 34.0
const MELEE_NOISE_RADIUS := 6.0
const SPRINT_NOISE_RADIUS := 15.0
const SPRINT_NOISE_INTERVAL := 0.45
# Gun rest angle: barrel points forward-down (bat rest is PI + 0.55).
const GUN_REST_X := -1.88
const BAT_REST_X := PI + 0.55

var _player: PlayerController
var _hud: Hud
var _zombies: ZombieManager
var _noise: NoiseBus
var _health: PlayerHealth
var _survival: SurvivalStats
var _visual: Node3D
var _blood: BloodFX
var _camera_rig: CameraRig
var weapons: WeaponManager # set by main (wave loop)
var ranged: RangedCombat # set by main (wave loop)

var _weapon_pivot: Node3D
var _swoosh: MeshInstance3D
var _swoosh_mat: StandardMaterial3D
var _swing_t := 0.0
var _cd := 0.0
var _hit_done := false
var _noise_t := 0.0
var _suppress := 0.0
var _hitstop_gen := 0
var _swing_dur := SWING_TIME # per-weapon swing time (bat default)
var _cd_dur := COOLDOWN # per-weapon cooldown (bat default)
var _wired := false

# Phase 3: workbench "Spiked Bat" upgrade.
var _damage_bonus := 0.0
var _spiked := false


func add_damage_bonus(amount: float) -> void:
	_damage_bonus += amount


func add_spikes() -> void:
	if _spiked or _weapon_pivot == null:
		return
	_spiked = true
	_add_spikes_visual()


func _add_spikes_visual() -> void:
	# Long spikes driven through the bat at angles (bat only).
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.50, 0.51, 0.53)
	steel.metallic = 0.75
	steel.roughness = 0.35
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


## Wave loop: called by main after weapons/ranged are assigned.
func wire_weapons() -> void:
	if _wired or weapons == null:
		return
	_wired = true
	weapons.equipped.connect(_on_weapon_equipped)
	_rebuild_weapon(weapons.current)


func _melee_def() -> Dictionary:
	if weapons != null and WeaponManager.is_melee(weapons.current):
		return WeaponManager.MELEE[weapons.current]
	return {"name": "NAIL BAT", "swing": SWING_TIME, "cooldown": COOLDOWN,
		"damage": DAMAGE, "range": RANGE, "arc": ARC_DEG,
		"stamina": 8.0, "noise": MELEE_NOISE_RADIUS}


func _on_weapon_equipped(id: String) -> void:
	_rebuild_weapon(id)


func _rebuild_weapon(id: String) -> void:
	if _weapon_pivot == null:
		return
	for c in _weapon_pivot.get_children():
		c.queue_free()
	_swoosh = null
	_swing_t = 0.0
	_cd = 0.0
	var pv := _visual as PlayerVisual
	match id:
		WeaponManager.MACHETE:
			_build_machete()
			pv.set_weapon_rest(BAT_REST_X)
		WeaponManager.FIRE_AXE:
			_build_fire_axe()
			pv.set_weapon_rest(BAT_REST_X)
		WeaponManager.PISTOL:
			_build_pistol()
			pv.set_weapon_rest(GUN_REST_X)
		WeaponManager.SHOTGUN:
			_build_shotgun()
			pv.set_weapon_rest(GUN_REST_X)
		_:
			_build_bat()
			if _spiked:
				_add_spikes_visual()
			pv.set_weapon_rest(BAT_REST_X)
	if WeaponManager.is_melee(id) or weapons == null:
		_build_swoosh()


## Respawn: the old weapon pivot died with the ragdoll. Attach a fresh
## pivot to the rebuilt forearm and rebuild the current weapon's mesh.
func refresh_weapon_visual() -> void:
	_weapon_pivot = Node3D.new()
	(_visual as PlayerVisual).attach_weapon(_weapon_pivot)
	_rebuild_weapon(weapons.current if weapons != null else WeaponManager.BAT)
	var def := _melee_def()
	_swing_dur = float(def["swing"])
	_cd_dur = float(def["cooldown"])


func _mesh_inst(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	_weapon_pivot.add_child(mi)
	return mi


func _cyl_inst(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	_weapon_pivot.add_child(mi)
	return mi


func _build_machete() -> void:
	# Fast, light: short grip + long flat blade along +Y (same frame as bat).
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.64, 0.66)
	steel.metallic = 0.8
	steel.roughness = 0.30
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.16, 0.12, 0.09)
	grip.roughness = 0.9
	_cyl_inst(0.028, 0.032, 0.22, Vector3(0, -0.08, 0), grip)
	_mesh_inst(Vector3(0.022, 0.62, 0.10), Vector3(0, 0.32, 0), steel)
	_mesh_inst(Vector3(0.026, 0.05, 0.11), Vector3(0, 0.03, 0), grip) # guard


func _build_fire_axe() -> void:
	# Slow, heavy: long haft + head with blade and poll.
	var haft := StandardMaterial3D.new()
	haft.albedo_color = Color(0.48, 0.33, 0.19)
	haft.roughness = 0.85
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.56, 0.58)
	steel.metallic = 0.75
	steel.roughness = 0.40
	var head_red := StandardMaterial3D.new()
	head_red.albedo_color = Color(0.55, 0.16, 0.10)
	head_red.roughness = 0.6
	_cyl_inst(0.026, 0.030, 0.72, Vector3(0, 0.10, 0), haft)
	_mesh_inst(Vector3(0.10, 0.16, 0.05), Vector3(0, 0.44, 0.10), head_red) # head
	_mesh_inst(Vector3(0.03, 0.20, 0.02), Vector3(0, 0.44, 0.20), steel) # blade edge
	_mesh_inst(Vector3(0.08, 0.10, 0.06), Vector3(0, 0.44, -0.03), head_red) # poll


func _build_pistol() -> void:
	# Compact semi-auto: grip + slide along +Y (barrel = +Y).
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.metallic = 0.4
	dark.roughness = 0.5
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.30, 0.30, 0.32)
	steel.metallic = 0.8
	steel.roughness = 0.35
	var grip := _mesh_inst(Vector3(0.055, 0.16, 0.07), Vector3(0, -0.05, 0.01), dark)
	grip.rotation.x = 0.18
	_mesh_inst(Vector3(0.05, 0.20, 0.065), Vector3(0, 0.13, 0), steel) # slide
	_mesh_inst(Vector3(0.02, 0.03, 0.02), Vector3(0, 0.24, 0), dark) # front sight


func _build_shotgun() -> void:
	# Pump shotgun: wooden stock/fore-end + long barrel along +Y.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.40, 0.26, 0.14)
	wood.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.25, 0.27)
	steel.metallic = 0.8
	steel.roughness = 0.40
	_mesh_inst(Vector3(0.06, 0.22, 0.07), Vector3(0, -0.14, 0.02), wood) # stock
	_cyl_inst(0.028, 0.028, 0.62, Vector3(0, 0.28, 0), steel) # barrel
	_mesh_inst(Vector3(0.07, 0.12, 0.08), Vector3(0, 0.05, 0), wood) # pump
	_mesh_inst(Vector3(0.025, 0.035, 0.025), Vector3(0, 0.60, 0), steel) # bead


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
	# Nail bat carried in the right hand. The visual parents the pivot to
	# the forearm so the swing below is arms-driven.
	_weapon_pivot = Node3D.new()
	(_visual as PlayerVisual).attach_weapon(_weapon_pivot)
	_build_bat()
	# Rest orientation is set by PlayerVisual.attach_weapon (bat rides in
	# the hand, business end angled down-forward).
	_build_swoosh()


func _build_bat() -> void:
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


func _build_swoosh() -> void:
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
	# Streak quad lying in the swing plane, long axis along the blade so it
	# smears along the arc. The overhead chop rotates about the pivot's X
	# axis (swing in the YZ plane), so the streak is rotated 90 deg about Y
	# to put its long axis in that plane, normal along the swing axis.
	_swoosh.rotation = Vector3(0.0, PI * 0.5, 0.0) # quad normal -> swing axis
	_swoosh.position = Vector3(0.03, 0.42, 0)
	_swoosh.visible = false
	_weapon_pivot.add_child(_swoosh)


func try_attack() -> void:
	if _health.is_dead() or _cd > 0.0:
		return
	# Guns fire through RangedCombat (hitscan); melee swings below.
	if weapons != null and ranged != null and WeaponManager.is_gun(weapons.current):
		ranged.try_fire()
		return
	var def := _melee_def()
	if _survival != null and not _survival.spend_stamina(float(def["stamina"])):
		return # gassed: blocked with HUD/audio feedback, no cooldown burned
	_cd = _cd_dur
	_swing_t = _swing_dur
	_hit_done = false
	(_visual as PlayerVisual).play_attack(_swing_dur)
	Sound.play("swoosh")
	_noise.emit_noise(_player.global_position, float(def["noise"]))


func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_suppress = maxf(0.0, _suppress - delta)
	if _health.is_dead():
		return
	if _suppress <= 0.0 and (Input.is_action_just_pressed("attack") or _hud.consume_attack()):
		try_attack()
	if ranged != null:
		if Input.is_action_just_pressed("reload"):
			ranged.start_reload()
		if Input.is_action_just_pressed("weapon_swap") and weapons != null:
			weapons.cycle()
	_update_swing(delta)
	_update_sprint_noise(delta)


func _update_swing(delta: float) -> void:
	if _swing_t <= 0.0:
		return
	_swing_t -= delta
	var t := 1.0 - _swing_t / _swing_dur # 0 -> 1
	# The arm swing itself is driven by PlayerVisual's "attack" action (the
	# bat rides in the right hand, the left hand reaches a second grip point
	# on the handle for the two-handed overhead swing); combat only times
	# the hit + swoosh.
	_update_swoosh(t)
	if not _hit_done and t >= 0.45:
		_hit_done = true
		_apply_hit()
	if _swing_t <= 0.0 and _swoosh != null:
		_swoosh.visible = false


func _update_swoosh(t: float) -> void:
	# Streak flashes across the middle of the swing, then fades.
	if _swoosh == null:
		return
	if t > 0.20 and t < 0.78:
		_swoosh.visible = true
		var st := clampf((t - 0.20) / 0.58, 0.0, 1.0)
		_swoosh_mat.albedo_color.a = 0.5 * sin(st * PI)
	else:
		_swoosh.visible = false


func _apply_hit() -> void:
	var def := _melee_def()
	var yaw := (_visual as Node3D).rotation.y
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var hit_any := false
	var killed_any := false
	for z in _zombies.living_zombies():
		var to := z.global_position - _player.global_position
		to.y = 0.0
		if to.length() > float(def["range"]):
			continue
		if fwd.dot(to.normalized()) < cos(deg_to_rad(float(def["arc"]))):
			continue
		var bonus := _damage_bonus if weapons == null or weapons.current == WeaponManager.BAT else 0.0
		# Ragdoll launch: the axe hits hardest, the machete slices light.
		var launch := 1.0
		if weapons != null:
			match weapons.current:
				WeaponManager.MACHETE:
					launch = 0.85
				WeaponManager.FIRE_AXE:
					launch = 1.5
		var died: bool = z.take_damage(float(def["damage"]) + bonus, _player.global_position, launch)
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
