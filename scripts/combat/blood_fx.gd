class_name BloodFX
extends Node3D
## Pooled dark-red blood bursts for melee connects. CPUParticles3D
## (mobile-safe), pre-built pool — burst() just repositions + restarts,
## so there is zero allocation on the hit path.

const POOL := 10

var _pool: Array[CPUParticles3D] = []
var _next := 0


func _ready() -> void:
	top_level = true # bursts live in world space, not on the player
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.05, 0.04) # dark arterial red
	mat.roughness = 0.55
	mesh.material = mat
	for i in POOL:
		var p := CPUParticles3D.new()
		p.amount = 16
		p.lifetime = 0.5
		p.one_shot = true
		p.explosiveness = 0.85
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.14
		p.direction = Vector3(0, 1, 0)
		p.spread = 42.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.5
		p.gravity = Vector3(0, -13, 0)
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		p.mesh = mesh
		p.emitting = false
		add_child(p)
		_pool.append(p)


func burst(pos: Vector3) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.global_position = pos
	p.restart()
