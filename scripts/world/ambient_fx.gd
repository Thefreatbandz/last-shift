class_name AmbientFX
extends Node3D
## HD pass ambience: dust puffs kicked up while sprinting, and dead leaves
## drifting on the wind. Pooled CPUParticles3D + a handful of animated
## quads — cheap enough for phones, no per-frame allocation.

const DUST_POOL := 4
const LEAF_COUNT := 6

var _player: PlayerController
var _dust: Array[CPUParticles3D] = []
var _dust_next := 0
var _puff_t := 0.0
var _leaves: Array[MeshInstance3D] = []
var _leaf_age: Array[float] = []
var _leaf_vel: Array[Vector3] = []
var _wind := Vector3(0.85, 0, 0.4).normalized()


func setup(player: PlayerController) -> void:
	_player = player


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.50, 0.42, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.10, 0.16)
	mesh.material = mat
	for i in DUST_POOL:
		var p := CPUParticles3D.new()
		p.amount = 8
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.18
		p.direction = Vector3(0, 1, 0)
		p.spread = 55.0
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.0
		p.gravity = Vector3(0, -2.5, 0)
		p.damping_min = 2.0
		p.damping_max = 3.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.4
		p.mesh = mesh
		p.emitting = false
		add_child(p)
		_dust.append(p)
	# Wind-blown leaves: shared material, animated transforms.
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.45, 0.30, 0.14)
	lmat.roughness = 1.0
	var lmesh := BoxMesh.new()
	lmesh.size = Vector3(0.12, 0.015, 0.09)
	lmesh.material = lmat
	for i in LEAF_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = lmesh
		mi.top_level = true
		add_child(mi)
		_leaves.append(mi)
		_leaf_age.append(randf() * 6.0)
		_leaf_vel.append(Vector3.ZERO)
		_respawn_leaf(i, true)


func _respawn_leaf(i: int, anywhere := false) -> void:
	var mi := _leaves[i]
	var base := _player.global_position if _player != null else Vector3.ZERO
	var r := 14.0 if anywhere else 10.0
	mi.global_position = base + Vector3(
		randf_range(-r, r), randf_range(0.3, 1.6), randf_range(-r, r))
	_leaf_vel[i] = _wind * randf_range(1.2, 2.4) + Vector3(0, randf_range(-0.2, 0.1), 0)
	_leaf_age[i] = 0.0


func _process(delta: float) -> void:
	# Sprint dust at the player's heels.
	if _player != null and _player.sprint_active:
		var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
		if planar > 3.0:
			_puff_t -= delta
			if _puff_t <= 0.0:
				_puff_t = 0.18
				var p := _dust[_dust_next]
				_dust_next = (_dust_next + 1) % DUST_POOL
				p.global_position = _player.global_position + Vector3(0, 0.12, 0)
				p.restart()
	# Drifting leaves.
	for i in _leaves.size():
		_leaf_age[i] += delta
		var mi := _leaves[i]
		mi.global_position += _leaf_vel[i] * delta
		mi.rotation.y += delta * 3.0
		mi.rotation.x = sin(_leaf_age[i] * 5.0 + float(i)) * 0.6
		if _leaf_age[i] > 6.0:
			_respawn_leaf(i)
