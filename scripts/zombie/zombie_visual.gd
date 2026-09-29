class_name ZombieVisual
extends Node3D
## Phase 2 procedural walker: hunched, grey-green skin, torn clothes, dark
## wounds/blood patches, dangling arms, matted hair. Same builder pattern as
## PlayerVisual (low-poly primitives, pivoted limbs) but every material is
## STATIC and shared across all zombie instances (mobile-first: 6 zombies).
## Shamble walk (dragging, swaying, head loll) + attack lunge. Eyes glow at
## night so night aggression reads visually.

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

# Shared materials, built once for every zombie.
static var _mats: Dictionary = {}


static func shared_mats() -> Dictionary:
	if _mats.is_empty():
		_mats["skin"] = _mk(Color(0.52, 0.58, 0.46), 0.85) # pale grey-green
		_mats["skin_dark"] = _mk(Color(0.38, 0.44, 0.34), 0.9)
		_mats["shirt"] = _mk(Color(0.30, 0.28, 0.32), 0.95) # torn dark shirt
		_mats["shirt_dark"] = _mk(Color(0.18, 0.17, 0.20), 0.95)
		_mats["pants"] = _mk(Color(0.25, 0.24, 0.28), 0.95) # ripped trousers
		_mats["wound"] = _mk(Color(0.32, 0.10, 0.08), 1.0) # dark wounds
		_mats["blood"] = _mk(Color(0.22, 0.05, 0.05), 0.6) # dried blood
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


func set_target_yaw(y: float) -> void:
	_target_yaw = y


func play_lunge() -> void:
	_lunge_t = 0.38


## Called by ZombieAI.take_damage: quick stagger — torso rocks back, head
## snaps, arms flail up — blended as an overlay on top of the shamble.
func play_hit_reaction(_from_dir: Vector3) -> void:
	_flinch_t = FLINCH_TIME


## Brief white/red emissive flash so the connect reads even at distance.
func flash_hit() -> void:
	_flash_t = 0.13
	_set_flash(true)


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


func _apply_flinch(delta: float) -> void:
	# Additive overlay: envelope 0 -> 1 -> 0 over FLINCH_TIME.
	_flinch_t -= delta
	var t := clampf(1.0 - _flinch_t / FLINCH_TIME, 0.0, 1.0)
	var f := sin(t * PI)
	_body.rotation.x -= f * 0.45 # torso rocks back
	_body.position.z += f * 0.14 # shoved backward
	_head.rotation.x -= f * 0.55 # head snaps back
	_arm_l.rotation.x -= f * 0.9 # arms flail up
	_arm_r.rotation.x -= f * 0.9
	_arm_l.rotation.z += f * 0.4
	_arm_r.rotation.z -= f * 0.4


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
	# Slow, dragging, asymmetric shamble.
	_phase += delta * (2.2 + speed * 1.1)
	var s := sin(_phase)
	var s2 := sin(_phase * 0.5 + 1.3) # asymmetry: one leg drags
	var swing := 0.42 + speed * 0.06
	_leg_l.rotation.x = s * swing
	_leg_r.rotation.x = -s2 * swing * 0.8
	_shin_l.rotation.x = -maxf(0.0, -s) * 0.5
	_shin_r.rotation.x = -maxf(0.0, s2) * 0.35 # dragging leg barely bends
	# Dangling arms: hang forward-down, slight sway, one arm twitches.
	_arm_l.rotation.x = -0.55 + s * 0.10
	_arm_r.rotation.x = -0.75 + s2 * 0.14
	_arm_l.rotation.z = 0.10 + s * 0.03
	_arm_r.rotation.z = -0.14 + s2 * 0.04
	# Heavy hunch + lateral sway + head loll.
	_body.rotation.x = 0.34
	_body.rotation.z = sin(_phase * 0.5) * 0.07
	_body.position.y = absf(cos(_phase)) * 0.03
	_head.position.y = _head_base_y - absf(cos(_phase)) * 0.012
	_head.rotation.z = sin(_phase * 0.5 + 0.7) * 0.16
	_head.rotation.x = 0.18 + sin(_phase * 0.33) * 0.05


func _idle_sway(delta: float) -> void:
	_phase += delta * 1.1
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, 0.08)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, 0.08)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.55, 0.08)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.75, 0.08)
	_body.rotation.x = lerpf(_body.rotation.x, 0.34, 0.08)
	_body.rotation.z = sin(_phase) * 0.03
	_head.rotation.z = sin(_phase * 0.7) * 0.10
	_head.rotation.x = 0.18
	_apply_twitch(delta)


func _apply_twitch(delta: float) -> void:
	# Additive overlay: every few seconds one random twitch fires.
	_twitch_t -= delta
	if _twitch_kind == 0 and _twitch_t <= 0.0:
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


func _build() -> void:
	var M := shared_mats()
	_body = Node3D.new()
	_body.rotation.x = 0.34 # permanent hunch
	add_child(_body)
	# --- Legs: ripped trousers, one shoe missing (bloody foot). ---
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side, 0.92, 0.0)
		_body.add_child(leg)
		_box(leg, Vector3(0.17, 0.38, 0.19), Vector3(0, -0.19, 0), M["pants"])
		_box(leg, Vector3(0.18, 0.10, 0.20), Vector3(0, -0.34, 0.01), M["shirt_dark"],
			Vector3(0.2 * side, 0, 0.15)) # torn cuff
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.38, 0)
		leg.add_child(shin)
		_box(shin, Vector3(0.15, 0.34, 0.16), Vector3(0, -0.17, 0), M["pants"])
		_box(shin, Vector3(0.10, 0.14, 0.05), Vector3(0.03, -0.10, -0.07), M["wound"]) # gash
		if side < 0.0:
			# Left shoe intact.
			_box(shin, Vector3(0.16, 0.10, 0.28), Vector3(0, -0.38, -0.04), M["shirt_dark"])
			_leg_l = leg
			_shin_l = shin
		else:
			# Right shoe lost: bare bloody foot.
			_box(shin, Vector3(0.13, 0.08, 0.24), Vector3(0, -0.38, -0.03), M["blood"])
			_leg_r = leg
			_shin_r = shin
	# --- Torso: torn shirt, wounds, dried blood. ---
	_box(_body, Vector3(0.40, 0.46, 0.26), Vector3(0, 1.16, 0.02), M["shirt"])
	_box(_body, Vector3(0.20, 0.22, 0.02), Vector3(-0.06, 1.12, -0.115), M["skin"]) # torn open
	_box(_body, Vector3(0.12, 0.10, 0.02), Vector3(-0.06, 1.10, -0.125), M["wound"]) # bite wound
	_box(_body, Vector3(0.16, 0.06, 0.27), Vector3(0.05, 0.98, 0.02), M["blood"]) # blood streak
	_box(_body, Vector3(0.42, 0.09, 0.28), Vector3(0, 0.95, 0.02), M["shirt_dark"],
		Vector3(0.15, 0, 0.1)) # ripped hem
	# --- Arms: dangle forward-down, torn sleeves, wounded forearm. ---
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.26 * side, 1.34, 0.0)
		arm.rotation.x = -0.65
		_body.add_child(arm)
		_box(arm, Vector3(0.13, 0.26, 0.14), Vector3(0, -0.13, 0), M["shirt"]) # sleeve
		_box(arm, Vector3(0.11, 0.22, 0.12), Vector3(0, -0.36, 0), M["skin"]) # bare forearm
		_box(arm, Vector3(0.10, 0.10, 0.11), Vector3(0, -0.52, 0), M["skin_dark"]) # hand
		if side < 0.0:
			_box(arm, Vector3(0.12, 0.09, 0.02), Vector3(0, -0.34, -0.06), M["wound"])
			_arm_l = arm
		else:
			_arm_r = arm
	# --- Head: pale, sunken eyes, slack jaw, matted hair, head wound. ---
	_head = Node3D.new()
	_head.position = Vector3(0, 1.48, -0.10)
	_head.rotation.x = 0.18
	_body.add_child(_head)
	_box(_head, Vector3(0.22, 0.24, 0.23), Vector3.ZERO, M["skin"])
	_box(_head, Vector3(0.18, 0.08, 0.20), Vector3(0, -0.13, -0.02), M["skin_dark"]) # slack jaw
	_box(_head, Vector3(0.19, 0.02, 0.01), Vector3(0, -0.10, -0.115), M["wound"]) # mouth gash
	_box(_head, Vector3(0.05, 0.045, 0.02), Vector3(-0.055, 0.01, -0.11), M["eye"])
	_box(_head, Vector3(0.05, 0.045, 0.02), Vector3(0.055, 0.01, -0.11), M["eye"])
	_box(_head, Vector3(0.13, 0.09, 0.03), Vector3(0.06, 0.10, 0.02), M["wound"],
		Vector3(0, 0, 0.4)) # head wound
	_box(_head, Vector3(0.24, 0.12, 0.24), Vector3(0, 0.12, 0.03), M["hair"]) # matted hair
	_box(_head, Vector3(0.05, 0.14, 0.16), Vector3(-0.11, 0.02, 0.04), M["hair"])
	_box(_head, Vector3(0.05, 0.14, 0.16), Vector3(0.11, 0.02, 0.04), M["hair"])
