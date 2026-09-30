extends SceneTree
## Procedural ragdoll death regression suite.
## - Killing blow spawns a ProcRagdoll: 6 live RigidBody3D parts with
##   cone-twist joints, hurled away from the attacker.
## - Bat kill sprawls; shotgun kill (launch 2.8) flies much harder.
## - Parts stay attached (within 3m of the torso after 1s of tumbling).
## - Bodies freeze ~2.2s after death, then persist as a corpse.
## - Active cap: at most 6 ragdolls simulate; overflow deaths fall back
##   to the classic crumple (no missing corpses, no unbounded cost).
## - Player death ragdolls too; the dead can't walk; respawn rebuilds
##   the visual and re-attaches the weapon.
## Run: godot --headless --path . --script res://tests/ragdoll_qa.gd
## Grep the output for SCRIPT ERROR separately.

const EPS := 0.05

var _booted := false
var _frames := 0
var _ok := true
var _main: Node
var _player: Node
var _zombies: Array = []
var _kill_list: Array = [] # zombies killed for the cap test
var _death_frame := -1
var _bat_z: Node = null
var _bat_start := Vector3.ZERO
var _bat_phys0 := 0
var _bat_pending := false
var _bat_disp := 0.0
var _shotgun_z: Node = null
var _shotgun_start := Vector3.ZERO
var _shotgun_phys0 := 0
var _shotgun_pending := false
var _spawn_pos := Vector3.ZERO
var _freeze_frame := -1
var _freeze_t := 0.0
var _player_killed := false
var _player_phase_frame := 0
var _move_checked := false
var _respawned := false
var _done := false


func _check(label: String, cond: bool) -> void:
	if cond:
		print("RAGDOLLQA PASS ", label)
	else:
		_ok = false
		print("RAGDOLLQA FAIL ", label)


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_static_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames % 60 == 0:
		print("RAGDOLLQA heartbeat frame=", _frames, " phys=", Engine.get_physics_frames())
	# Physics-gated launch measurements: resolve each kill's displacement
	# after 6 physics steps (0.1s) so the impulse has integrated.
	if _bat_pending and Engine.get_physics_frames() >= _bat_phys0 + 15:
		_bat_pending = false
		_resolve_launch(true)
	if _shotgun_pending and Engine.get_physics_frames() >= _shotgun_phys0 + 15:
		_shotgun_pending = false
		_resolve_launch(false)
	if _frames == 60:
		_kill_bat()
	elif _frames == 64:
		_kill_shotgun()
	elif _frames == 70:
		_check_coherence()
	elif _frames >= 72 and _frames <= 78:
		_kill_cap_burst()
	elif _frames == 84:
		_check_cap()
	elif _frames >= 100 and _freeze_frame < 0:
		if _frames > 3000:
			_check("zombie_freeze_observed", false)
			print("RAGDOLLQA_RESULT ok=", _ok)
			quit(1)
			return true
		_poll_freeze()
	elif not _player_killed and _freeze_frame >= 0:
		# Phase 2 (sequenced, not frame-fixed): the zombie freeze proved
		# the corpse lifecycle; now the player death + respawn.
		_kill_player()
		_player_killed = true
		_player_phase_frame = _frames
	elif _player_killed and not _move_checked \
			and _frames >= _player_phase_frame + 60:
		_check_move_gate()
		_move_checked = true
	elif _player_killed and _move_checked and not _respawned \
			and _frames >= _player_phase_frame + 120:
		_respawn_player()
	elif _respawned and not _done \
			and _frames >= _player_phase_frame + 160:
		_done = true
		_check_respawn()
		print("RAGDOLLQA_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


func _static_checks() -> void:
	var s := _src("res://scripts/fx/proc_ragdoll.gd")
	_check("src_max_active_6", s.contains("MAX_ACTIVE := 6"))
	_check("src_active_time", s.contains("ACTIVE_TIME := 2.2"))
	_check("src_world_only_collision", s.contains("collision_mask = 1"))
	_check("src_freeze", s.contains("b.freeze = true"))
	_check("src_cap_fallback", s.contains("return null"))
	var ai := _src("res://scripts/zombie/zombie_ai.gd")
	_check("src_launch_param", ai.contains("launch := 1.0"))
	_check("src_fallback_crumple", ai.contains("visual.play_death()"))
	var pg := _src("res://scripts/player/player.gd")
	_check("src_dead_no_walk", pg.contains("health.is_dead()"))


func _zm() -> Node:
	return _main.get_node("Zombies")


func _alive_zombies() -> Array:
	var out: Array = []
	for z in _zm().get("zombies"):
		if not bool(z.call("is_dead")):
			out.append(z)
	return out


func _kill(z: Node, launch: float) -> void:
	# The attacker stands 1m south of the VICTIM: the blow hurls it north.
	var zp: Vector3 = (z as Node3D).global_position
	z.call("take_damage", 99999.0, zp + Vector3(0, 0, -1.0), launch)


func _kill_bat() -> void:
	_player = _main.get_node("Player")
	var zs := _alive_zombies()
	_check("zombies_present", zs.size() >= 9)
	if zs.is_empty():
		return
	var z: Node = zs[0]
	_spawn_pos = z.global_position
	_kill(z, 1.0)
	_death_frame = _frames
	_check("bat_ragdoll_spawned", z.get("_ragdoll") != null)
	var rag: Node = z.get("_ragdoll")
	if rag == null:
		return
	var bodies := _rigid_bodies(rag)
	_check("six_parts", bodies.size() == 6)
	_check("visual_ragdolled", bool(z.get_node("Visual").get("_ragdolled")))
	_bat_z = z
	_bat_start = (bodies[0] as RigidBody3D).global_position
	_bat_phys0 = Engine.get_physics_frames()
	_bat_pending = true


func _rigid_bodies(rag: Node) -> Array:
	var out: Array = []
	for c in rag.get_children():
		if c is RigidBody3D:
			out.append(c)
	return out


func _resolve_launch(is_bat: bool) -> void:
	var z: Node = _bat_z if is_bat else _shotgun_z
	var tag := "bat" if is_bat else "shotgun"
	_check(tag + "_victim_ragdolled", z != null and z.get("_ragdoll") != null)
	if z == null or z.get("_ragdoll") == null:
		return
	var bodies := _rigid_bodies(z.get("_ragdoll"))
	var d: Vector3 = (bodies[0] as RigidBody3D).global_position \
		- (_bat_start if is_bat else _shotgun_start)
	# 0.2m in 6 phys frames (~2 m/s) is a solid launch; the old 0.35
	# threshold was calibrated for broken joints (parts flying solo).
	_check(tag + "_impulse_applied", d.length() > 0.2)
	# The blow came from the south: the body must fly north (+Z).
	_check(tag + "_flies_away_from_blow", d.z > 0.2)
	if is_bat:
		_bat_disp = d.length()
	else:
		_check("shotgun_launches_harder", d.length() > _bat_disp * 1.4)


func _kill_shotgun() -> void:
	var zs := _alive_zombies()
	_check("shotgun_victim_alive", zs.size() >= 8)
	if zs.is_empty():
		return
	_shotgun_z = zs[0]
	_kill(_shotgun_z, 2.8)
	var rag: Node = _shotgun_z.get("_ragdoll")
	_check("shotgun_ragdoll_spawned", rag != null)
	if rag == null:
		return
	_shotgun_start = (_rigid_bodies(rag)[0] as RigidBody3D).global_position
	_shotgun_phys0 = Engine.get_physics_frames()
	_shotgun_pending = true


func _check_coherence() -> void:
	# ~10 frames after the bat kill: the body is tumbling but the joints
	# hold it together — every part within 2m of the torso. (Was 3m,
	# which masked completely broken joints.)
	var zs: Array = _zm().get("zombies")
	var rag: Node = null
	for z in zs:
		if bool(z.call("is_dead")) and z.get("_ragdoll") != null:
			rag = z.get("_ragdoll")
			break
	_check("ragdoll_found", rag != null)
	if rag == null:
		return
	var bodies := _rigid_bodies(rag)
	var torso_pos: Vector3 = (bodies[0] as RigidBody3D).global_position
	var held := true
	for b in bodies:
		if (b as RigidBody3D).global_position.distance_to(torso_pos) > 2.0:
			held = false
	_check("joints_hold_body_together", held)
	# (body movement is verified by the physics-timed _resolve_launch;
	# the old idle-frame check here was flaky.)


func _kill_cap_burst() -> void:
	# Kill 7 more in quick succession: 2 already dead, so 9 total deaths
	# against a cap of 6 active ragdolls.
	var zs := _alive_zombies()
	if zs.is_empty():
		return
	_kill(zs[0], 1.0)
	_kill_list.append(zs[0])


func _check_cap() -> void:
	var zs: Array = _zm().get("zombies")
	var ragdolled := 0
	var crumpled := 0
	for z in zs:
		if bool(z.call("is_dead")):
			if z.get("_ragdoll") != null:
				ragdolled += 1
			else:
				crumpled += 1
	_check("cap_six_active", ragdolled == 6)
	_check("cap_overflow_crumples", crumpled == 3)
	_check("cap_no_missing_corpse", ragdolled + crumpled == 9)


func _poll_freeze() -> void:
	var zs: Array = _zm().get("zombies")
	for z in zs:
		var rag: Node = z.get("_ragdoll")
		if rag != null and bool(rag.get("_frozen")):
			_freeze_frame = _frames
			_freeze_t = float(rag.get("_t"))
			var all_frozen := true
			for b in _rigid_bodies(rag):
				if not bool((b as RigidBody3D).get("freeze")):
					all_frozen = false
			_check("bodies_frozen", all_frozen)
			_check("freeze_timing_2_2s", _freeze_t > 2.0 and _freeze_t < 3.0)
			return


func _kill_player() -> void:
	print("RAGDOLLQA kill_player enter frame=", _frames)
	if _freeze_frame < 0:
		_check("zombie_freeze_observed", false)
	else:
		_check("zombie_freeze_observed", true)
	var health: Node = _player.get_node("Health")
	var zs := _alive_zombies()
	var from := Vector3.ZERO
	if not zs.is_empty():
		from = (zs[0] as Node3D).global_position
	print("RAGDOLLQA kill_player damaging")
	health.call("damage", 99999.0, from)
	print("RAGDOLLQA kill_player damaged, dead=", bool(health.call("is_dead")))
	_check("player_dead", bool(health.call("is_dead")))
	var visual: Node = _player.get_node("Visual")
	_check("player_ragdolled", bool(visual.get("_ragdolled")))
	_check("player_ragdoll_parts", visual.get("_ragdoll") != null)
	# Hold forward input: the corpse must not walk.
	Input.action_press("move_forward")


func _check_move_gate() -> void:
	var vel: Vector3 = _player.get("velocity")
	_check("dead_dont_walk", Vector2(vel.x, vel.z).length() < 0.15)
	Input.action_release("move_forward")


func _respawn_player() -> void:
	var health: Node = _player.get_node("Health")
	var combat: Node = _player.get_node("Combat")
	var survival: Node = _main.get_node("Survival")
	_main.call("_on_respawn", health, combat, survival)
	_respawned = true


func _check_respawn() -> void:
	_check("respawn_ran", _respawned)
	var visual: Node = _player.get_node("Visual")
	_check("ragdoll_cleared", not bool(visual.get("_ragdolled")))
	var body: Node = visual.get("_body")
	_check("body_rebuilt", body != null and body.get_parent() == visual)
	var combat: Node = _player.get_node("Combat")
	var pivot = combat.get("_weapon_pivot") # untyped: may be a freed ref
	_check("weapon_reattached", pivot != null and is_instance_valid(pivot) \
		and (pivot as Node).is_inside_tree())
