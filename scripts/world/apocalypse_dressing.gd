class_name ApocalypseDressing
extends Node3D
## Apocalypse world dressing (Tbandz 2026-09-29): blood on walls and ground,
## scattered corpses, barrel fires, burning/wrecked cars, rubble piles.
## PURELY COSMETIC — no loot, no collisions, no gameplay hooks.
##
## Append-only contract: this runs AFTER NeighborhoodBuilder.build_world and
## never touches the builder's lot/spec/loot/spawn arrays, so layout and
## interior hashes are unchanged. All randomness comes from a dedicated
## RandomNumberGenerator seeded from world_seed (never randomize(), never the
## builder's streams).
##
## Perf contract (iPhone 12): shared meshes/materials everywhere, one
## MultiMeshInstance3D per repeated item, flame flicker driven by ONE _process
## on this manager node (never per-fire), <= 6 real OmniLight3D (no shadows),
## smoke <= 24 particles per fire.
##
## Hook (one line in main.gd _start_run, right after build_world):
##     ApocalypseDressing.new().dress(neighborhood)

const SEED_XOR := 0xA90CA1ED # dressing-only stream; must not collide with hood streams
const MAX_LIGHTS := 6 # hard cap on real OmniLight3D fire lights

var _rng := RandomNumberGenerator.new()
var _stats := {"blood": 0, "corpses": 0, "barrel_fires": 0, "burning_wrecks": 0,
	"wrecks": 0, "rubble": 0, "lights": 0}

# Shared resources (built once in dress).
var _m_blood: StandardMaterial3D
var _m_body: StandardMaterial3D # desiccated gray corpse cloth
var _m_body_dark: StandardMaterial3D # fresher dark corpse cloth
var _m_cloth_a: StandardMaterial3D # faded rust-red corpse clothes
var _m_cloth_b: StandardMaterial3D # faded denim-blue corpse clothes
var _m_skin: StandardMaterial3D
var _m_concrete: StandardMaterial3D
var _m_wood: StandardMaterial3D
var _m_rust: StandardMaterial3D
var _m_char: StandardMaterial3D # burnt wreck paint
var _m_scorch: StandardMaterial3D # dark scorch decal
var _m_ash: StandardMaterial3D # pale ash drift
var _m_tire: StandardMaterial3D
var _m_glass_dark: StandardMaterial3D
var _m_flame: StandardMaterial3D
var _m_paint: Array[StandardMaterial3D] = [] # faded paints for smoking wrecks
var _plane := PlaneMesh.new() # flat XZ, shared by ground/wall blood
var _cube := BoxMesh.new() # unit cube; sized per-instance via transform
var _ball := SphereMesh.new() # unit-ish sphere for heads
var _barrel_mesh := CylinderMesh.new()
var _flame_quad := QuadMesh.new() # vertical XY, shared by all flames
var _smoke_tex: Texture2D

# Collected instance transforms, committed to MultiMeshes at the end.
var _t_blood: Array[Transform3D] = []
var _t_body: Array[Transform3D] = [] # gray corpse parts (torso/arms)
var _t_body_dark: Array[Transform3D] = [] # dark corpse parts (legs, fresh torsos)
var _t_cloth_a: Array[Transform3D] = [] # rust-red clothed torso/arms
var _t_cloth_b: Array[Transform3D] = [] # denim-blue clothed torso/arms
var _t_skin: Array[Transform3D] = [] # heads
var _t_concrete: Array[Transform3D] = []
var _t_woodchunk: Array[Transform3D] = []
var _t_scorch: Array[Transform3D] = [] # dark scorch decals around fires/wrecks
var _t_char: Array[Transform3D] = [] # charred chunks around fires/wrecks
var _t_ash: Array[Transform3D] = [] # pale ash drifts near some fires

# Flicker state: one _process drives every fire.
var _fires: Array = [] # [{light, quads, phase, base}]
var _time := 0.0
var _placed: Array[Vector3] = [] # my own fire/wreck spots (spacing)


func dress(hood: NeighborhoodBuilder) -> ApocalypseDressing:
	name = "ApocalypseDressing"
	_rng.seed = int(hood.world_seed) ^ SEED_XOR
	_build_shared()
	var corpses := _place_corpses(hood)
	_place_blood(hood, corpses)
	_place_barrel_fires(hood)
	_place_burning_wrecks(hood)
	_place_wrecks(hood)
	_place_rubble(hood)
	_place_scorch(hood) # v3: scorch decals + charred chunks + ash drifts
	_commit_multimeshes()
	hood.add_child(self)
	return self


func get_stats() -> Dictionary:
	return _stats.duplicate()


## Deterministic fingerprint: stats + rounded corpse/blood origins.
func get_fingerprint() -> String:
	var parts: Array[String] = []
	for k in _stats.keys():
		parts.append("%s:%d" % [k, int(_stats[k])])
	for t in _t_skin: # one transform per corpse (heads)
		var o := t.origin
		parts.append("c:%.3f,%.3f" % [o.x, o.z])
	for t in _t_blood:
		var o := t.origin
		parts.append("b:%.3f,%.3f" % [o.x, o.z])
	return "|".join(parts)


func _process(delta: float) -> void:
	_time += delta
	for f in _fires:
		var ph: float = f["phase"]
		var l: OmniLight3D = f["light"]
		if is_instance_valid(l):
			l.light_energy = float(f["base"]) * (
				0.82 + 0.18 * sin(_time * 11.0 + ph) + 0.08 * sin(_time * 27.0 + ph * 1.7))
		var s := 1.0 + 0.10 * sin(_time * 13.0 + ph) + 0.05 * sin(_time * 29.0 + ph * 2.3)
		for q in (f["quads"] as Array):
			if is_instance_valid(q):
				(q as MeshInstance3D).scale = Vector3(s, 1.0 + (s - 1.0) * 2.5, s)


# ------------------------------------------------- shared resources ---

func _mat(c: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _build_shared() -> void:
	_m_blood = _mat(Color(0.30, 0.012, 0.025, 0.88), 0.3)
	_m_blood.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_body = _mat(Color(0.34, 0.31, 0.29), 0.95)
	_m_body_dark = _mat(Color(0.19, 0.15, 0.12), 0.95)
	_m_cloth_a = _mat(Color(0.42, 0.19, 0.13), 0.95) # faded rust red
	_m_cloth_b = _mat(Color(0.20, 0.27, 0.38), 0.95) # faded denim blue
	_m_skin = _mat(Color(0.52, 0.44, 0.38), 0.9)
	_m_concrete = _mat(Color(0.30, 0.29, 0.28), 0.95)
	_m_wood = _mat(Color(0.36, 0.26, 0.16), 0.9)
	_m_rust = _mat(Color(0.36, 0.20, 0.10), 0.85, 0.25)
	_m_char = _mat(Color(0.085, 0.08, 0.08), 0.95)
	_m_scorch = _mat(Color(0.05, 0.045, 0.04), 1.0) # scorch decal, near-black
	_m_ash = _mat(Color(0.55, 0.53, 0.49), 1.0) # pale ash drift
	_m_tire = _mat(Color(0.10, 0.10, 0.10), 0.95)
	_m_glass_dark = _mat(Color(0.05, 0.06, 0.07), 0.2, 0.6)
	for c in [Color(0.40, 0.20, 0.13), Color(0.26, 0.30, 0.36), Color(0.33, 0.33, 0.22)]:
		_m_paint.append(_mat(c.lerp(Color(0.45, 0.42, 0.38), 0.35), 0.7, 0.1))
	_plane.size = Vector2(1, 1)
	_cube.size = Vector3(1, 1, 1)
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 6
	_barrel_mesh.top_radius = 0.32
	_barrel_mesh.bottom_radius = 0.32
	_barrel_mesh.height = 0.95
	_barrel_mesh.radial_segments = 12
	_flame_quad.size = Vector2(0.85, 1.15)
	_flame_quad.material = _make_flame_mat()
	_smoke_tex = _make_smoke_tex()


func _make_flame_mat() -> StandardMaterial3D:
	var tex := _make_flame_tex()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_flame_tex() -> Texture2D:
	# Deterministic procedural flame: bright yellow-white core at the base
	# fading to orange and transparent at the tip.
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var ny := float(y) / 63.0 # 0 = top tip, 1 = base
		var width := 0.30 + 0.55 * ny
		for x in 32:
			var nx := (float(x) / 31.0 - 0.5) * 2.0
			var d := absf(nx) / width
			var a := clampf(1.0 - d, 0.0, 1.0) * clampf(ny * 3.0, 0.0, 1.0)
			a *= clampf((1.0 - ny) * 10.0 + 0.25, 0.0, 1.0)
			var heat := clampf(ny * (1.0 - d) * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.28 + 0.62 * heat, 0.04 + 0.26 * heat, a))
	return ImageTexture.create_from_image(img)


func _make_smoke_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := float(x) / 63.0 - 0.5
			var dy := float(y) / 63.0 - 0.5
			var d := sqrt(dx * dx + dy * dy) * 2.0
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _commit_multimeshes() -> void:
	_add_mmi(_plane, _m_blood, _t_blood)
	_add_mmi(_cube, _m_body, _t_body)
	_add_mmi(_cube, _m_body_dark, _t_body_dark)
	_add_mmi(_cube, _m_cloth_a, _t_cloth_a)
	_add_mmi(_cube, _m_cloth_b, _t_cloth_b)
	_add_mmi(_ball, _m_skin, _t_skin)
	_add_mmi(_cube, _m_concrete, _t_concrete)
	_add_mmi(_cube, _m_wood, _t_woodchunk)
	_add_mmi(_plane, _m_scorch, _t_scorch)
	_add_mmi(_cube, _m_char, _t_char)
	_add_mmi(_plane, _m_ash, _t_ash)


func _add_mmi(mesh: Mesh, mat: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# ------------------------------------------------- placement data ---

## All building + house entries with pos/w/d/face for footprint tests.
func _entries(hood: NeighborhoodBuilder) -> Array:
	var out: Array = []
	for b in (hood.buildings as Array):
		out.append(b)
	for h in (hood.houses as Array):
		out.append(h)
	return out


func _door_pos(e: Dictionary) -> Vector3:
	var p := e["pos"] as Vector3
	var face := float(e["face"])
	return p + Vector3(0, 0, face * float(e["d"]) * 0.5)


func _in_footprint(p: Vector3, e: Dictionary, margin: float) -> bool:
	var c := e["pos"] as Vector3
	return absf(p.x - c.x) < float(e["w"]) * 0.5 + margin \
		and absf(p.z - c.z) < float(e["d"]) * 0.5 + margin


func _clear_of_buildings(p: Vector3, hood: NeighborhoodBuilder, margin: float) -> bool:
	for e in _entries(hood):
		if _in_footprint(p, e as Dictionary, margin):
			return false
	return true


func _clear_of_doors(p: Vector3, hood: NeighborhoodBuilder, dist: float) -> bool:
	for e in _entries(hood):
		var d := _door_pos(e as Dictionary)
		if Vector2(p.x - d.x, p.z - d.z).length() < dist:
			return false
	return true


func _road_point(hood: NeighborhoodBuilder, off_min: float, off_max: float) -> Vector3:
	var rects := hood.get_road_rects()
	var r: Rect2 = rects[_rng.randi() % rects.size()]
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var off := side * _rng.randf_range(off_min, off_max)
	if r.size.x > r.size.y: # EW road: runs along X
		return Vector3(_rng.randf_range(r.position.x + 4.0, r.end.x - 4.0),
			0, r.position.y + r.size.y * 0.5 + off)
	# NS road: runs along Z
	return Vector3(r.position.x + r.size.x * 0.5 + off, 0,
		_rng.randf_range(r.position.y + 4.0, r.end.y - 4.0))


func _intersection(hood: NeighborhoodBuilder) -> Vector2:
	return Vector2(hood.road_ns_x, hood.road_ew_z)


func _open_point(hood: NeighborhoodBuilder) -> Vector3:
	var m := NeighborhoodBuilder.MAP_HALF - 3.0
	for _t in 40:
		var p := Vector3(_rng.randf_range(-m, m), 0, _rng.randf_range(-m, m))
		if not _clear_of_buildings(p, hood, 2.0):
			continue
		return p
	return Vector3.ZERO


# ------------------------------------------------- 1. blood ---

func _blood_ground(p: Vector3, smin: float, smax: float) -> void:
	var s := _rng.randf_range(smin, smax)
	var sy := s * _rng.randf_range(0.6, 1.0)
	var t := Transform3D(
		Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1, sy)),
		Vector3(p.x, 0.02, p.z))
	_t_blood.append(t)
	_stats["blood"] = int(_stats["blood"]) + 1


func _blood_wall(p: Vector3, face: float) -> void:
	# Flat quad on the wall plane, facing outward.
	var w := _rng.randf_range(0.5, 1.3)
	var h := _rng.randf_range(0.4, 1.1)
	var b := Basis(Vector3.RIGHT, face * PI * 0.5).scaled(Vector3(w, h, 1))
	var t := Transform3D(b, Vector3(p.x, _rng.randf_range(0.5, 2.0),
		p.z + face * 0.04))
	_t_blood.append(t)
	_stats["blood"] = int(_stats["blood"]) + 1


func _place_blood(hood: NeighborhoodBuilder, corpses: Array[Vector3]) -> void:
	# Concentrated near corpses...
	for cp in corpses:
		for i in _rng.randi_range(1, 2):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.4, 1.7)
			_blood_ground(cp + Vector3(cos(a) * r, 0, sin(a) * r), 0.5, 1.5)
	# ...and near doorways (ground + walls).
	for e in _entries(hood):
		var d := _door_pos(e as Dictionary)
		var face := float((e as Dictionary)["face"])
		if _rng.randf() < 0.65:
			for i in _rng.randi_range(1, 2):
				_blood_ground(d + Vector3(_rng.randf_range(-3.0, 3.0), 0,
					face * _rng.randf_range(0.8, 3.2)), 0.4, 1.2)
		if _rng.randf() < 0.40:
			_blood_wall(d + Vector3(_rng.randf_range(-2.5, 2.5), 0, 0), face)
	# A few smears along road edges.
	for i in 12:
		_blood_ground(_road_point(hood, 4.5, 6.5), 0.4, 1.0)


# ------------------------------------------------- 2. corpses ---

## Mirrors loot_container._build_corpse (old/fresh) as shared-mesh
## MultiMesh transforms. NO loot registration, NO collision — pure dressing.
func _place_corpses(hood: NeighborhoodBuilder) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	# NOTE: Array.shuffle() uses the GLOBAL rng — never call it here. Manual
	# seeded Fisher-Yates below instead.
	var order: Array = []
	for e in _entries(hood):
		order.append(e)
	for i in range(order.size() - 1, 0, -1): # seeded Fisher-Yates
		var j := _rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var n_door := mini(6, order.size())
	for i in n_door:
		var e := order[i] as Dictionary
		var d := _door_pos(e)
		var face := float(e["face"])
		spots.append(d + Vector3(_rng.randf_range(-2.5, 2.5), 0,
			face * _rng.randf_range(2.0, 4.5)))
	for i in _rng.randi_range(4, 6):
		spots.append(_road_point(hood, 3.2, 5.5))
	for i in _rng.randi_range(2, 4):
		spots.append(_open_point(hood))
	spots.resize(mini(16, spots.size()))
	while spots.size() < 10:
		spots.append(_open_point(hood))
	for p in spots:
		_corpse(p)
	_stats["corpses"] = spots.size()
	return spots


func _corpse(p: Vector3) -> void:
	var yaw := _rng.randf() * TAU
	var fresh := _rng.randf() < 0.4
	var root_t := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.z))
	var torso_mat_list: Array = _t_body_dark if fresh else _t_body
	# Clothing color varies per body — derived from the already-drawn yaw,
	# so the RNG stream (and every downstream draw) never shifts.
	var cloth_lists := [_t_body, _t_cloth_a, _t_cloth_b]
	var cloth: Array = cloth_lists[int(yaw * 3.0) % 3]
	# torso, arms (mirror _build_corpse dims)
	torso_mat_list.append(root_t * Transform3D(
		Basis(Vector3.UP, _rng.randf_range(-0.1, 0.1)).scaled(Vector3(0.55, 0.28, 1.05)),
		Vector3(0, 0.16, 0)))
	cloth.append(root_t * Transform3D(
		Basis(Vector3.UP, 0.12).scaled(Vector3(0.16, 0.14, 0.62)),
		Vector3(-0.38, 0.10, 0.05)))
	cloth.append(root_t * Transform3D(
		Basis(Vector3.UP, -0.10).scaled(Vector3(0.16, 0.14, 0.62)),
		Vector3(0.38, 0.10, -0.02)))
	# Torn gash on the torso (dark patch).
	_t_body_dark.append(root_t * Transform3D(
		Basis(Vector3.UP, 0.3).scaled(Vector3(0.16, 0.03, 0.13)),
		Vector3(0.12, 0.31, 0.18)))
	# Lost shoe nearby, for some bodies.
	if int(yaw * 7.0) % 4 == 0:
		_t_body_dark.append(root_t * Transform3D(
			Basis(Vector3.UP, 0.6).scaled(Vector3(0.14, 0.12, 0.32)),
			Vector3(0.58, 0.06, -1.25)))
	# legs always dark
	_t_body_dark.append(root_t * Transform3D(
		Basis(Vector3.UP, 0.05).scaled(Vector3(0.20, 0.16, 0.72)),
		Vector3(-0.14, 0.10, -0.85)))
	_t_body_dark.append(root_t * Transform3D(
		Basis(Vector3.UP, -0.06).scaled(Vector3(0.20, 0.16, 0.72)),
		Vector3(0.14, 0.10, -0.88)))
	# head
	_t_skin.append(root_t * Transform3D(
		Basis().scaled(Vector3.ONE * 0.42), Vector3(0, 0.20, 0.78)))
	if fresh or _rng.randf() < 0.3:
		_blood_ground(p, 1.5, 2.3)


# ------------------------------------------------- 3. fires ---

func _smoke(pos: Vector3, amount: int) -> void:
	# Mirrors neighborhood_builder._smoke (GPUParticles3D, billboarded soft
	# blob texture), with small particle budgets.
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.8
	p.preprocess = 2.8
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = Color(1, 1, 1, 0.5)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_texture = _smoke_tex
	qm.albedo_color = Color(0.14, 0.14, 0.15, 1.0)
	quad.material = qm
	p.draw_pass_1 = quad
	p.position = pos
	add_child(p)


func _flame(pos: Vector3, base_yaw: float) -> Array:
	# Two crossed emissive quads. Returns them for the flicker list.
	var quads: Array = []
	for k in 2:
		var q := MeshInstance3D.new()
		q.mesh = _flame_quad
		q.position = pos
		q.rotation.y = base_yaw + k * PI * 0.5
		add_child(q)
		quads.append(q)
	return quads


func _register_fire(quads: Array, with_light: bool, fire_pos: Vector3) -> void:
	var entry := {"light": null, "quads": quads,
		"phase": _rng.randf() * TAU, "base": 3.4}
	if with_light and int(_stats["lights"]) < MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.15)
		# V3: stronger light pools so burning barrels read alive at night
		# (same count, no new lights — perf cap unchanged).
		l.light_energy = 3.4
		l.omni_range = 12.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.position = fire_pos + Vector3(0, 1.2, 0)
		add_child(l)
		entry["light"] = l
		_stats["lights"] = int(_stats["lights"]) + 1
	_fires.append(entry)


func _place_barrel_fires(hood: NeighborhoodBuilder) -> void:
	# 6 barrel fires tucked beside buildings (off the door path).
	var order: Array = []
	for e in _entries(hood):
		order.append(e)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var made := 0
	for e in order:
		if made >= 6:
			break
		var d := _door_pos(e as Dictionary)
		var face := float((e as Dictionary)["face"])
		var p := d + Vector3(_rng.randf_range(3.0, 5.5) * (1.0 if _rng.randf() < 0.5 else -1.0),
			0, face * _rng.randf_range(1.0, 2.5))
		if not _clear_of_buildings(p, hood, 0.8) or not _clear_of_doors(p, hood, 2.5):
			continue
		_placed.append(p)
		var barrel := MeshInstance3D.new()
		barrel.mesh = _barrel_mesh
		barrel.material_override = _m_rust
		barrel.position = p + Vector3(0, 0.475, 0)
		add_child(barrel)
		var quads := _flame(p + Vector3(0, 0.75, 0), _rng.randf() * PI)
		_smoke(p + Vector3(0, 1.6, 0), 20)
		_blood_ground(p + Vector3(_rng.randf_range(-1.5, 1.5), 0,
			_rng.randf_range(-1.5, 1.5)), 0.4, 0.9)
		_register_fire(quads, true, p)
		made += 1
	_stats["barrel_fires"] = made


func _place_burning_wrecks(hood: NeighborhoodBuilder) -> void:
	# 2-3 burning wrecks on road edges: charred car + flames + smoke.
	var made := 0
	var want := _rng.randi_range(2, 3)
	var tries := 0
	while made < want and tries < 40:
		tries += 1
		var p := _road_point(hood, 3.2, 5.2)
		if not _spot_free(hood, p, 10.0):
			continue
		_placed.append(p)
		_wreck(p, _rng.randf() * TAU, true, false)
		var quads := _flame(p + Vector3(0, 0.9, 0), _rng.randf() * PI)
		_smoke(p + Vector3(0, 1.8, 0), 24)
		_blood_ground(p + Vector3(_rng.randf_range(-2.0, 2.0), 0,
			_rng.randf_range(-2.0, 2.0)), 0.6, 1.3)
		_register_fire(quads, false, p) # lights already spent on barrels
		made += 1
	_stats["burning_wrecks"] = made


# ------------------------------------------------- 4. wrecks ---

## Simplified burnt/smoking wreck (mirrors neighborhood_builder._car's
## proportions). No collision body — wrecks never block paths.
func _wreck(pos: Vector3, rot_y: float, burnt: bool, smoking: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	root.rotation.z = _rng.randf_range(-0.05, 0.05)
	add_child(root)
	var paint := _m_char if burnt else _m_paint[_rng.randi() % _m_paint.size()]
	_box_at(root, Vector3(4.2, 0.62, 1.9), Vector3(0, 0.63, 0), paint)
	_box_at(root, Vector3(1.0, 0.18, 1.7), Vector3(1.65, 0.98, 0), paint)
	_box_at(root, Vector3(0.9, 0.16, 1.7), Vector3(-1.7, 0.96, 0), paint)
	_box_at(root, Vector3(1.9, 0.5, 1.58), Vector3(-0.25, 1.16, 0), paint)
	_box_at(root, Vector3(1.9, 0.08, 1.58), Vector3(-0.25, 1.49, 0), paint)
	if burnt:
		_box_at(root, Vector3(1.92, 0.30, 1.60), Vector3(-0.25, 1.30, 0), _m_char)
		_box_at(root, Vector3(0.05, 0.40, 1.3), Vector3(0.76, 1.18, 0), _m_glass_dark)
	else:
		_box_at(root, Vector3(1.92, 0.30, 1.60), Vector3(-0.25, 1.30, 0), _m_glass_dark)
	# Wheels (wrecks sit crooked; some wheels missing).
	var missing := _rng.randi() % 4
	var wi := 0
	for sx in [-1.35, 1.35]:
		for sz in [-0.85, 0.85]:
			if wi != missing:
				var w := MeshInstance3D.new()
				w.mesh = _barrel_mesh
				w.material_override = _m_tire
				w.scale = Vector3(0.68, 0.24, 0.68)
				w.position = Vector3(sx, 0.34, sz)
				root.add_child(w)
			wi += 1
	# Rust patches low on the hull.
	_box_at(root, Vector3(0.34, 0.16, 0.03), Vector3(0.9, 0.45, 0.96), _m_rust)
	_box_at(root, Vector3(0.28, 0.14, 0.03), Vector3(-1.4, 0.42, -0.96), _m_rust)
	if smoking:
		_smoke(pos + Vector3(1.7, 1.4, 0).rotated(Vector3.UP, rot_y), 20)


func _box_at(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cube
	mi.material_override = mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)


func _spot_free(hood: NeighborhoodBuilder, p: Vector3, spacing: float) -> bool:
	# Off road center lines and the intersection, off buildings and door
	# paths, and spaced from my own other fire/wreck spots.
	var inter := _intersection(hood)
	if Vector2(p.x - inter.x, p.z - inter.y).length() < 8.0:
		return false
	if absf(p.z - hood.road_ew_z) < 3.0 and absf(p.x - inter.x) > 8.0:
		return false
	if absf(p.x - hood.road_ns_x) < 3.0 and absf(p.z - inter.y) > 8.0:
		return false
	if not _clear_of_buildings(p, hood, 1.5):
		return false
	if not _clear_of_doors(p, hood, 3.0):
		return false
	for q in _placed:
		if Vector2(p.x - q.x, p.z - q.z).length() < spacing:
			return false
	return true


func _place_wrecks(hood: NeighborhoodBuilder) -> void:
	# 4-6 extra wrecks (smoking or burnt), road edges, never blocking.
	var made := 0
	var want := _rng.randi_range(4, 6)
	var tries := 0
	while made < want and tries < 60:
		tries += 1
		var p := _road_point(hood, 3.2, 5.2)
		if not _spot_free(hood, p, 10.0):
			continue
		_placed.append(p)
		var burnt := _rng.randf() < 0.5
		_wreck(p, _rng.randf() * TAU, burnt, not burnt and _rng.randf() < 0.7)
		if _rng.randf() < 0.5:
			_blood_ground(p + Vector3(_rng.randf_range(-2.0, 2.0), 0,
				_rng.randf_range(-2.0, 2.0)), 0.5, 1.1)
		made += 1
	_stats["wrecks"] = made


# ------------------------------------------------- 5. rubble ---

func _place_rubble(hood: NeighborhoodBuilder) -> void:
	# 8-12 low piles of broken concrete/wood near buildings and road edges.
	var made := 0
	var want := _rng.randi_range(8, 12)
	var tries := 0
	while made < want and tries < 80:
		tries += 1
		var p: Vector3
		if _rng.randf() < 0.6:
			var ents := _entries(hood)
			var e := ents[_rng.randi() % ents.size()] as Dictionary
			var c := e["pos"] as Vector3
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(float(e["w"]) * 0.5 + 1.0, float(e["w"]) * 0.5 + 3.5)
			p = c + Vector3(cos(a) * r, 0, sin(a) * r * 0.8)
		else:
			p = _road_point(hood, 5.5, 7.5)
		if not _clear_of_buildings(p, hood, 0.5) or not _clear_of_doors(p, hood, 2.0):
			continue
		for i in _rng.randi_range(5, 8):
			var a2 := _rng.randf() * TAU
			var r2 := _rng.randf_range(0.1, 1.4)
			var s := _rng.randf_range(0.22, 0.65)
			var t := Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(
					Vector3(s, s * _rng.randf_range(0.5, 0.9), s)),
				p + Vector3(cos(a2) * r2, s * 0.25, sin(a2) * r2))
			if _rng.randf() < 0.7:
				_t_concrete.append(t)
			else:
				_t_woodchunk.append(t)
		made += 1
	_stats["rubble"] = made


# ------------------------------------------------- 6. scorch ---

## V3: scorch decals + charred chunks + ash drifts around every fire/wreck
## spot, derived from the already-placed positions. Runs after all
## existing placements, so every pre-existing RNG draw (and every QA
## stat) is untouched; adds only its own draws at the end of the stream.
func _place_scorch(hood: NeighborhoodBuilder) -> void:
	for p in _placed:
		for _i in _rng.randi_range(2, 3):
			var s := _rng.randf_range(1.2, 2.8)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.4, 1.6)
			_t_scorch.append(Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(
					Vector3(s, 1, s * _rng.randf_range(0.7, 1.0))),
				Vector3(p.x + cos(a) * r, 0.025, p.z + sin(a) * r)))
		for _i in _rng.randi_range(4, 7):
			var s2 := _rng.randf_range(0.18, 0.5)
			var a2 := _rng.randf() * TAU
			var r2 := _rng.randf_range(0.6, 2.4)
			_t_char.append(Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(
					Vector3(s2, s2 * _rng.randf_range(0.4, 0.8), s2)),
				Vector3(p.x + cos(a2) * r2, s2 * 0.25, p.z + sin(a2) * r2)))
		if _rng.randf() < 0.4:
			for _i in 2:
				var s3 := _rng.randf_range(0.9, 1.8)
				var a3 := _rng.randf() * TAU
				var r3 := _rng.randf_range(1.0, 3.0)
				_t_ash.append(Transform3D(
					Basis(Vector3.UP, _rng.randf() * TAU).scaled(
						Vector3(s3, 1, s3 * _rng.randf_range(0.5, 0.9))),
					Vector3(p.x + cos(a3) * r3, 0.022, p.z + sin(a3) * r3)))
