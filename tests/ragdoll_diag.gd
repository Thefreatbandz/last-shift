extends SceneTree
## Diagnostic: measure how far each limb RB drifts from its joint anchor.
## If ConeTwistJoint3D is working, pivots should stay within ~0.4m of
## their anchors through the tumble.

var _booted := false
var _frames := 0
var _main: Node
var _z: Node = null
var _anchors := {} # RigidBody3D -> Vector3 anchor


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 60:
		for z in _main.get_node("Zombies").get("zombies"):
			if not bool(z.call("is_dead")):
				_z = z
				break
		var zp: Vector3 = (_z as Node3D).global_position
		_z.call("take_damage", 99999.0, zp + Vector3(0, 0, -1.0), 1.0)
		var rag: Node = _z.get("_ragdoll")
		# Record each limb RB and its joint anchor (= its spawn position).
		for c in rag.get_children():
			if c is RigidBody3D:
				_anchors[c] = (c as RigidBody3D).global_position
		print("DIAG spawned, anchors=", _anchors.size())
		# Inspect the joints: are they where we think, do paths resolve?
		for c in rag.get_children():
			if c is ConeTwistJoint3D:
				var j := c as ConeTwistJoint3D
				var a := rag.get_node_or_null(j.node_a)
				var b := rag.get_node_or_null(j.node_b)
				print("DIAG joint at ", j.global_position,
					" a_resolves=", a != null, " b_resolves=", b != null)
				break
	elif _frames == 90 or _frames == 120 or _frames == 180:
		# CORRECT metric: max distance of any part from the TORSO (not
		# from spawn — the whole body is supposed to fly). Joints hold
		# iff this stays small through the tumble.
		var torso_pos := Vector3.ZERO
		var bodies: Array = []
		for rb in _anchors.keys():
			if is_instance_valid(rb):
				bodies.append(rb)
		if not bodies.is_empty():
			torso_pos = (bodies[0] as RigidBody3D).global_position
		var worst := 0.0
		for rb in bodies:
			var d: float = (rb as RigidBody3D).global_position.distance_to(
				torso_pos)
			worst = maxf(worst, d)
		print("DIAG frame=", _frames, " worst_part_to_torso=",
			snappedf(worst, 0.01), " (jointed if < ~1.2)")
	elif _frames == 200:
		print("DIAG done")
		quit(0)
		return true
	return false
