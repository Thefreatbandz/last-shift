class_name RangedCombat
extends Node
## Hitscan gun combat: pistol + shotgun. Fires in the player's facing
## direction with slight aim assist (snaps up to AIM_ASSIST_DEG toward the
## nearest living zombie inside the gun's range). Raycasts against zombies
## (capsule test) with distance falloff; shotgun fires a pellet spread.
## Gunshots go through the existing NoiseBus so zombies hear them, flash
## a muzzle light, and cost stamina. Reloads pull from inventory ammo.

const AIM_ASSIST_DEG := 12.0

var mag := {} # gun id -> rounds currently in the magazine

var _player: PlayerController
var _hud: Hud
var _zombies: ZombieManager
var _noise: NoiseBus
var _inv: Inventory
var _survival: SurvivalStats
var _weapons: WeaponManager
var _visual: PlayerVisual
var _muzzle: OmniLight3D
var _muzzle_quad: MeshInstance3D
var _blood: BloodFX
var _flash_t := 0.0
var _cd := 0.0
var _reload_t := 0.0
var _reloading := ""


func setup(player: PlayerController, hud: Hud, zombies: ZombieManager,
		noise: NoiseBus, inv: Inventory, survival: SurvivalStats,
		weapons: WeaponManager) -> void:
	_player = player
	_hud = hud
	_zombies = zombies
	_noise = noise
	_inv = inv
	_survival = survival
	_weapons = weapons
	_visual = player.get_node("Visual") as PlayerVisual
	# Muzzle flash: small quad + light at the gun tip.
	_muzzle_quad = MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(0.35, 0.35)
	_muzzle_quad.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.30)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_quad.material_override = mat
	_muzzle_quad.visible = false
	_player.add_child(_muzzle_quad)
	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color(1.0, 0.70, 0.30)
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 8.0
	_player.add_child(_muzzle)
	_blood = BloodFX.new()
	_player.add_child(_blood) # BloodFX._ready sets top_level itself
	for id in WeaponManager.GUNS:
		mag[id] = int(WeaponManager.GUNS[id]["mag"])


func mag_in(id: String) -> int:
	return int(mag.get(id, 0))


func is_reloading() -> bool:
	return _reloading != ""


## Attack input for the equipped gun. Returns true if a shot was fired.
func try_fire() -> bool:
	var id := _weapons.current
	if not WeaponManager.is_gun(id):
		return false
	var g: Dictionary = WeaponManager.GUNS[id]
	if _cd > 0.0:
		return false
	if _reloading != "":
		return false
	if int(mag.get(id, 0)) <= 0:
		start_reload() # dry-fire: auto reload if ammo exists
		Sound.play_3d("reload", _player.global_position)
		return false
	if not _survival.spend_stamina(float(g["stamina"])):
		return false
	mag[id] = int(mag[id]) - 1
	_cd = float(g["cooldown"])
	_visual.play_shoot()
	_fire_pellets(id, g)
	_flash_t = 0.06
	_noise.emit_noise(_player.global_position, float(g["noise"]))
	Sound.play_3d(g["sound"], _player.global_position)
	if int(mag[id]) <= 0:
		start_reload() # empty: roll straight into a reload
	_weapons.refresh_display()
	return true


## R: reload the equipped gun from inventory ammo.
func start_reload() -> bool:
	var id := _weapons.current
	if not WeaponManager.is_gun(id):
		return false
	if _reloading != "":
		return false
	var g: Dictionary = WeaponManager.GUNS[id]
	var need: int = int(g["mag"]) - int(mag.get(id, 0))
	if need <= 0:
		return false
	var have: int = _inv.count(g["ammo"])
	if have <= 0:
		_hud.show_interact("NO AMMO", 1.2)
		return false
	_reloading = id
	_reload_t = float(g["reload"])
	Sound.play_3d("reload", _player.global_position)
	return true


func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta
	if _reloading != "":
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	if _flash_t > 0.0:
		_flash_t -= delta
	_muzzle_quad.visible = _flash_t > 0.0
	_muzzle.light_energy = 3.0 if _flash_t > 0.0 else 0.0
	if _muzzle_quad.visible:
		_muzzle_quad.global_position = _muzzle_pos()


func _finish_reload() -> void:
	var id := _reloading
	var g: Dictionary = WeaponManager.GUNS[id]
	var need: int = int(g["mag"]) - int(mag.get(id, 0))
	var take: int = mini(need, _inv.count(g["ammo"]))
	if take > 0:
		_inv.remove(g["ammo"], take)
		mag[id] = int(mag[id]) + take
		Sound.play_3d("reload", _player.global_position)
	_reloading = ""
	_weapons.refresh_display()


## Yaw the player faces (visual rotation).
func _aim_yaw() -> float:
	var yaw: float = (_visual as Node3D).rotation.y
	var origin := _player.global_position
	var best_yaw := yaw
	var best_score := AIM_ASSIST_DEG
	var g: Dictionary = WeaponManager.GUNS[_weapons.current]
	for z in _zombies.living_zombies():
		var to: Vector3 = z.global_position - origin
		to.y = 0.0
		var d := to.length()
		if d > float(g["range"]) + 1.0:
			continue
		var want := atan2(-to.x, -to.z)
		var diff := absf(rad_to_deg(angle_difference(yaw, want)))
		if diff < best_score:
			best_score = diff
			best_yaw = want
	return best_yaw


func _fire_pellets(id: String, g: Dictionary) -> void:
	var origin := _player.global_position + Vector3(0, 1.4, 0)
	var base_yaw := _aim_yaw()
	var pellets: int = int(g["pellets"])
	for i in pellets:
		var spread_rad := deg_to_rad(float(g["spread"])) * (0.0 if pellets == 1 else (randf() * 2.0 - 1.0))
		var dir := Vector3(-sin(base_yaw + spread_rad), 0, -cos(base_yaw + spread_rad))
		_hit_one(id, g, origin, dir.normalized())
	_flash_t = 0.06


func _hit_one(id: String, g: Dictionary, origin: Vector3, dir: Vector3) -> void:
	var rng_max := float(g["range"])
	var best: ZombieAI = null
	var best_t := rng_max
	for z in _zombies.living_zombies():
		var to: Vector3 = z.global_position + Vector3(0, 1.1, 0) - origin
		var t: float = to.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var perp: float = (to - dir * t).length()
		if perp < 0.55: # zombie capsule half-width
			best = z
			best_t = t
	if best != null:
		var fall := clampf(1.0 - best_t / rng_max * 0.5, 0.4, 1.0)
		var dmg: float = float(g["damage"]) * fall
		# Shotgun pellets launch the body; the pistol shoves it.
		var launch := 2.8 if id == WeaponManager.SHOTGUN else 1.5
		var died: bool = best.take_damage(dmg, _player.global_position, launch)
		_blood.burst(best.global_position + Vector3(0, 1.25, 0))
		if died:
			_blood.splat(best.global_position)


## World-space muzzle tip: ahead of the player, at shoulder height.
func _muzzle_pos() -> Vector3:
	return _player.global_position + Vector3(0, 1.35, 0) \
		+ Vector3(-sin((_visual as Node3D).rotation.y), 0, -cos((_visual as Node3D).rotation.y)) * 0.55
