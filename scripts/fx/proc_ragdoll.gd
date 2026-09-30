class_name ProcRagdoll
extends Node3D
## Procedural ragdoll-style death for our primitive-built characters (no
## Skeleton3D, so no PhysicalBone3D re-rig): the victim's pivoted body parts
## become live RigidBody3Ds, held together with cone-twist joints, kicked
## by the killing blow (bat = sprawl, shotgun = launch). They tumble,
## bounce off the world with a thud, settle, then freeze after ~2.2s into
## a persistent corpse. Phone-safe by construction:
##   - at most MAX_ACTIVE ragdolls simulate at once (overflow deaths fall
##     back to the classic crumple),
##   - parts collide with the world only (layer 4 vs mask 1: never with
##     each other, the player, or other zombies),
##   - bodies freeze fast; the frozen corpse is just 6 sleeping statics.
## Used by ZombieAI._die and PlayerHealth._die.

const MAX_ACTIVE := 6
const ACTIVE_TIME := 2.2
const LAYER := 4 # debris layer: world-only collision
const BOUNCE := 0.35

static var _active := 0
static var _phys_mat: PhysicsMaterial = null
static var _shapes := {} # rounded-size key -> shared BoxShape3D


## Spawn a ragdoll from part descriptors:
##   {"pivot": Node3D, "center": Vector3, "size": Vector3, "mass": float,
##    "limb": bool}  ("limb" false marks the torso everything joints to)
## kill_dir is the horizontal killing-blow direction, power scales with the
## weapon (bat ~5, shotgun ~14). Returns null when the active cap is hit.
static func spawn(parent: Node3D, parts: Array, kill_dir: Vector3,
		power: float) -> ProcRagdoll:
	if _active >= MAX_ACTIVE:
		return null
	if _phys_mat == null:
		_phys_mat = PhysicsMaterial.new()
		_phys_mat.bounce = BOUNCE
		_phys_mat.friction = 0.9
	var rag := ProcRagdoll.new()
	parent.add_child(rag)
	_active += 1
	rag._counted = true
	# Snapshot every pivot's world pose FIRST: reparenting later must not
	# shift the snapshots.
	var snaps: Array = []
	for p in parts:
		var piv: Node3D = p["pivot"]
		if piv == null or not is_instance_valid(piv):
			continue
		snaps.append({"p": p, "gt": piv.global_transform})
	if snaps.is_empty():
		rag.queue_free()
		return null
	var torso_rb: RigidBody3D = null
	var limbs: Array = [] # {"rb": RigidBody3D, "at": Vector3}
	for s in snaps:
		var p: Dictionary = s["p"]
		var piv: Node3D = s["p"]["pivot"]
		var rb := RigidBody3D.new()
		rb.mass = float(p["mass"])
		rb.physics_material_override = _phys_mat
		rb.collision_layer = LAYER
		rb.collision_mask = 1
		rb.linear_damp = 0.4
		rb.angular_damp = 2.2
		rb.can_sleep = true
		rag.add_child(rb)
		var gt: Transform3D = s["gt"]
		gt.basis = gt.basis.orthonormalized() # physics dislikes scaled bodies
		rb.global_transform = gt
		var cs := CollisionShape3D.new()
		cs.shape = _box_shape(p["size"])
		cs.position = p["center"]
		rb.add_child(cs)
		piv.reparent(rb) # keep_global: the pivot keeps its world pose
		rag._bodies.append(rb)
		if bool(p.get("limb", true)):
			limbs.append({"rb": rb, "at": gt.origin})
		else:
			torso_rb = rb
	if torso_rb == null:
		torso_rb = rag._bodies[0]
	# Cone-twist joints: limbs stay attached but flail. The joint must be
	# FULLY configured before entering the tree — Godot only builds the
	# physics constraint from the pre-tree transform and node paths, so
	# setting them after add_child silently leaves the bodies unjoined.
	# Snug spans: the corpse should read as one body, not spare parts.
	var rag_inv := rag.global_transform.affine_inverse()
	for l in limbs:
		var j := ConeTwistJoint3D.new()
		j.transform = rag_inv * Transform3D(Basis(), l["at"])
		j.node_a = rag.get_path_to(torso_rb)
		j.node_b = rag.get_path_to(l["rb"])
		j.swing_span = 0.55
		j.twist_span = 0.8
		rag.add_child(j)
	# The killing blow: coherent base velocity (so the body flies as one)
	# plus per-part differentials (so it reads as a tumble, not a slide).
	var dir := kill_dir
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var tumble := -dir.cross(Vector3.UP)
	if tumble.length() < 0.05:
		tumble = Vector3.RIGHT
	tumble = tumble.normalized() # pitches the body's top toward the blow
	# Coherent launch: EVERY part gets the same linear velocity so the
	# joints don't fight translational differences (the solver was
	# dissipating the launch as heat). Visual variety comes from the
	# per-part angular velocity and the joint spans, not from velocity
	# jitter.
	var v: Vector3 = dir * power * randf_range(0.9, 1.1)
	v.y = randf_range(1.8, 3.4)
	for b in rag._bodies:
		if b == torso_rb:
			b.angular_velocity = tumble * randf_range(2.5, 5.5) \
				+ Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
					randf_range(-1.0, 1.0))
		else:
			# Modest flail: wild spin fights the joint spans and the
			# solver brakes the whole body dissipating the launch.
			b.angular_velocity = Vector3(randf_range(-3.0, 3.0),
				randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		b.linear_velocity = v # direct set: apply_impulse in the spawn
		# frame was shattering the fresh joints; velocity is equivalent
		# for an instantaneous launch and the solver accepts it cleanly.
	# One-shot impact thud when the torso first slams the world.
	torso_rb.contact_monitor = true
	torso_rb.max_contacts_reported = 4
	torso_rb.body_entered.connect(rag._on_torso_impact.bind(torso_rb))
	return rag


static func active_count() -> int:
	return _active


static func _box_shape(size: Vector3) -> BoxShape3D:
	var key := "%d_%d_%d" % [roundi(size.x * 100.0), roundi(size.y * 100.0),
		roundi(size.z * 100.0)]
	if not _shapes.has(key):
		var s := BoxShape3D.new()
		s.size = size
		_shapes[key] = s
	return _shapes[key]


var _bodies: Array[RigidBody3D] = []
var _t := 0.0
var _frozen := false
var _counted := false
var _thudded := false


func _process(delta: float) -> void:
	if _frozen:
		return
	_t += delta
	# Safety: a body that fell through the world freezes instead of
	# dropping forever.
	var sunk := false
	if not _bodies.is_empty() and is_instance_valid(_bodies[0]):
		sunk = _bodies[0].global_position.y < -3.0
	if _t >= ACTIVE_TIME or sunk:
		_freeze_all()


func _freeze_all() -> void:
	_frozen = true
	for b in _bodies:
		if is_instance_valid(b):
			b.freeze = true
	if _counted:
		_counted = false
		_active -= 1


## Corpse persistence: sink the frozen body into the ground. Teleports the
## bodies directly (frozen bodies ignore parent motion).
func sink_by(dy: float) -> void:
	for b in _bodies:
		if is_instance_valid(b):
			var gp := b.global_position
			gp.y -= dy
			b.global_position = gp


func _on_torso_impact(_hit: Node, torso: RigidBody3D) -> void:
	if _thudded:
		return
	_thudded = true
	var at := global_position + Vector3(0, 0.5, 0)
	if is_instance_valid(torso):
		at = torso.global_position
	Sound.play_3d("pound", at, -8.0, randf_range(0.85, 1.1))


func _exit_tree() -> void:
	if _counted:
		_counted = false
		_active -= 1
