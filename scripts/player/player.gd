class_name PlayerController
extends CharacterBody3D
## Phase 1 survivor movement: camera-relative WASD/arrows + touch joystick,
## walk / run / sprint speed bands with smooth acceleration, and gravity.
## (Combat, dodge and interactions arrive in later phases.)

@export var walk_speed := 3.0
@export var run_speed := 5.2
@export var sprint_speed := 7.4
@export var acceleration := 14.0
@export var gravity := 22.0

var camera_rig: CameraRig
var hud: Hud

@onready var visual: PlayerVisual = $Visual


func _ready() -> void:
	floor_snap_length = 0.3


func _physics_process(delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint")
	if hud != null and hud.touch_mode:
		iv = hud.move_vector
		sprinting = hud.sprint_held

	var mag := clampf(iv.length(), 0.0, 1.0)
	var speed := lerpf(walk_speed, run_speed, mag)
	if sprinting and mag > 0.1:
		speed = sprint_speed

	var wish := Vector3.ZERO
	if mag > 0.05 and camera_rig != null:
		# Screen-up (away from camera) is -Z in rig space; rotate input by rig yaw.
		wish = (Basis(Vector3.UP, camera_rig.yaw) * Vector3(iv.x, 0.0, iv.y)).normalized()

	var target_v := wish * speed
	var k := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, target_v.x, k)
	velocity.z = lerpf(velocity.z, target_v.z, k)
	velocity.y -= gravity * delta
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.5
	move_and_slide()

	var planar := Vector2(velocity.x, velocity.z).length()
	if planar > 0.6 and wish != Vector3.ZERO:
		visual.set_target_yaw(atan2(-wish.x, -wish.z))
	visual.tick(delta, planar, planar > 0.4)
