class_name SurvivalStats
extends Node
## Survival meters: stamina, hunger, thirst.
## - Stamina drains on sprint and per melee swing; regenerates walking/idle.
##   At 0 you cannot sprint; swings are blocked with HUD/audio feedback.
## - Hunger drains over ~24 in-game hours; canned food restores +40.
##   At 0: HP drains 2/s and max stamina halves.
## - Thirst drains over ~14 in-game hours; clean water restores +50.
##   At 0: stamina regeneration stops + a dehydration vignette pulses.
## Sleeping costs hunger/thirst (you wake up hungry) — survival pressure.
## Drain is driven by in-game hours so sleep/time-skips cost correctly.

const MAX := 100.0
const SPRINT_DRAIN := 12.0 # stamina per real second while sprinting
const ATTACK_COST := 8.0 # stamina per bat swing
const REGEN_WALK := 10.0 # per real second
const REGEN_IDLE := 18.0
const SPRINT_MIN := 10.0 # stamina required to START sprinting
const HUNGER_PER_HOUR := 100.0 / 24.0 # full -> empty over ~2 in-game days
const THIRST_PER_HOUR := 100.0 / 14.0 # full -> empty over ~14 in-game hours
const STARVE_HP_DRAIN := 2.0 # HP per real second at 0 hunger
const FOOD_RESTORE := 40.0
const WATER_RESTORE := 50.0
const WARN := 25.0 # HUD warning threshold
const GROWL_MIN := 18.0 # seconds between stomach growls
const GROWL_MAX := 32.0

var stamina := MAX
var hunger := MAX
var thirst := MAX

var _player: PlayerController
var _hud: Hud
var _health: PlayerHealth
var _tm: TimeManager
var _last_hours := -1.0
var _sprinting := false
var _growl_t := 8.0


func setup(player: PlayerController, hud: Hud, health: PlayerHealth,
		tm: TimeManager) -> void:
	_player = player
	_hud = hud
	_health = health
	_tm = tm
	_push_hud()


func _process(delta: float) -> void:
	if _health != null and _health.is_dead():
		return # frozen while dead
	tick(delta)


func tick(delta: float) -> void:
	_tick_clocks(delta)
	_tick_stamina(delta)
	_tick_starvation(delta)
	_tick_growl(delta)
	_push_hud()


func _tick_clocks(delta: float) -> void:
	# Hunger/thirst drain on in-game time, not real time, so sleeping and
	# day-skips cost correctly. (Sleep jumps call on_sleep() directly.)
	if _tm == null:
		return
	var h := _tm.time_hours
	if _last_hours >= 0.0:
		var dh := h - _last_hours
		if dh < 0.0:
			dh += 24.0
		hunger = maxf(0.0, hunger - HUNGER_PER_HOUR * dh)
		thirst = maxf(0.0, thirst - THIRST_PER_HOUR * dh)
	_last_hours = h


func stamina_max() -> float:
	return 50.0 if hunger <= 0.0 else MAX


func _tick_stamina(delta: float) -> void:
	_sprinting = _player != null and _player.sprint_active
	if _sprinting:
		stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	elif thirst > 0.0:
		var rate := REGEN_IDLE
		if _player != null and _player.moving:
			rate = REGEN_WALK
		stamina = minf(stamina_max(), stamina + rate * delta)
	else:
		# Dehydrated: no regeneration (stamina only goes down).
		stamina = minf(stamina, stamina_max())
	# Starving clamps the pool down.
	stamina = minf(stamina, stamina_max())


func _tick_starvation(delta: float) -> void:
	if hunger <= 0.0 and _health != null:
		_health.drain(STARVE_HP_DRAIN * delta)


func _tick_growl(delta: float) -> void:
	if hunger >= WARN:
		return
	_growl_t -= delta
	if _growl_t <= 0.0:
		_growl_t = randf_range(GROWL_MIN, GROWL_MAX)
		# Low-pitched groan doubles as a stomach growl — no new audio file.
		Sound.play("groan1", -14.0, 0.45)


func _push_hud() -> void:
	if _hud == null:
		return
	_hud.set_survival(stamina / stamina_max(), hunger / MAX, thirst / MAX)
	_hud.set_dehydrated(thirst <= 0.0)


## Sprint gating: need SPRINT_MIN to start, but can ride it down to 0.
func can_sprint() -> bool:
	if _sprinting:
		return stamina > 0.0
	return stamina >= SPRINT_MIN


## Called by combat before a swing. Returns false (with feedback) if gassed.
func try_attack_cost() -> bool:
	if stamina < ATTACK_COST:
		if _hud != null:
			_hud.pulse_stamina()
		Sound.play("click", -8.0, 0.6) # dull denied blip
		return false
	stamina = maxf(0.0, stamina - ATTACK_COST)
	return true


func eat_food() -> void:
	hunger = minf(MAX, hunger + FOOD_RESTORE)
	Sound.play("eat")
	_push_hud()


func drink_water() -> void:
	thirst = minf(MAX, thirst + WATER_RESTORE)
	Sound.play("eat", 0.0, 1.3)
	_push_hud()


## Sleeping costs a little hunger/thirst — you wake up hungry.
func on_sleep(hours_slept: float) -> void:
	hunger = maxf(0.0, hunger - HUNGER_PER_HOUR * hours_slept)
	thirst = maxf(0.0, thirst - THIRST_PER_HOUR * hours_slept)
	_push_hud()


func on_respawn() -> void:
	stamina = MAX
	hunger = maxf(hunger, 60.0)
	thirst = maxf(thirst, 60.0)
	_last_hours = -1.0
	_push_hud()
