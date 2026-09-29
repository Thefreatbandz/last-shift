class_name PlayerHealth
extends Node
## Phase 2: survivor health pool. Damage flashes the HUD vignette; death
## raises the YOU DIED screen; tapping respawns at the safehouse doorstep
## with zombies reset. Attached as the "Health" child of Player.

const MAX_HP := 100.0
const RESPAWN_POS := Vector3(-6, 0.3, -13) # safehouse doorstep

var hp := MAX_HP

var _dead := false
var _player: PlayerController
var _hud: Hud
var _zombies: ZombieManager
var _respawn_pos := RESPAWN_POS # Phase 3: claiming the safehouse moves this


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


func damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	_hud.set_health(hp, MAX_HP)
	_hud.flash_damage()
	(_player.get_node("Visual") as PlayerVisual).play_hurt_flinch()
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
