class_name PlayerHealth
extends Node
## Phase 2: survivor health pool. Damage flashes the HUD vignette; death
## raises the YOU DIED screen; tapping respawns at the safehouse doorstep
## with zombies reset. Attached as the "Health" child of Player.

const MAX_HP := 100.0
const RESPAWN_POS := Vector3(-6, 0.3, -13) # safehouse doorstep

signal damaged # wave loop: timed healing is interrupted by damage

var hp := MAX_HP

var _dead := false
var _player: PlayerController
var _hud: Hud
var _zombies: ZombieManager
var _respawn_pos := RESPAWN_POS # Phase 3: claiming the safehouse moves this
var _last_from := Vector3.ZERO # where the killing blow came from


func setup(player: PlayerController, hud: Hud, zombies: ZombieManager) -> void:
	_player = player
	_hud = hud
	_zombies = zombies
	_hud.set_health(hp, MAX_HP)


func set_respawn(pos: Vector3) -> void:
	_respawn_pos = pos


func heal(amount: float) -> void:
	if _dead:
		return
	hp = minf(MAX_HP, hp + amount)
	_hud.set_health(hp, MAX_HP)
	Sound.set_heartbeat(hp < 30.0)


func is_dead() -> bool:
	return _dead


## Quiet HP loss (starvation, etc.): updates the HUD and death, but no
## damage flash or hurt sound — those would spam every frame.
func drain(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	_hud.set_health(hp, MAX_HP)
	if hp <= 0.0:
		_die()
	else:
		Sound.set_heartbeat(hp < 30.0 and hp > 0.0)


func damage(amount: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_last_from = from_pos
	hp = maxf(0.0, hp - amount)
	_hud.set_health(hp, MAX_HP)
	_hud.flash_damage()
	(_player.get_node("Visual") as PlayerVisual).play_hurt_flinch()
	damaged.emit()
	if hp <= 0.0:
		_die()
	else:
		Sound.play("hurt")
	Sound.set_heartbeat(hp < 30.0 and hp > 0.0)


func _die() -> void:
	_dead = true
	Sound.play("death")
	Sound.set_heartbeat(false)
	_hud.show_death()
	# Ragdoll: hurl the body away from whatever killed us. Same 6-active
	# cap as the zombies; if it's full the death overlay still reads fine.
	var visual := _player.get_node("Visual") as PlayerVisual
	var dir := _player.global_position - _last_from
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = -_player.global_transform.basis.z
		dir.y = 0.0
	var rag := ProcRagdoll.spawn(_player, visual.ragdoll_parts(),
		dir.normalized(), 7.0)
	if rag != null:
		visual.attach_ragdoll(rag)


func respawn() -> void:
	if not _dead:
		return
	_dead = false
	hp = MAX_HP
	_player.global_position = _respawn_pos
	_player.velocity = Vector3.ZERO
	_zombies.reset_all()
	_hud.set_health(hp, MAX_HP)
	_hud.hide_death()
	Sound.set_heartbeat(false)
