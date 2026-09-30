class_name ZombieAI
extends CharacterBody3D
## Phase 2 walker brain: WANDER -> SUSPICIOUS -> CHASE -> ATTACK -> LOSE.
## Vision cone + range (night: farther, wider; flashlight gives the player
## away from much farther). Hearing via NoiseBus. Simple steering with
## wall-slide + corner bias — no navmesh. No per-frame allocations.

enum State { WANDER, SUSPICIOUS, CHASE, ATTACK, LOSE }

const GRAVITY := 22.0
const WANDER_DAY := 1.2
const WANDER_NIGHT := 1.8
const CHASE_DAY := 2.7
const CHASE_NIGHT := 3.8
const VISION_DAY := 11.0
const VISION_NIGHT := 13.5
const FLASHLIGHT_BONUS := 7.0
const CONE_DAY := 75.0
const CONE_NIGHT := 90.0
const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 12.0
const ATTACK_COOLDOWN := 1.3
# Barricade pounding: zombies hammer boarded/closed doors with the same
# arms-only swipe (visual.play_lunge), body planted. Boards first, then
# the door bursts open (BarricadeManager owns HP/stages).
const POUND_DAMAGE := 8.0
const POUND_RANGE := 2.4
const POUND_COOLDOWN := 1.3
const LOSE_TIME := 4.0
const HEAR_MULT_NIGHT := 1.4
const MAX_HP := 100.0

var state: int = State.WANDER
var hp := MAX_HP
var spawn_pos := Vector3.ZERO

# Brute variant (building types: police station + other high-risk spots).
# Base Walker constants above are NEVER touched — brutes only scale via
# these multipliers, set by make_brute().
var is_brute := false
var max_hp := MAX_HP
var spd_mult := 1.0
var dmg_mult := 1.0

var player: PlayerController
var player_health: PlayerHealth
var barricades: BarricadeManager # wave loop: pound boarded/closed doors
var time_manager: TimeManager

var _night_f := 0.0
var _visible := false
var _vis_t := 0.0
var _wander_target := Vector3.ZERO
var _wander_t := 0.0
var _stimulus := Vector3.ZERO
var _look_t := 0.0
var _last_known := Vector3.ZERO
var _lose_t := 0.0
var _attack_cd := 0.0
var _attack_hit_t := -1.0
var _pound_cd := 0.0
var _pound_hit_t := -1.0
var _wall_bias := 1.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _dead := false
var _dead_t := 0.0

# Audio: vocal cooldown, footstep distance, state-change tracking.
var _vocal_t := 0.0
var _idle_vocal_t := 0.0 # QA: idle groans so zombies are heard, not just seen
var _snarl_t := 0.0
var _step_dist := 0.0
var _shuffle_alt := false
var _prev_state: int = State.WANDER

var _to := Vector3.ZERO
var _dir := Vector3.ZERO
var _last_launch := 1.0 # ragdoll launch factor of the killing blow
var _ragdoll: ProcRagdoll = null # live ragdoll, if the active cap allowed one

@onready var visual: ZombieVisual = $Visual


func _ready() -> void:
	floor_snap_length = 0.3
	spawn_pos = global_position
	_wander_target = global_position
	_vis_t = randf() * 0.2
	_idle_vocal_t = randf_range(2.0, 9.0) # stagger idle groans across the pack
	_stuck_pos = global_position


func setup(p: PlayerController, tm: TimeManager) -> void:
	player = p
	time_manager = tm
	player_health = p.get_node("Health") as PlayerHealth


## Brute: a riot-gear remnant. ~2.2x HP, slightly faster, hits harder, and
## visibly bulkier. Only spawned in designated high-risk interiors.
func make_brute() -> void:
	is_brute = true
	max_hp = 220.0
	hp = max_hp
	spd_mult = 1.22
	dmg_mult = 1.5
	if is_instance_valid(visual):
		visual.set_brute()


func reset() -> void:
	hp = max_hp
	_dead = false
	_dead_t = 0.0
	state = State.WANDER
	_visible = false
	_lose_t = 0.0
	_attack_cd = 0.0
	_attack_hit_t = -1.0
	_pound_cd = 0.0
	_pound_hit_t = -1.0
	global_position = spawn_pos
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	visible = true
	set_physics_process(true)
	$CollisionShape3D.disabled = false


func on_noise(pos: Vector3, radius: float) -> void:
	if _dead or state == State.CHASE or state == State.ATTACK:
		return
	var d := global_position.distance_to(pos)
	if d < radius * lerpf(1.0, HEAR_MULT_NIGHT, _night_f):
		_stimulus = pos
		state = State.SUSPICIOUS
		_look_t = 0.0


## Wave loop: wave completion counts dead-but-present corpses as cleared.
func is_dead() -> bool:
	return _dead


## Returns true if the blow killed the zombie (for hit feedback sizing).
## Returns true if the hit killed the zombie. `launch` scales the death
## ragdoll (bat ~1.0, shotgun ~2.8); default keeps old callers working.
func take_damage(amount: float, from_pos: Vector3, launch := 1.0) -> bool:
	if _dead:
		return false
	hp -= amount
	_last_launch = launch
	_to = global_position - from_pos
	_to.y = 0.0
	if _to.length() > 0.01:
		velocity += _to.normalized() * 5.0
	# Getting hit gets its attention.
	_last_known = player.global_position if player else _last_known
	_visible = true
	_lose_t = 0.0
	if hp <= 0.0:
		_die()
		return true
	visual.play_hit_reaction(_to)
	visual.flash_hit()
	if state != State.CHASE and state != State.ATTACK and player:
		state = State.CHASE
	return false


func _die() -> void:
	_dead = true
	_dead_t = 26.0 # HD pass: corpses persist a while, then sink away
	Sound.play_3d("zombie_die", global_position)
	$CollisionShape3D.disabled = true
	# Procedural ragdoll: body parts become live bodies, hurled away from
	# the killing blow. If the active cap is hit, fall back to the classic
	# crumple so the death still reads.
	var dir := _to
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = -global_transform.basis.z
		dir.y = 0.0
	_ragdoll = ProcRagdoll.spawn(self, visual.ragdoll_parts(),
		dir.normalized(), 5.5 * _last_launch)
	if _ragdoll != null:
		visual.set_ragdolled()
	else:
		visual.play_death() # fold into a crumple as the body falls


func _physics_process(delta: float) -> void:
	if _dead:
		_dead_t -= delta
		if _ragdoll != null:
			pass # the physics server owns the corpse now; leave it alone
		else:
			rotation.x = lerpf(rotation.x, -PI * 0.5, 1.0 - exp(-6.0 * delta))
			visual.tick_dead(delta)
		if _dead_t <= 1.5:
			# Sink the corpse into the ground over its last 1.5s, then free.
			if _ragdoll != null:
				_ragdoll.sink_by(delta * 1.0)
			else:
				position.y = -1.5 * (1.0 - _dead_t / 1.5)
		if _dead_t <= 0.0:
			queue_free()
		return
	_update_night()
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = 0.15 + randf() * 0.1
		_visible = _check_vision()
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_pound_cd = maxf(0.0, _pound_cd - delta)
	_vocal_t = maxf(0.0, _vocal_t - delta)
	_snarl_t = maxf(0.0, _snarl_t - delta)
	_update_idle_groan(delta)

	match state:
		State.WANDER:
			_do_wander(delta)
		State.SUSPICIOUS:
			_do_suspicious(delta)
		State.CHASE:
			_do_chase(delta)
		State.ATTACK:
			_do_attack(delta)
		State.LOSE:
			_do_lose(delta)

	if state != _prev_state:
		_on_state_changed(state)
		_prev_state = state

	velocity.y -= GRAVITY * delta
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.5
	move_and_slide()
	_update_stuck(delta)

	var planar := Vector2(velocity.x, velocity.z).length()
	visual.tick(delta, planar, planar > 0.3)
	_update_footsteps(delta, planar)


## Groan when the zombie notices something; snarls are handled at the lunge.
func _on_state_changed(new_state: int) -> void:
	if _vocal_t > 0.0:
		return
	if new_state == State.SUSPICIOUS or new_state == State.CHASE:
		Sound.play_3d("groan%d" % randi_range(1, 4), global_position,
			0.0, randf_range(0.92, 1.08), 30.0)
		_vocal_t = 5.0


## QA fix: zombies groan idly on a timer when the player is near — the
## early-warning system. Before this they only vocalized on spotting the
## player, so a quiet street sounded empty.
func _update_idle_groan(delta: float) -> void:
	if _dead:
		return
	_idle_vocal_t -= delta
	if _idle_vocal_t > 0.0:
		return
	_idle_vocal_t = randf_range(7.0, 14.0)
	if _vocal_t > 0.0 or player == null:
		return
	if player_health != null and player_health.is_dead():
		return
	if global_position.distance_to(player.global_position) > 20.0:
		return
	Sound.play_3d("groan%d" % randi_range(1, 4), global_position,
		0.0, randf_range(0.85, 1.0), 30.0)
	_vocal_t = 5.0


func _update_footsteps(delta: float, planar: float) -> void:
	if planar > 0.4 and is_on_floor():
		_step_dist += planar * delta
		if _step_dist >= 2.3:
			_step_dist = 0.0
			_shuffle_alt = not _shuffle_alt
			Sound.play_3d("shuffle1" if _shuffle_alt else "shuffle2", global_position)
	else:
		_step_dist = 0.0


func _update_night() -> void:
	var ang := time_manager.time_hours / 24.0 * TAU - PI * 0.5
	_night_f = 1.0 - smoothstep(-0.06, 0.22, sin(ang))


func _vision_range() -> float:
	var r := lerpf(VISION_DAY, VISION_NIGHT, _night_f)
	if _night_f > 0.5 and (1.0 - _night_f) < 0.35:
		r += FLASHLIGHT_BONUS # flashlight gives you away at night
	return r


func _check_vision() -> bool:
	if player == null or player_health == null or player_health.is_dead():
		return false
	_to = player.global_position - global_position
	_to.y = 0.0
	var dist := _to.length()
	if dist > _vision_range():
		return false
	if dist > 1.2:
		var fwd := Basis(Vector3.UP, visual.rotation.y) * Vector3(0, 0, -1)
		var cone := lerpf(CONE_DAY, CONE_NIGHT, _night_f)
		if fwd.dot(_to.normalized()) < cos(deg_to_rad(cone * 0.5)):
			return false
	# Line of sight: anything solid between us blocks it.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.5, 0),
		player.global_position + Vector3(0, 1.0, 0))
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == player


func _face(pos: Vector3) -> void:
	_to = pos - global_position
	if Vector2(_to.x, _to.z).length() > 0.05:
		visual.set_target_yaw(atan2(-_to.x, -_to.z))


func _steer(delta: float, target: Vector3, speed: float) -> void:
	_to = target - global_position
	_to.y = 0.0
	var dist := _to.length()
	_dir = _to / dist if dist > 0.25 else Vector3.ZERO
	if is_on_wall() and _dir != Vector3.ZERO:
		var n := get_wall_normal()
		n.y = 0.0
		n = n.normalized()
		# Slide along the wall + tangent bias to work around corners.
		_dir = _dir - n * _dir.dot(n)
		if _dir.length() < 0.2:
			_dir = n.cross(Vector3.UP) * _wall_bias
		else:
			_dir = (_dir.normalized() + n.cross(Vector3.UP) * 0.6 * _wall_bias).normalized()
	# Exponentially damped toward the desired velocity (frame-rate
	# independent): turns and starts ramp instead of snapping.
	var k := 1.0 - exp(-8.0 * delta)
	velocity.x = lerpf(velocity.x, _dir.x * speed, k)
	velocity.z = lerpf(velocity.z, _dir.z * speed, k)
	if _dir != Vector3.ZERO:
		visual.set_target_yaw(atan2(-_dir.x, -_dir.z))


func _update_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t >= 1.0:
		_stuck_t = 0.0
		if global_position.distance_to(_stuck_pos) < 0.4 and state != State.ATTACK:
			_wall_bias = -_wall_bias # try the other way around
		_stuck_pos = global_position


func _do_wander(delta: float) -> void:
	if _visible:
		state = State.CHASE
		_last_known = player.global_position
		_lose_t = 0.0
		return
	_wander_t -= delta
	_to = _wander_target - global_position
	_to.y = 0.0
	if _to.length() < 1.0 or _wander_t <= 0.0:
		_wander_target = global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_wander_t = randf_range(4.0, 8.0)
	_steer(delta, _wander_target, lerpf(WANDER_DAY, WANDER_NIGHT, _night_f) * spd_mult)


func _do_suspicious(delta: float) -> void:
	if _visible:
		state = State.CHASE
		_last_known = player.global_position
		_lose_t = 0.0
		return
	_to = _stimulus - global_position
	_to.y = 0.0
	if _to.length() < 1.2:
		# Arrived: look around, then give up.
		_look_t += delta
		visual.set_target_yaw(visual.rotation.y + delta * 1.2)
		# Eased stop instead of a hard zero: no velocity snap.
		var stop_k := 1.0 - exp(-10.0 * delta)
		velocity.x = lerpf(velocity.x, 0.0, stop_k)
		velocity.z = lerpf(velocity.z, 0.0, stop_k)
		if _look_t > 2.5:
			state = State.WANDER
			_wander_t = 0.0
	else:
		_look_t = 0.0
		_steer(delta, _stimulus, lerpf(1.6, 2.2, _night_f))


func _do_chase(delta: float) -> void:
	if player_health.is_dead():
		state = State.WANDER
		return
	if _visible:
		_lose_t = 0.0
		_last_known = player.global_position
	else:
		_lose_t += delta
		if _lose_t > LOSE_TIME:
			state = State.LOSE
			return
	var dist := Vector2(
		player.global_position.x - global_position.x,
		player.global_position.z - global_position.z).length()
	if _pound_door_first():
		return
	if dist < ATTACK_RANGE:
		state = State.ATTACK
		return
	_face(player.global_position)
	_steer(delta, player.global_position, lerpf(CHASE_DAY, CHASE_NIGHT, _night_f) * spd_mult)


## Wave loop: a closed door (boarded or not) between the zombie and the
## player gets pounded instead of attacking through it. Returns true when
## pounding took over this tick.
func _pound_door_first() -> bool:
	if barricades == null:
		return false
	var door := barricades.nearest_closed_door(global_position, POUND_RANGE)
	if door.is_empty():
		return false
	_do_pound(door)
	return true


func _do_pound(door: Dictionary) -> void:
	var delta := get_physics_process_delta_time()
	var dp := door["pos"] as Vector3
	_face(dp)
	# Eased stop while pounding: body planted, arms do the work.
	var k := 1.0 - exp(-10.0 * delta)
	velocity.x = lerpf(velocity.x, 0.0, k)
	velocity.z = lerpf(velocity.z, 0.0, k)
	if _pound_cd <= 0.0:
		_pound_cd = POUND_COOLDOWN
		_pound_hit_t = 0.22
		visual.play_lunge() # arms-only swipe reads as pounding
		if _snarl_t <= 0.0:
			Sound.play_3d("snarl", global_position, 0.0, randf_range(0.94, 1.06))
			_snarl_t = 3.0
	if _pound_hit_t > 0.0:
		_pound_hit_t -= delta
		if _pound_hit_t <= 0.0 \
				and global_position.distance_to(dp) < POUND_RANGE + 0.6:
			barricades.pound(String(door["key"]), POUND_DAMAGE)


func _do_attack(delta: float) -> void:
	if player_health.is_dead():
		state = State.WANDER
		return
	if _pound_door_first():
		return
	_face(player.global_position)
	# Eased stop while attacking: no velocity snap.
	var atk_k := 1.0 - exp(-10.0 * delta)
	velocity.x = lerpf(velocity.x, 0.0, atk_k)
	velocity.z = lerpf(velocity.z, 0.0, atk_k)
	var dist := Vector2(
		player.global_position.x - global_position.x,
		player.global_position.z - global_position.z).length()
	if dist > ATTACK_RANGE * 1.4:
		state = State.CHASE
		_attack_hit_t = -1.0
		return
	if _attack_cd <= 0.0:
		_attack_cd = ATTACK_COOLDOWN
		_attack_hit_t = 0.22
		visual.play_lunge()
		if _snarl_t <= 0.0:
			Sound.play_3d("snarl", global_position, 0.0, randf_range(0.94, 1.06))
			_snarl_t = 3.0
	if _attack_hit_t > 0.0:
		_attack_hit_t -= delta
		if _attack_hit_t <= 0.0 and dist < ATTACK_RANGE * 1.25:
			player_health.damage(ATTACK_DAMAGE * dmg_mult, global_position)


func _do_lose(delta: float) -> void:
	if _visible:
		state = State.CHASE
		_last_known = player.global_position
		_lose_t = 0.0
		return
	_to = _last_known - global_position
	_to.y = 0.0
	if _to.length() < 1.5:
		state = State.WANDER
		_wander_t = 0.0
	else:
		_steer(delta, _last_known, lerpf(CHASE_DAY, CHASE_NIGHT, _night_f) * 0.8 * spd_mult)
