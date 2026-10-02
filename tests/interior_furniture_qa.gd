extends SceneTree
## Interior furniture QA: every tagged interior furniture piece must sit inside
## its building footprint; the safehouse workbench/stash/bedroll must be
## inside the safehouse with door-swing clearance; closed doors must keep a
## physics body out. Run:
##   godot --headless --path . --script res://tests/interior_furniture_qa.gd
## Grep the output for SCRIPT ERROR separately.

const SEEDS := [48392017, 12345, 777, 20260704, 424242]
const EPS := 0.05 # inside-footprint tolerance (m)

var _booted := false
var _frames := 0
var _ok := true
var _main: Node
var _nb: Node # live Neighborhood
var _doors: Node
var _probe: CharacterBody3D
var _probe_dir := Vector3.ZERO
var _probe_rect := Rect2()
var _probe_entered := false
var _probe_nearest := 999.0
var _probe_house := 0
# Lazy load: NeighborhoodBuilder/InteriorZones touch the Sound autoload;
# static class_name refs compile before autoloads register in bare
# --script mode. (prompt_qa.gd precedent.)
var _NB: GDScript
var _IZ: GDScript


func _check(label: String, cond: bool) -> void:
	if cond:
		print("FURNQA PASS ", label)
	else:
		_ok = false
		print("FURNQA FAIL ", label)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_NB = load("res://scripts/world/neighborhood_builder.gd")
		_IZ = load("res://scripts/world/interior_zones.gd")
		_builder_checks()
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		return false
	_frames += 1
	match _frames:
		30:
			_live_trio_checks()
			_live_door_toggle()
		32:
			_live_door_toggle_assert()
		154:
			_live_probe_assert()
			print("FURNQA_RESULT ok=", _ok)
			quit(0 if _ok else 1)
			return true
		_:
			pass
	if _probe != null and _frames > 34 and _frames < 154:
		_probe_step(_delta)
	return false


# ------------------------------------------------------- builder checks ---

func _builder_checks() -> void:
	for seed in SEEDS:
		var nb: Node = _NB.new()
		root.add_child(nb)
		nb.build_world(seed)
		_check("layout_hash_stable_%d" % seed,
			nb.layout_hash() == _hash_of(seed))
		for hi in nb.houses.size():
			var h := nb.houses[hi] as Dictionary
			var hroot := h["root"] as Node3D
			var rect := _footprint(h)
			var pieces := _tagged_furniture(hroot)
			_check("house_%d_has_furniture_%d" % [hi, seed], pieces.size() >= 10)
			for p in pieces:
				var a := _world_aabb(p as Node3D)
				if not _inside_rect(a, rect, EPS):
					_check("house_%d_%d_inside_%s" % [hi, seed, (p as Node).name], false)
		# Commercial buildings: roots are bld_<kind>. Kinds can repeat
		# (world-density expansion lots), so match the root by position,
		# not by name. Zoned kinds are hollow SHELLS outside (no
		# furniture); their real interiors live in the hidden zones
		# (checked below).
		for b in nb.buildings:
			var bd := b as Dictionary
			var kind := String(bd["kind"])
			var broot := _bld_root_for(nb, bd) as Node3D
			if broot == null:
				_check("bld_root_%s_%d" % [kind, seed], false)
				continue
			var rect := _footprint(bd)
			var pieces := _tagged_furniture(broot)
			if _IZ.is_zoned_kind(kind):
				_check("bld_%s_shell_empty_%d" % [kind, seed], pieces.size() == 0)
				continue
			_check("bld_%s_has_furniture_%d" % [kind, seed],
				pieces.size() >= 2)
			for p in pieces:
				var a := _world_aabb(p as Node3D)
				if not _inside_rect(a, rect, EPS):
					_check("bld_%s_%d_inside_%s" % [kind, seed, (p as Node).name], false)
		# Hidden interior zones: furniture must sit inside the zone bounds,
		# and every zone must be furnished (compound on the inside).
		if nb.interior_zones != null:
			for z in nb.interior_zones.zones:
				var zd := z as Dictionary
				var zkind := String(zd["kind"])
				var zbounds := zd["bounds"] as Rect2
				var zpieces := _tagged_furniture(zd["root"] as Node3D)
				_check("zone_%s_has_furniture_%d" % [zkind, seed],
					zpieces.size() >= 4)
				for p in zpieces:
					var a := _world_aabb(p as Node3D)
					if not _inside_rect(a, zbounds, EPS):
						_check("zone_%s_%d_inside_%s" % [zkind, seed, (p as Node).name], false)
		# Building loot + indoor zombie spawns: zone loot/spawns live in
		# zone bounds; everything else in building footprints.
		var rects: Array = []
		for b in nb.buildings:
			var bd2 := b as Dictionary
			if _IZ.is_zoned_kind(String(bd2["kind"])):
				continue
			rects.append(_footprint(bd2))
		if nb.interior_zones != null:
			for z in nb.interior_zones.zones:
				rects.append((z as Dictionary)["bounds"])
		for li in nb.building_loot.size():
			var ld := nb.building_loot[li] as Dictionary
			var lp := ld["pos"] as Vector3
			if String(ld.get("kind", "")) == "lumber":
				# Lumber piles sit out front of the warehouse by design.
				_check("loot_%d_%d_lumber_near_wh" % [li, seed],
					_near_kind(lp, nb.buildings, "warehouse", 7.0))
			else:
				_check("loot_%d_%d_inside" % [li, seed], _inside_any(lp, rects, 0.0))
		for zi in nb.building_zombie_spawns.size():
			var zp := nb.building_zombie_spawns[zi] as Vector3
			_check("zspawn_%d_%d_inside" % [zi, seed], _inside_any(zp, rects, 0.0))
		nb.free()


func _hash_of(seed: int) -> String:
	var nb2: Node = _NB.new()
	root.add_child(nb2)
	nb2.build_world(seed)
	var hsh: String = nb2.layout_hash()
	nb2.free()
	return hsh


func _footprint(d: Dictionary) -> Rect2:
	var p := d["pos"] as Vector3
	var w := float(d["w"])
	var dd := float(d["d"])
	return Rect2(p.x - w * 0.5, p.z - dd * 0.5, w, dd)


## Find a commercial building's exterior root by position. Kinds can repeat
## (world-density expansion lots): Godot auto-renames duplicate sibling
## names ("bld_grocery" -> "@Node3D@1234"), so a name lookup cannot work
## for duplicates — but every root sits exactly on its spec position.
func _bld_root_for(nb: Node, bd: Dictionary) -> Node:
	var bp := (bd as Dictionary)["pos"] as Vector3
	for c in nb.get_children():
		if c is Node3D and ((c as Node3D).position - bp).length() < 0.01:
			return c
	return null


func _near_kind(p: Vector3, buildings: Array, kind: String, margin: float) -> bool:
	for b in buildings:
		var bd := b as Dictionary
		if String(bd.get("kind", "")) != kind:
			continue
		var r := _footprint(bd).grow(margin)
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false


func _tagged_furniture(n: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c != n and c.has_meta("furniture"):
			out.append(c)
		for ch in c.get_children():
			stack.append(ch)
	return out


func _world_aabb(n: Node3D) -> AABB:
	var a := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var local := AABB()
		var has := false
		if c is MeshInstance3D:
			local = (c as MeshInstance3D).get_aabb()
			has = true
		elif c is CollisionShape3D:
			# Collision-only pieces (_solid): fall back to the shape extents.
			local = _shape_aabb((c as CollisionShape3D).shape)
			has = local.size.length_squared() > 0.0
		if has:
			# World transform from the local-transform chain (valid even
			# before the tree's first transform update).
			var xf := Transform3D.IDENTITY
			var cur: Node = c
			while cur is Node3D:
				xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var wa: AABB = xf * local
			if first:
				a = wa
				first = false
			else:
				a = a.merge(wa)
		for ch in c.get_children():
			stack.append(ch)
	return a


func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var bs := shape as BoxShape3D
		return AABB(-bs.size * 0.5, bs.size)
	if shape is CapsuleShape3D:
		var ks := shape as CapsuleShape3D
		return AABB(Vector3(-ks.radius, -ks.height * 0.5, -ks.radius),
			Vector3(ks.radius * 2.0, ks.height, ks.radius * 2.0))
	if shape is SphereShape3D:
		var ss := shape as SphereShape3D
		var r := ss.radius
		return AABB(Vector3(-r, -r, -r), Vector3(2.0 * r, 2.0 * r, 2.0 * r))
	if shape is CylinderShape3D:
		var ys := shape as CylinderShape3D
		return AABB(Vector3(-ys.radius, -ys.height * 0.5, -ys.radius),
			Vector3(ys.radius * 2.0, ys.height, ys.radius * 2.0))
	return AABB()


func _inside_rect(a: AABB, rect: Rect2, eps: float) -> bool:
	return a.position.x >= rect.position.x - eps \
		and a.position.z >= rect.position.y - eps \
		and a.end.x <= rect.end.x + eps \
		and a.end.z <= rect.end.y + eps


func _inside_any(p: Vector3, rects: Array, eps: float) -> bool:
	for r in rects:
		var rc := r as Rect2
		if rc.grow(eps).has_point(Vector2(p.x, p.z)):
			return true
	return false


# ---------------------------------------------------------- live checks ---

func _live_trio_checks() -> void:
	_nb = _main.get_node("Neighborhood")
	_doors = _main.get_node("HouseDoors")
	var sh := _main.get_node("Safehouse")
	var h := (_nb.houses[_nb.safehouse_index]) as Dictionary
	var hroot := h["root"] as Node3D
	var w := float(h["w"])
	var d := float(h["d"])
	var face := float(h["face"])
	var rect := _footprint(h)
	_check("trio_parented_inside", sh.get("_inprops") != null)
	for key in ["_bench", "_chest", "_bedroll"]:
		var n := sh.get(key) as Node3D
		if n == null:
			_check("trio_exists_" + key, false)
			continue
		_check("trio_parent_" + key, n.get_parent() == sh.get("_inprops"))
		var a := _world_aabb(n)
		_check("trio_inside_" + key, _inside_rect(a, rect, EPS))
		# Door-swing clearance: keep the swing disc (radius 1.6 around the
		# hinge at house-local x=-0.7, front wall) clear. face*lc.z measures
		# "forwardness": d/2 at the front wall, -d/2 at the back.
		var lc := hroot.to_local(a.get_center())
		var near_front := face * lc.z > d * 0.5 - 2.2
		var in_swing := absf(lc.x + 0.7) < 1.7 and near_front
		_check("trio_door_clear_" + key, not in_swing)
		# No overlap with the searchable loot crate (0.95^2 at the front-left).
		var loot_c := Vector3(-w * 0.5 + 1.0, 0.3, face * (d * 0.5 - 1.2))
		var loot_a := AABB(loot_c - Vector3(0.475, 0.3, 0.475),
			Vector3(0.95, 0.6, 0.95))
		var trio_local := AABB(hroot.to_local(a.position), a.size)
		_check("trio_loot_clear_" + key, not trio_local.intersects(loot_a))


func _live_door_toggle() -> void:
	# Pick a non-safehouse house, verify the blocker is live while closed,
	# then open it (deferred disable applies next frame).
	_probe_house = 0
	if _probe_house == _nb.safehouse_index:
		_probe_house = 1
	var door := (_nb.houses[_probe_house] as Dictionary)["door"] as Dictionary
	_check("door_starts_closed", not bool(door["open"]))
	var shape := (door["blocker"] as Node).get_child(0) as CollisionShape3D
	_check("blocker_enabled_closed", not shape.disabled)
	_doors.set_door_open(_probe_house, true, false)


func _live_door_toggle_assert() -> void:
	var door := (_nb.houses[_probe_house] as Dictionary)["door"] as Dictionary
	var shape := (door["blocker"] as Node).get_child(0) as CollisionShape3D
	_check("blocker_disabled_open", shape.disabled)
	_doors.set_door_open(_probe_house, false, false)
	# Spawn the physics probe outside the now-closed door.
	var h := (_nb.houses[_probe_house]) as Dictionary
	var face := float(h["face"])
	var dpos := (door["pos"] as Vector3)
	_probe_dir = Vector3(0, 0, face) # points outward
	_probe_rect = _footprint(h)
	_probe = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	_probe.add_child(cs)
	_probe.global_position = dpos + _probe_dir * 1.2 + Vector3(0, 0.1, 0)
	root.add_child(_probe)


func _probe_step(delta: float) -> void:
	# Drive the probe straight at the closed door; it must stop at the
	# blocker and never enter the footprint.
	var v := -_probe_dir * 3.0
	v.y = _probe.velocity.y - 20.0 * delta
	_probe.velocity = v
	_probe.move_and_slide()
	var p := _probe.global_position
	var door := (_nb.houses[_probe_house] as Dictionary)["door"] as Dictionary
	var dist := p.distance_to(door["pos"] as Vector3)
	_probe_nearest = minf(_probe_nearest, dist)
	if _probe_rect.has_point(Vector2(p.x, p.z)):
		_probe_entered = true


func _live_probe_assert() -> void:
	_check("probe_reached_door", _probe_nearest < 1.0)
	_check("probe_blocked_by_closed_door", not _probe_entered)
	if _probe != null:
		_probe.queue_free()
		_probe = null
