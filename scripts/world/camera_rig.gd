class_name CameraRig
extends Node3D
## Angled top-down follow camera (~55 degrees pitch). Smooth-lerps to the
## player with a velocity look-ahead so motion feels alive. Q/E rotates
## the yaw on desktop within this phase's limited-rotation design.

var target: Node3D
var yaw := 0.0

var _yaw_target := 0.0
var _look_ahead := 0.35

@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	_cam.position = Vector3(0.0, 12.4, 8.7)
	_cam.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	_cam.fov = 52.0
	_cam.far = 220.0


## Teleport the rig onto the target (used at spawn so the first frame is framed).
func snap() -> void:
	if target != null:
		global_position = _goal_pos()


func _process(delta: float) -> void:
	if Input.is_action_pressed("rotate_left"):
		_yaw_target += 1.7 * delta
	if Input.is_action_pressed("rotate_right"):
		_yaw_target -= 1.7 * delta
	yaw = lerp_angle(yaw, _yaw_target, 1.0 - exp(-8.0 * delta))
	rotation.y = yaw
	if target != null:
		global_position = global_position.lerp(_goal_pos(), 1.0 - exp(-6.0 * delta))


func _goal_pos() -> Vector3:
	var p := target.global_position
	var v := Vector3.ZERO
	if target is CharacterBody3D:
		v = (target as CharacterBody3D).velocity
		v.y = 0.0
	return p + v * _look_ahead
