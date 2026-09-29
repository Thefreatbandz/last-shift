class_name PlayerVisual
extends Node3D
## Procedural survivor visual: an ordinary person in worn clothes, NOT a
## cartoon toy. Realistic proportions, muted gritty materials, pivoted limbs
## for sin-based walk animation, body bob, lean and idle breathing.
## A chest-mounted flashlight SpotLight3D switches on at night.

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: MeshInstance3D
var _flashlight: SpotLight3D

var _phase := 0.0
var _idle_t := 0.0
var _target_yaw := 0.0

# Materials (shared across parts).
var _m_hoodie: StandardMaterial3D
var _m_pants: StandardMaterial3D
var _m_boots: StandardMaterial3D
var _m_skin: StandardMaterial3D
var _m_hair: StandardMaterial3D
var _m_pack: StandardMaterial3D
var _m_dark: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build()


func set_target_yaw(y: float) -> void:
	_target_yaw = y


func set_flashlight(on: bool) -> void:
	_flashlight.light_energy = 2.6 if on else 0.0


func tick(delta: float, speed: float, moving: bool) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-10.0 * delta))
	var k := 1.0 - exp(-8.0 * delta)
	if moving:
		var intensity := clampf(speed / 5.2, 0.0, 1.4)
		_phase += delta * (4.0 + speed * 1.6)
		var s := sin(_phase)
		_leg_l.rotation.x = s * 0.60 * intensity
		_leg_r.rotation.x = -s * 0.60 * intensity
		_arm_l.rotation.x = -s * 0.45 * intensity
		_arm_r.rotation.x = s * 0.45 * intensity
		_body.position.y = absf(cos(_phase)) * 0.055 * intensity
		_body.rotation.x = -0.10 * intensity
		_torso.scale.y = 1.0
		_idle_t = 0.0
	else:
		_idle_t += delta
		var b := sin(_idle_t * 2.2)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, k)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, b * 0.03, k)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -b * 0.03, k)
		_body.position.y = b * 0.012
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, k)
		_torso.scale.y = 1.0 + b * 0.015 # breathing


func _make_materials() -> void:
	_m_hoodie = _mat(Color(0.20, 0.22, 0.25)) # dark charcoal hoodie
	_m_pants = _mat(Color(0.29, 0.29, 0.24)) # cargo pants
	_m_boots = _mat(Color(0.12, 0.10, 0.09)) # worn boots
	_m_skin = _mat(Color(0.79, 0.61, 0.47), 0.7) # skin
	_m_hair = _mat(Color(0.16, 0.11, 0.08)) # messy dark hair
	_m_pack = _mat(Color(0.35, 0.36, 0.24)) # olive backpack
	_m_dark = _mat(Color(0.10, 0.10, 0.11)) # zipper / details


func _mat(c: Color, rough := 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)

	# Legs (pivot at the hip).
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.14 * side, 0.92, 0.0)
		_body.add_child(leg)
		_part(leg, Vector3(0.20, 0.50, 0.24), Vector3(0, -0.25, 0), _m_pants) # thigh
		_part(leg, Vector3(0.17, 0.42, 0.20), Vector3(0, -0.68, 0), _m_pants) # shin
		_part(leg, Vector3(0.19, 0.14, 0.32), Vector3(0, -0.86, -0.04), _m_boots) # boot
		if side < 0.0:
			_leg_l = leg
		else:
			_leg_r = leg

	# Torso: hoodie + zipper + hood + backpack.
	_torso = _part(_body, Vector3(0.50, 0.60, 0.30), Vector3(0, 1.22, 0), _m_hoodie)
	_part(_body, Vector3(0.06, 0.52, 0.03), Vector3(0, 1.22, -0.155), _m_dark) # zipper
	_part(_body, Vector3(0.30, 0.16, 0.14), Vector3(0, 1.50, 0.17), _m_hoodie) # hood
	_part(_body, Vector3(0.38, 0.48, 0.20), Vector3(0, 1.24, 0.25), _m_pack) # backpack
	_part(_body, Vector3(0.40, 0.10, 0.22), Vector3(0, 1.52, 0.25), _m_dark) # bedroll

	# Arms (pivot at the shoulder).
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.33 * side, 1.46, 0.0)
		_body.add_child(arm)
		_part(arm, Vector3(0.15, 0.60, 0.17), Vector3(0, -0.30, 0), _m_hoodie)
		_part(arm, Vector3(0.13, 0.14, 0.14), Vector3(0, -0.65, 0), _m_skin) # hand
		if side < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm

	# Head: face + messy hair cap.
	var head := Node3D.new()
	head.position = Vector3(0, 1.68, 0)
	_body.add_child(head)
	_part(head, Vector3(0.26, 0.28, 0.26), Vector3.ZERO, _m_skin)
	_part(head, Vector3(0.28, 0.14, 0.28), Vector3(0, 0.12, 0.01), _m_hair)
	var tuft := _part(head, Vector3(0.16, 0.10, 0.16), Vector3(0.04, 0.20, -0.02), _m_hair)
	tuft.rotation = Vector3(0.0, 0.4, 0.25)

	# Chest-mounted flashlight (SpotLight3D shines along its -Z).
	var lamp_mount := Node3D.new()
	lamp_mount.position = Vector3(0.18, 1.42, -0.20)
	lamp_mount.rotation.x = -0.32 # tilt slightly down
	_body.add_child(lamp_mount)
	var lamp_body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.055
	cyl.height = 0.16
	lamp_body.mesh = cyl
	lamp_body.rotation.x = PI * 0.5
	lamp_body.material_override = _m_dark
	lamp_mount.add_child(lamp_body)
	_flashlight = SpotLight3D.new()
	_flashlight.spot_range = 15.0
	_flashlight.spot_angle = 34.0
	_flashlight.light_color = Color(1.0, 0.95, 0.85)
	_flashlight.light_energy = 0.0
	_flashlight.shadow_enabled = false
	lamp_mount.add_child(_flashlight)
