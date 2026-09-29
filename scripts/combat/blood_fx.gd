class_name BloodFX
extends Node3D
## HD pass: richer melee blood. Pooled dark-red bursts + brighter arterial
## chunks (two CPUParticles3D per pool slot), and persistent ground splats
## (flat dark quads, pooled, fade after ~25s). CPUParticles3D throughout
## (mobile-safe); burst()/splat() just reposition + restart, so there is
## zero allocation on the hit path.

const POOL := 8
const SPLAT_POOL := 6
const SPLAT_LIFE := 25.0

var _pool: Array[CPUParticles3D] = []
var _chunks: Array[CPUParticles3D] = []
var _next := 0
var _splats: Array[MeshInstance3D] = []
var _splat_mats: Array[StandardMaterial3D] = []
var _splat_age: Array[float] = []
var _splat_next := 0


func _ready() -> void:
	top_level = true # bursts live in world space, not on the player
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.30, 0.05, 0.04) # dark arterial red
	dark.roughness = 0.55
	var dark_mesh := BoxMesh.new()
	dark_mesh.size = Vector3(0.07, 0.07, 0.07)
	dark_mesh.material = dark
	var bright := StandardMaterial3D.new()
	bright.albedo_color = Color(0.55, 0.10, 0.07) # fresh bright red
	bright.roughness = 0.4
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3(0.05, 0.05, 0.05)
	chunk_mesh.material = bright
	for i in POOL:
		var p := _make_burst(dark_mesh, 16, 2.5, 5.5, 0.5, 42.0)
		add_child(p)
		_pool.append(p)
		var c := _make_burst(chunk_mesh, 7, 3.5, 7.0, 0.65, 30.0)
		add_child(c)
		_chunks.append(c)
	# Ground splats: thin dark quads, one material each so they fade
	# independently (shared fade would pulse every splat at once).
	var splat_mesh := BoxMesh.new()
	splat_mesh.size = Vector3(1.0, 0.012, 1.0)
	for i in SPLAT_POOL:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.23, 0.045, 0.035, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		var mi := MeshInstance3D.new()
		mi.mesh = splat_mesh
		mi.material_override = m
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_splats.append(mi)
		_splat_mats.append(m)
		_splat_age.append(-1.0)


func _make_burst(mesh: Mesh, amount: int, vmin: float, vmax: float,
		life: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.14
	p.direction = Vector3(0, 1, 0)
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -13, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.mesh = mesh
	p.emitting = false
	return p


func burst(pos: Vector3) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	var c := _chunks[_next]
	_next = (_next + 1) % POOL
	p.global_position = pos
	c.global_position = pos
	p.restart()
	c.restart()


## Persistent ground splat under a kill. Fades out over its last 5s.
func splat(pos: Vector3) -> void:
	var idx := _splat_next
	var mi := _splats[idx]
	var m := _splat_mats[idx]
	_splat_next = (_splat_next + 1) % SPLAT_POOL
	mi.global_position = Vector3(pos.x, 0.02, pos.z)
	mi.rotation.y = randf() * TAU
	var s := randf_range(0.7, 1.3)
	mi.scale = Vector3(s, 1.0, s * randf_range(0.7, 1.0))
	mi.visible = true
	var col := m.albedo_color
	col.a = 0.85
	m.albedo_color = col
	_splat_age[idx] = 0.0


func _process(delta: float) -> void:
	for i in _splats.size():
		if _splat_age[i] < 0.0:
			continue
		_splat_age[i] += delta
		var age := _splat_age[i]
		if age >= SPLAT_LIFE:
			_splats[i].visible = false
			_splat_age[i] = -1.0
		elif age > SPLAT_LIFE - 5.0:
			var m := _splat_mats[i]
			var col := m.albedo_color
			col.a = 0.85 * (1.0 - (age - (SPLAT_LIFE - 5.0)) / 5.0)
			m.albedo_color = col
