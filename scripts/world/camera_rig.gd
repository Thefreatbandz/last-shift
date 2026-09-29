class_name CameraRig
extends Node3D
## Angled top-down follow camera (~55 degrees pitch). Smooth-lerps to the
## player with a velocity look-ahead so motion feels alive. Q/E rotates
## the yaw on desktop within this phase's limited-rotation design.

var target: Node3D
var yaw := 0.0

var _yaw_target := 0.0
var _look_ahead := 0.35

# Trauma-based screen shake (combat hit feedback). add_trauma() piles on,
# decays fast; the offset is trauma^2 so small hits barely nudge.
var _trauma := 0.0
var _base_cam_pos := Vector3.ZERO

@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	_cam.position = Vector3(0.0, 12.4, 8.7)
	_cam.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	_cam.fov = 52.0
	_cam.far = 220.0
	_base_cam_pos = _cam.position


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Teleport the rig onto the target (used at spawn so the first frame is framed).
func snap() -> void:
	if target != null:
		global_position = _goal_pos()


## Point the camera immediately (used at spawn so the safehouse, which can
## face +Z or -Z, never blocks the opening frame).
func set_yaw_immediate(v: float) -> void:
	yaw = v
	_yaw_target = v
	rotation.y = v


func _process(delta: float) -> void:
	if Input.is_action_pressed("rotate_left"):
		_yaw_target += 1.7 * delta
	if Input.is_action_pressed("rotate_right"):
		_yaw_target -= 1.7 * delta
	yaw = lerp_angle(yaw, _yaw_target, 1.0 - exp(-8.0 * delta))
	rotation.y = yaw
	if target != null:
		global_position = global_position.lerp(_goal_pos(), 1.0 - exp(-6.0 * delta))
	_update_shake(delta)


func _update_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - 1.8 * delta)
	var sh := _trauma * _trauma
	if sh > 0.00001:
		_cam.position = _base_cam_pos + Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		) * 0.38 * sh
		_cam.rotation.z = randf_range(-1.0, 1.0) * 0.035 * sh
	else:
		_cam.position = _base_cam_pos
		_cam.rotation.z = 0.0


func _goal_pos() -> Vector3:
	var p := target.global_position
	var v := Vector3.ZERO
	if target is CharacterBody3D:
		v = (target as CharacterBody3D).velocity
		v.y = 0.0
	return p + v * _look_ahead
