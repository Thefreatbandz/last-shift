class_name ZombieVisual
extends Node3D
## Phase 2 procedural walker, HD upgrade: sharper low-poly anatomy built from
## tapered frustums — defined skull (brow ridge, cheek planes, sunken
## sockets), exposed bone (forearm, shin, ribs, teeth), torn cloth strips
## hanging off the shirt/sleeves, per-instance body types (lanky / stocky /
## gaunt via seeded body scale). Same builder pattern as PlayerVisual
## (pivoted limbs) and the same public API: set_target_yaw, tick,
## tick_dead (death crumple), play_lunge, play_hit_reaction, flash_hit,
## set_eye_glow. All materials remain STATIC and shared across instances
## (mobile-first). Eyes glow at night.

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D

var _phase := 0.0
var _target_yaw := 0.0
var _lunge_t := 0.0
var _head_base_y := 0.0

# --- Hit feedback (combat): flinch overlay + white/red damage flash. ---
var _flinch_t := 0.0
const FLINCH_TIME := 0.30
# Snapshot-relative absolute flinch overlay: play_hit_reaction snapshots
# every flinch channel; _apply_flinch writes snapshot + envelope * amount
# each frame after the base pose. The shamble can write whatever it likes
# underneath — the flinch always wins while active, can never accumulate,
# and leaves zero residue.
var _flinch_snap := {}
var _flash_t := 0.0
var _flash_on := false
var _meshes: Array[MeshInstance3D] = []

# Phase 3: idle variation — occasional twitches so no two zombies stand alike.
# Offsets are applied differentially (current minus previous frame) so the
# base pose always wins back with zero residual when the twitch ends.
var _twitch_t := 2.0
var _twitch_kind := 0 # 0 none, 1 head snap, 2 arm spasm, 3 body shudder
var _twitch_dur := 0.5
var _twitch_el := 0.0
var _twitch_dir := 1.0
var _twitch_prev := 0.0
static var _flash_mat: StandardMaterial3D = null

# Death crumple: folded over ~0.45s by tick_dead (called from the AI's dead
# branch), on top of the whole-body fall-flat the AI already applies.
var _dead_t := -1.0
const DEAD_TIME := 0.45

# Shared materials, built once for every zombie.
static var _mats: Dictionary = {}


static func shared_mats() -> Dictionary:
	if _mats.is_empty():
		_mats["skin"] = _mk(Color(0.52, 0.58, 0.46), 0.85) # pale grey-green
		_mats["skin_dark"] = _mk(Color(0.38, 0.44, 0.34), 0.9)
		_mats["shirt"] = _mk(Color(0.30, 0.28, 0.32), 0.95) # torn dark shirt
		_mats["shirt_b"] = _mk(Color(0.36, 0.26, 0.20), 0.95) # variant: filthy brown
		_mats["shirt_c"] = _mk(Color(0.22, 0.26, 0.30), 0.95) # variant: dead blue
		_mats["shirt_dark"] = _mk(Color(0.18, 0.17, 0.20), 0.95)
		_mats["pants"] = _mk(Color(0.25, 0.24, 0.28), 0.95) # ripped trousers
		_mats["pants_b"] = _mk(Color(0.30, 0.28, 0.20), 0.95) # variant: khaki
		_mats["wound"] = _mk(Color(0.32, 0.10, 0.08), 1.0) # dark wounds
		_mats["blood"] = _mk(Color(0.22, 0.05, 0.05), 0.6) # dried blood
		_mats["bone"] = _mk(Color(0.78, 0.72, 0.58), 0.7) # exposed bone
		_mats["hair"] = _mk(Color(0.16, 0.13, 0.10), 1.0) # matted hair
		var eye := StandardMaterial3D.new()
		eye.albedo_color = Color(0.85, 0.82, 0.55)
		eye.emission_enabled = true
		eye.emission = Color(0.9, 0.85, 0.45)
		eye.emission_energy_multiplier = 0.0
		_mats["eye"] = eye
	return _mats


static func _mk(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func set_eye_glow(energy: float) -> void:
	var eye := shared_mats()["eye"] as StandardMaterial3D
	eye.emission_energy_multiplier = energy


func _ready() -> void:
	shared_mats()
	_build()
	_head_base_y = _head.position.y
	_collect_meshes(self)
	_get_flash_mat()


## Brute variant look: riot-gear remnant. Bulkier body, tactical vest,
## shoulder pads, cracked riot helmet. Called by ZombieAI.make_brute().
func set_brute() -> void:
	_body.scale = Vector3(1.32, 1.10, 1.22)
	var M := shared_mats()
	var gear: Material = M["pants"] # dark charcoal
	# Tactical vest over the torso.
	_box(_body, Vector3(0.58, 0.52, 0.44), Vector3(0, 1.12, 0.02), gear)
	_box(_body, Vector3(0.40, 0.30, 0.05), Vector3(0, 1.14, -0.20),
		M["shirt_dark"]) # vest front plate
	# Shoulder pads.
	_box(_body, Vector3(0.24, 0.18, 0.32), Vector3(-0.38, 1.36, 0), gear)
	_box(_body, Vector3(0.24, 0.18, 0.32), Vector3(0.38, 1.36, 0), gear)
	# Cracked riot helmet.
	_box(_head, Vector3(0.36, 0.22, 0.38), Vector3(0, 0.13, -0.01), gear)
	_box(_head, Vector3(0.30, 0.10, 0.02), Vector3(0, 0.02, -0.19),
		M["wound"]) # shattered visor
	_meshes.clear()
	_collect_meshes(self) # include the gear in the hit-flash pass
	# NOTE: set_brute recollects; cleared first (called after _ready's pass).


func set_target_yaw(y: float) -> void:
	_target_yaw = y


func play_lunge() -> void:
	_lunge_t = 0.38


## Called by ZombieAI.take_damage: quick stagger — torso rocks back, head
## snaps, arms flail up — blended as an overlay on top of the shamble.
func play_hit_reaction(_from_dir: Vector3) -> void:
	# Unwind any in-flight flinch so rapid hits can't stack residue.
	if _flinch_t > 0.0:
		_restore_flinch_snap()
	_flinch_snap = {
		"rx": _body.rotation.x, "pz": _body.position.z,
		"head_x": _head.rotation.x,
		"arm_l": _arm_l.rotation.x, "arm_r": _arm_r.rotation.x,
		"arml_z": _arm_l.rotation.z, "armr_z": _arm_r.rotation.z,
	}
	_flinch_t = FLINCH_TIME


func _restore_flinch_snap() -> void:
	if _flinch_snap.is_empty():
		return
	_body.rotation.x = _flinch_snap["rx"]
	_body.position.z = _flinch_snap["pz"]
	_head.rotation.x = _flinch_snap["head_x"]
	_arm_l.rotation.x = _flinch_snap["arm_l"]
	_arm_r.rotation.x = _flinch_snap["arm_r"]
	_arm_l.rotation.z = _flinch_snap["arml_z"]
	_arm_r.rotation.z = _flinch_snap["armr_z"]


## Brief white/red emissive flash so the connect reads even at distance.
func flash_hit() -> void:
	_flash_t = 0.13
	_set_flash(true)


## Called once by ZombieAI._die: folds the body into a crumple.
func play_death() -> void:
	# Unwind any in-flight flinch so the corpse starts from the base pose.
	if _flinch_t > 0.0:
		_restore_flinch_snap()
	_flinch_t = 0.0
	_dead_t = 0.0


func tick(delta: float, speed: float, moving: bool) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-6.0 * delta))
	if _lunge_t > 0.0:
		_lunge_t -= delta
		_lunge(delta)
	elif moving:
		_shamble(delta, speed)
	else:
		_idle_sway(delta)
	if _flinch_t > 0.0:
		_apply_flinch(delta)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_flash(false)


## Death branch: the AI rotates the whole body flat; this folds the limbs
## in so it reads as a crumple, not a stiff board falling over.
func tick_dead(delta: float) -> void:
	if _dead_t < 0.0:
		return
	_apply_twitch(delta, false) # finish any in-flight twitch, start none
	_dead_t += delta
	var t := clampf(_dead_t / DEAD_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, 3.0) # ease-out cubic
	_body.position.y = -0.34 * e # torso sinks toward the ground
	_body.rotation.x = 0.34 + 0.55 * e # folds forward at the waist
	_body.rotation.z = 0.22 * e # slight sideways twist
	_head.rotation.x = 0.18 + 0.85 * e # chin drops to chest
	_head.rotation.z = 0.35 * e
	_arm_l.rotation.x = -0.55 - 0.55 * e
	_arm_r.rotation.x = -0.75 - 0.45 * e
	_arm_l.rotation.z = 0.10 + 0.55 * e # arms fold inward
	_arm_r.rotation.z = -0.14 - 0.55 * e
	_leg_l.rotation.x = 0.25 * e
	_leg_r.rotation.x = -0.30 * e
	_shin_l.rotation.x = -0.55 * e
	_shin_r.rotation.x = -0.70 * e


func _apply_flinch(delta: float) -> void:
	# Snapshot-relative absolute writes: snapshot + full current envelope
	# offset. Envelope 0 -> 1 -> 0 over FLINCH_TIME; net is exactly zero.
	_flinch_t -= delta
	var t := clampf(1.0 - _flinch_t / FLINCH_TIME, 0.0, 1.0)
	var f := sin(t * PI)
	var s := _flinch_snap
	_body.position.z = s["pz"] + f * 0.14 # shoved BACKWARD, away from the attacker
	_body.rotation.x = s["rx"] + f * 0.45 # torso rocks BACK, away from the attacker
	_head.rotation.x = s["head_x"] + f * 0.55 # head snaps back
	_arm_l.rotation.x = s["arm_l"] - f * 0.9 # arms flail
	_arm_r.rotation.x = s["arm_r"] - f * 0.9
	_arm_l.rotation.z = s["arml_z"] + f * 0.4
	_arm_r.rotation.z = s["armr_z"] - f * 0.4


func _set_flash(on: bool) -> void:
	if _flash_on == on:
		return
	_flash_on = on
	for m in _meshes:
		m.material_overlay = _flash_mat if on else null


func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		_collect_meshes(c)


static func _get_flash_mat() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.82, 0.78)
	return _flash_mat


func _shamble(delta: float, speed: float) -> void:
	# Slow, dragging, asymmetric shamble with arm lag.
	_phase += delta * (2.2 + speed * 1.1)
	var s := sin(_phase)
	var s2 := sin(_phase * 0.5 + 1.3) # asymmetry: one leg drags
	var swing := 0.42 + speed * 0.06
	_leg_l.rotation.x = s * swing
	_leg_r.rotation.x = -s2 * swing * 0.8
	_shin_l.rotation.x = -maxf(0.0, -s) * 0.5
	_shin_r.rotation.x = -maxf(0.0, s2) * 0.35 # dragging leg barely bends
	# Dangling arms: hang forward-down, lag behind the body sway.
	var lag := sin(_phase - 0.9)
	_arm_l.rotation.x = -0.55 + lag * 0.12
	_arm_r.rotation.x = -0.75 + sin(_phase * 0.5 + 0.4) * 0.15
	_arm_l.rotation.z = 0.10 + s * 0.04
	_arm_r.rotation.z = -0.14 + s2 * 0.05
	# Heavy hunch + lateral sway + head loll.
	_body.rotation.x = 0.34
	_body.rotation.z = sin(_phase * 0.5) * 0.08
	_body.position.y = absf(cos(_phase)) * 0.035
	_head.position.y = _head_base_y - absf(cos(_phase)) * 0.015
	_head.rotation.z = sin(_phase * 0.5 + 0.7) * 0.20
	_head.rotation.x = 0.18 + sin(_phase * 0.33) * 0.07
	_apply_twitch(delta) # keep advancing: never freeze a twitch mid-flight


func _idle_sway(delta: float) -> void:
	_phase += delta * 1.1
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 0.08)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 0.08)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.55, 0.08)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.75, 0.08)
	_body.rotation.x = lerpf(_body.rotation.x, 0.34, 0.08)
	_body.rotation.z = sin(_phase) * 0.035
	_head.rotation.z = sin(_phase * 0.7) * 0.12
	_head.rotation.x = 0.18
	_apply_twitch(delta)


func _apply_twitch(delta: float, can_trigger := true) -> void:
	# Additive overlay: every few seconds one random twitch fires.
	# The twitch MUST advance in every animation state (not just idle):
	# the offsets are differential and only net back to zero if the
	# twitch runs to completion. A twitch frozen mid-flight by a state
	# change used to leave the head permanently twisted.
	_twitch_t -= delta
	if can_trigger and _twitch_kind == 0 and _twitch_t <= 0.0:
		_twitch_kind = randi_range(1, 3)
		_twitch_dur = randf_range(0.35, 0.65)
		_twitch_el = 0.0
		_twitch_dir = 1.0 if randf() < 0.5 else -1.0
		_twitch_prev = 0.0
		_twitch_t = randf_range(2.5, 6.5)
	if _twitch_kind == 0:
		return
	_twitch_el += delta
	var t := clampf(_twitch_el / _twitch_dur, 0.0, 1.0)
	var f := sin(t * PI)
	var d := f - _twitch_prev # differential: no accumulation, no residue
	_twitch_prev = f
	match _twitch_kind:
		1: # head snap
			_head.rotation.y += d * 0.70 * _twitch_dir
			_head.rotation.x = 0.18 - f * 0.22 # base pose sets this absolutely
		2: # arm spasm
			_arm_r.rotation.x -= d * 0.80
			_arm_r.rotation.z -= d * 0.50 * _twitch_dir
		3: # body shudder
			_body.rotation.z += d * 0.12 * _twitch_dir
			_body.rotation.x -= d * 0.10
	if t >= 1.0:
		_twitch_kind = 0
		_twitch_prev = 0.0


func _lunge(delta: float) -> void:
	# Snappy forward pitch, arms thrown up toward the victim.
	var t := 1.0 - _lunge_t / 0.38 # 0 -> 1
	var up := sin(t * PI) # 0 up 1 down 0
	_body.rotation.x = 0.34 + up * 0.35
	_arm_l.rotation.x = -0.55 - up * 0.9
	_arm_r.rotation.x = -0.75 - up * 0.9
	_head.rotation.x = 0.18 + up * 0.25
	_leg_l.rotation.x = 0.3 * up
	_leg_r.rotation.x = -0.25 * up
	_apply_twitch(delta, false) # finish any in-flight twitch, start none


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Tapered box frustum: flat-shaded, 12 tris. top/bot are Vector2(width,
## depth) at +h/2 and -h/2 — the workhorse of the HD low-poly look.
func _frustum(parent: Node3D, top: Vector2, bot: Vector2, h: float,
		pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var tx := top.x * 0.5
	var tz := top.y * 0.5
	var bx := bot.x * 0.5
	var bz := bot.y * 0.5
	var hy := h * 0.5
	var t := [Vector3(-tx, hy, -tz), Vector3(tx, hy, -tz),
		Vector3(tx, hy, tz), Vector3(-tx, hy, tz)]
	var b := [Vector3(-bx, -hy, -bz), Vector3(bx, -hy, -bz),
		Vector3(bx, -hy, bz), Vector3(-bx, -hy, bz)]
	# CCW from outside: top, bottom, front(-z), back(+z), right(+x), left(-x).
	var quads := [
		[t[3], t[2], t[1], t[0]],
		[b[0], b[1], b[2], b[3]],
		[b[0], b[1], t[1], t[0]],
		[b[2], b[3], t[3], t[2]],
		[b[2], b[1], t[1], t[2]],
		[b[0], b[3], t[3], t[0]],
	]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for vi in tri:
				verts.append(q[vi])
				normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	var M := shared_mats()
	# Per-instance variety: pick a shirt/pants set and a body type from the
	# shared palette — zero extra materials, every zombie reads different.
	var shirt: Material = M["shirt"]
	var pants: Material = M["pants"]
	var roll := randf()
	if roll < 0.33:
		shirt = M["shirt_b"]
	elif roll < 0.66:
		shirt = M["shirt_c"]
	if randf() < 0.4:
		pants = M["pants_b"]
	_body = Node3D.new()
	_body.rotation.x = 0.34 # permanent hunch
	add_child(_body)
	var bt := randf() # body type
	if bt < 0.33:
		_body.scale = Vector3(0.90, 1.10, 0.90) # lanky: tall, narrow
	elif bt < 0.66:
		_body.scale = Vector3(1.16, 0.94, 1.08) # stocky: wide, short
	else:
		_body.scale = Vector3(0.84, 1.02, 0.84) # gaunt: skeletal
	_build_legs(M, pants)
	_build_torso(M, shirt)
	_build_arms(M, shirt)
	_build_head(M)


func _build_legs(M: Dictionary, pants: Material) -> void:
	# Tapered thighs, ripped trousers; one shin stripped to the bone.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side, 0.92, 0.0)
		_body.add_child(leg)
		_frustum(leg, Vector2(0.19, 0.21), Vector2(0.14, 0.16), 0.38,
			Vector3(0, -0.19, 0), pants)
		# Torn cuff flap.
		_box(leg, Vector3(0.05, 0.14, 0.02), Vector3(0.08 * side, -0.36, -0.09),
			pants, Vector3(0.5, 0, 0.3 * side))
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.38, 0)
		leg.add_child(shin)
		# Knee joint block.
		_box(shin, Vector3(0.16, 0.12, 0.17), Vector3(0, -0.02, 0), M["skin_dark"])
		if side < 0.0:
			# Left: flesh shin with a deep gash, shoe intact.
			_frustum(shin, Vector2(0.14, 0.16), Vector2(0.10, 0.12), 0.32,
				Vector3(0, -0.20, 0), pants)
			_box(shin, Vector3(0.09, 0.16, 0.02), Vector3(0.02, -0.20, -0.075),
				M["wound"], Vector3(0.1, 0, 0.15)) # gash
			_box(shin, Vector3(0.16, 0.10, 0.28), Vector3(0, -0.40, -0.04),
				M["shirt_dark"]) # shoe
			_leg_l = leg
			_shin_l = shin
		else:
			# Right: trousers torn away — bare tibia, bloody foot, no shoe.
			_box(shin, Vector3(0.055, 0.30, 0.055), Vector3(0.015, -0.21, 0),
				M["bone"], Vector3(0.06, 0, 0.05)) # tibia
			_box(shin, Vector3(0.045, 0.28, 0.045), Vector3(-0.035, -0.21, 0.01),
				M["bone"], Vector3(-0.05, 0, -0.06)) # fibula
			_box(shin, Vector3(0.10, 0.10, 0.13), Vector3(0, -0.06, 0),
				M["wound"]) # flesh remnant at knee
			_frustum(shin, Vector2(0.11, 0.12), Vector2(0.13, 0.22), 0.09,
				Vector3(0, -0.40, -0.03), M["blood"]) # mangled foot
			_leg_r = leg
			_shin_r = shin


func _build_torso(M: Dictionary, shirt: Material) -> void:
	# Tapered torso, ripped open at the chest: ribs + bite wound.
	_frustum(_body, Vector2(0.44, 0.30), Vector2(0.36, 0.26), 0.48,
		Vector3(0, 1.16, 0.02), shirt)
	# Torn-open chest: dark cavity, rib slivers, bite wound.
	_box(_body, Vector3(0.22, 0.24, 0.03), Vector3(-0.05, 1.14, -0.115), M["wound"])
	for i in 2:
		_box(_body, Vector3(0.16 - 0.02 * i, 0.025, 0.02),
			Vector3(-0.05, 1.18 - 0.07 * i, -0.128), M["bone"],
			Vector3(0, 0, 0.12 * (i - 0.5))) # exposed ribs
	_box(_body, Vector3(0.13, 0.11, 0.02), Vector3(-0.05, 1.06, -0.128),
		M["blood"]) # bite wound
	# Blood streak down the shirt.
	_box(_body, Vector3(0.07, 0.22, 0.02), Vector3(0.08, 1.02, -0.125),
		M["blood"])
	# Hanging cloth strips off the ripped hem — they sway with the shamble
	# via the body's rotation (rigid, cheap, reads as motion).
	for i in 2:
		var sx := -0.06 + 0.12 * i
		_box(_body, Vector3(0.055, 0.14, 0.015),
			Vector3(sx, 0.86, -0.12), shirt,
			Vector3(0, 0, 0.14 * (1 if i % 2 == 0 else -1)))
	# Shoulder pad of bunched torn cloth (left; the right sleeve is
	# already ragged).
	_box(_body, Vector3(0.16, 0.10, 0.18), Vector3(-0.25, 1.36, 0),
		M["shirt_dark"], Vector3(0, 0, 0.25))


func _build_arms(M: Dictionary, shirt: Material) -> void:
	# Dangle forward-down; one forearm stripped to the bone, torn sleeves.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.26 * side, 1.34, 0.0)
		arm.rotation.x = -0.65
		_body.add_child(arm)
		_frustum(arm, Vector2(0.15, 0.16), Vector2(0.11, 0.13), 0.28,
			Vector3(0, -0.14, 0), shirt) # sleeve
		# Torn sleeve strips.
		_box(arm, Vector3(0.04, 0.12, 0.015), Vector3(0.06 * side, -0.30, -0.06),
			shirt, Vector3(0.4, 0, 0.5 * side))
		if side < 0.0:
			# Left: bare forearm with a wound, claw hand.
			_frustum(arm, Vector2(0.11, 0.12), Vector2(0.08, 0.09), 0.24,
				Vector3(0, -0.38, 0), M["skin"])
			_box(arm, Vector3(0.10, 0.09, 0.02), Vector3(0, -0.36, -0.06),
				M["wound"])
			_frustum(arm, Vector2(0.09, 0.10), Vector2(0.06, 0.11), 0.10,
				Vector3(0, -0.54, -0.01), M["skin_dark"]) # claw hand
			_arm_l = arm
		else:
			# Right: flesh torn away — radius + ulna, one dangling finger bone.
			_box(arm, Vector3(0.04, 0.22, 0.04), Vector3(0.02, -0.38, 0),
				M["bone"], Vector3(0.08, 0, 0.04))
			_box(arm, Vector3(0.035, 0.20, 0.035), Vector3(-0.03, -0.38, 0.01),
				M["bone"], Vector3(-0.06, 0, -0.05))
			_box(arm, Vector3(0.09, 0.08, 0.10), Vector3(0, -0.28, 0),
				M["wound"]) # flesh remnant at elbow
			_box(arm, Vector3(0.022, 0.07, 0.022), Vector3(0, -0.53, -0.01),
				M["bone"], Vector3(0.3, 0, 0)) # finger bone
			_arm_r = arm


func _build_head(M: Dictionary) -> void:
	# Defined skull: tapered cranium (wide brow, narrow jaw), brow ridge,
	# cheek planes, sunken sockets, exposed teeth under the mouth gash.
	_head = Node3D.new()
	_head.position = Vector3(0, 1.50, -0.10)
	_head.rotation.x = 0.18
	_body.add_child(_head)
	_frustum(_head, Vector2(0.24, 0.25), Vector2(0.17, 0.19), 0.26,
		Vector3(0, 0.01, 0), M["skin"]) # tapered skull
	# Brow ridge + sunken eye sockets.
	_box(_head, Vector3(0.20, 0.045, 0.05), Vector3(0, 0.055, -0.105),
		M["skin_dark"], Vector3(-0.15, 0, 0))
	for side in [-1.0, 1.0]:
		_box(_head, Vector3(0.075, 0.07, 0.03),
			Vector3(0.058 * side, 0.005, -0.10), M["skin_dark"]) # socket
		_box(_head, Vector3(0.05, 0.045, 0.02),
			Vector3(0.058 * side, 0.005, -0.115), M["eye"])
		# Cheek planes: angled slabs under the sockets.
		_box(_head, Vector3(0.07, 0.05, 0.04),
			Vector3(0.085 * side, -0.055, -0.075), M["skin"],
			Vector3(0.3, 0.35 * side, 0))
	# Nose: broken wedge, one nostril dark.
	_frustum(_head, Vector2(0.035, 0.02), Vector2(0.05, 0.06), 0.09,
		Vector3(0.01, -0.03, -0.115), M["skin_dark"],
		Vector3(0.2, 0, 0.1))
	# Mouth gash with exposed teeth; slack jaw below.
	_box(_head, Vector3(0.17, 0.05, 0.03), Vector3(0, -0.095, -0.10), M["wound"])
	_box(_head, Vector3(0.13, 0.028, 0.015), Vector3(0, -0.088, -0.112),
		M["bone"]) # teeth
	_frustum(_head, Vector2(0.15, 0.16), Vector2(0.12, 0.13), 0.09,
		Vector3(0, -0.155, -0.01), M["skin_dark"]) # slack jaw
	# Head wound with bone showing.
	_box(_head, Vector3(0.12, 0.10, 0.03), Vector3(0.07, 0.10, 0.02),
		M["wound"], Vector3(0, 0, 0.4))
	_box(_head, Vector3(0.06, 0.05, 0.035), Vector3(0.07, 0.10, 0.015),
		M["bone"], Vector3(0, 0, 0.4)) # cracked skull
	# Matted hair: top cap, back mass, one clump over the forehead.
	_frustum(_head, Vector2(0.25, 0.26), Vector2(0.26, 0.27), 0.10,
		Vector3(0, 0.165, 0.01), M["hair"])
	_box(_head, Vector3(0.24, 0.18, 0.10), Vector3(0, 0.07, 0.13), M["hair"])
	_box(_head, Vector3(0.06, 0.10, 0.05), Vector3(-0.05, 0.14, -0.09),
		M["hair"], Vector3(-0.3, 0, 0.2)) # clump over forehead
