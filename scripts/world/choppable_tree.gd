class_name ChoppableTree
extends Node3D
## Wave loop: dead trees you can chop for wood. Two melee hits fells the
## tree (it tips over and stays as a fallen log + stump); felling grants
## 2-3 wood via the `felled` signal. Seeded per-tree, own RNG stream.

signal felled(tree: ChoppableTree, wood: int)

var hp := 2
var felled_flag := false
var wood := 3

var _shake_t := 0.0
var _fall_t := -1.0 # >= 0 while the tip-over animation plays
var _fall_dir := 1.0
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _body: StaticBody3D


func build(pos: Vector3, s: float, seed_val: int) -> void:
	position = pos
	_rng.seed = seed_val
	wood = 3 # one tree = one door barricade (BUILD_WOOD := 3)
	hp = 2
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.32, 0.28, 0.24) # dead gray-brown
	bark.roughness = 1.0
	_visual = Node3D.new()
	add_child(_visual)
	# Leaning dead trunk.
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13 * s
	cm.bottom_radius = 0.23 * s
	cm.height = 2.4 * s
	cm.radial_segments = 6
	cm.material = bark
	trunk.mesh = cm
	trunk.position = Vector3(0, 1.2 * s, 0)
	trunk.rotation.z = _rng.randf_range(-0.08, 0.08)
	_visual.add_child(trunk)
	# A few bare branches.
	for i in 3:
		var bl := _rng.randf_range(0.8, 1.3) * s
		var br := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09 * s, 0.09 * s, bl)
		bm.material = bark
		br.mesh = bm
		var yaw := _rng.randf() * TAU
		var h := _rng.randf_range(1.4, 2.1) * s
		br.position = Vector3(0, h, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, bl * 0.35)
		br.rotation.y = yaw
		br.rotation.x = _rng.randf_range(-0.5, -0.2)
		_visual.add_child(br)
	# Solid trunk so the player can't walk through it.
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35 * s
	shape.height = 2.4 * s
	cs.shape = shape
	cs.position = Vector3(0, 1.2 * s, 0)
	_body.add_child(cs)
	add_child(_body)
	_fall_dir = -1.0 if _rng.randf() < 0.5 else 1.0


func chop() -> void:
	if felled_flag:
		return
	hp -= 1
	_shake_t = 0.25
	Sound.play_3d("thwack", global_position)
	if hp <= 0:
		felled_flag = true
		_fall_t = 0.0
		if _body != null:
			_body.set_deferred("collision_layer", 0)
			_body.set_deferred("collision_mask", 0)
		felled.emit(self, wood)


func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		_visual.rotation.z = sin(_shake_t * 40.0) * 0.06 * maxf(_shake_t / 0.25, 0.0)
		if _shake_t <= 0.0:
			_visual.rotation.z = 0.0
	if _fall_t >= 0.0:
		_fall_t += delta
		var k := clampf(_fall_t / 0.7, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 2.0)
		_visual.rotation.x = _fall_dir * e * 1.45
		if k >= 1.0:
			_fall_t = -1.0
