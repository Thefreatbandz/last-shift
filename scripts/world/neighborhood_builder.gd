class_name NeighborhoodBuilder
extends Node3D
## Procedurally builds the Phase 1 residential neighborhood from a fixed seed:
## ground, roads + sidewalks, houses (one boarded-up future safehouse),
## streetlights, trees, fences, abandoned cars (one smoking), trash,
## a gas station corner, and invisible boundary walls. All collision is
## simple StaticBody3D boxes. Shared materials keep draw state cheap.
##
## HD world pass: houses get trim (corner boards, foundation, fascia,
## ridge caps), framed windows with sills + shutters, paneled doors with
## frames and steps, per-house roof colors, furnished interiors (couch
## with cushions, bookshelf with books, rug, floor lamp), lawns, curbs,
## grass tufts + debris via MultiMesh, detailed cars (pillars, hubs,
## bumpers, headlights), faceted trees/bushes, and distant silhouettes.

const SEED := 20260928
const MAP_HALF := 74.0

var _rng := RandomNumberGenerator.new()
var _time := 0.0

# Animated / night-driven materials.
var _window_lit_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _cone_mat: StandardMaterial3D
var _spot_lights: Array[SpotLight3D] = []
var _smoke_tex: ImageTexture

# Tree canopy pivots for wind sway: each entry [Node3D, phase, amplitude].
var _sway: Array = []

# Phase 3: the boarded-up future safehouse exposes its planks (so claiming
# can knock them down) and its door on a hinge pivot (so it can swing open).
var safehouse_boards: Array[MeshInstance3D] = []
var safehouse_door_pivot: Node3D

# QA pass: every house is enterable. houses[] entries are Dictionaries:
# {pos, w, d, face, roof (Node3D), door: {pivot, blocker, pos, open, safehouse}}
var houses: Array = []

# Static shared materials.
var _m_roof: StandardMaterial3D
var _m_chimney: StandardMaterial3D
var _m_door: StandardMaterial3D
var _m_door_panel: StandardMaterial3D
var _m_window_dark: StandardMaterial3D
var _m_pole: StandardMaterial3D
var _m_bark: StandardMaterial3D
var _m_leaf: StandardMaterial3D
var _m_leaf2: StandardMaterial3D
var _m_wood: StandardMaterial3D
var _m_tire: StandardMaterial3D
var _m_glass: StandardMaterial3D
var _m_trash: StandardMaterial3D
var _m_board: StandardMaterial3D
# HD pass materials.
var _m_trim: StandardMaterial3D      # warm off-white: corner boards, fascia, frames
var _m_shutter: StandardMaterial3D   # muted shutter color
var _m_foundation: StandardMaterial3D # concrete foundation skirt
var _m_step: StandardMaterial3D      # concrete doorstep
var _m_couch: StandardMaterial3D
var _m_cushion: StandardMaterial3D
var _m_table: StandardMaterial3D
var _m_shelf: StandardMaterial3D
var _m_rug: StandardMaterial3D
var _m_rug_edge: StandardMaterial3D
var _m_floor: StandardMaterial3D
var _m_lawn: StandardMaterial3D
var _m_tuft: StandardMaterial3D
var _m_debris: StandardMaterial3D
var _m_bush: StandardMaterial3D
var _m_barrel: StandardMaterial3D
var _m_barrel_band: StandardMaterial3D
var _m_bumper: StandardMaterial3D
var _m_hub: StandardMaterial3D
var _m_rust: StandardMaterial3D
var _m_headlight: StandardMaterial3D # emissive, night-driven via lamp mat trick
var _m_silhouette: StandardMaterial3D # unshaded dark: distant skyline/treeline
var _m_curb: StandardMaterial3D
var _m_canopy_edge: StandardMaterial3D
var _m_inner: StandardMaterial3D


func _ready() -> void:
	_rng.seed = SEED
	_make_materials()
	_build_ground()
	_build_roads()
	_build_houses()
	_build_streetlights()
	_build_trees()
	_build_fences()
	_build_cars()
	_build_gas_station()
	_build_props()
	_build_silhouettes()
	_build_boundary()


func _process(delta: float) -> void:
	_time += delta
	for s in _sway:
		var n := s[0] as Node3D
		var phase := float(s[1])
		var amp := float(s[2])
		n.rotation.z = sin(_time * 1.3 + phase) * amp
		n.rotation.x = cos(_time * 0.9 + phase) * amp * 0.6


func set_night_factor(f: float) -> void:
	_window_lit_mat.emission_energy_multiplier = lerpf(0.15, 2.6, f)
	_lamp_mat.emission_energy_multiplier = lerpf(0.4, 4.0, f)
	var c := _cone_mat.albedo_color
	c.a = lerpf(0.03, 0.14, f)
	_cone_mat.albedo_color = c
	for sp in _spot_lights:
		sp.light_energy = lerpf(0.0, 3.0, f)


# ---------------------------------------------------------------- materials ---

func _std(c: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _make_materials() -> void:
	_m_roof = _std(Color(0.23, 0.20, 0.18))
	_m_roof.cull_mode = BaseMaterial3D.CULL_DISABLED # hand-built prism: skip winding worries
	_m_chimney = _std(Color(0.36, 0.23, 0.18))
	_m_door = _std(Color(0.15, 0.12, 0.10))
	_m_door_panel = _std(Color(0.19, 0.15, 0.12), 0.8)
	_m_window_dark = _std(Color(0.07, 0.09, 0.12), 0.25, 0.6)
	_m_pole = _std(Color(0.15, 0.15, 0.16), 0.6, 0.4)
	_m_bark = _std(Color(0.25, 0.18, 0.12))
	_m_leaf = _std(Color(0.15, 0.23, 0.13))
	_m_leaf2 = _std(Color(0.12, 0.19, 0.11))
	_m_wood = _std(Color(0.32, 0.24, 0.16))
	_m_tire = _std(Color(0.08, 0.08, 0.09))
	_m_glass = _std(Color(0.06, 0.08, 0.10), 0.2, 0.7)
	_m_trash = _std(Color(0.10, 0.10, 0.11))
	_m_board = _std(Color(0.42, 0.32, 0.20))
	# HD pass.
	_m_trim = _std(Color(0.78, 0.74, 0.66), 0.85)
	_m_shutter = _std(Color(0.24, 0.28, 0.30), 0.9)
	_m_foundation = _std(Color(0.45, 0.44, 0.42), 0.95)
	_m_step = _std(Color(0.52, 0.51, 0.48), 0.95)
	_m_couch = _std(Color(0.34, 0.29, 0.24), 0.95)
	_m_cushion = _std(Color(0.40, 0.34, 0.28), 0.95)
	_m_table = _std(Color(0.36, 0.28, 0.18), 0.8)
	_m_shelf = _std(Color(0.30, 0.23, 0.15), 0.85)
	_m_rug = _std(Color(0.45, 0.20, 0.16), 1.0)
	_m_rug_edge = _std(Color(0.30, 0.14, 0.12), 1.0)
	_m_floor = _std(Color(0.20, 0.15, 0.10), 0.85)
	_m_lawn = _std(Color(0.20, 0.26, 0.15), 1.0)
	_m_tuft = _std(Color(0.24, 0.32, 0.16), 1.0)
	_m_debris = _std(Color(0.16, 0.15, 0.13), 1.0)
	_m_bush = _std(Color(0.13, 0.21, 0.12), 1.0)
	_m_barrel = _std(Color(0.35, 0.22, 0.12), 0.7, 0.3)
	_m_barrel_band = _std(Color(0.20, 0.20, 0.21), 0.6, 0.5)
	_m_bumper = _std(Color(0.18, 0.18, 0.19), 0.5, 0.4)
	_m_hub = _std(Color(0.45, 0.45, 0.46), 0.4, 0.6)
	_m_rust = _std(Color(0.30, 0.18, 0.10), 0.95)
	_m_curb = _std(Color(0.50, 0.50, 0.50), 0.95)
	_m_canopy_edge = _std(Color(0.62, 0.16, 0.12), 0.8)
	_m_inner = _std(Color(0.40, 0.36, 0.30), 0.95) # interior wall paint

	_m_headlight = StandardMaterial3D.new()
	_m_headlight.albedo_color = Color(0.85, 0.82, 0.70)
	_m_headlight.emission_enabled = true
	_m_headlight.emission = Color(1.0, 0.90, 0.60)
	_m_headlight.emission_energy_multiplier = 0.25

	_m_silhouette = StandardMaterial3D.new()
	_m_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_m_silhouette.albedo_color = Color(0.10, 0.12, 0.18)

	_window_lit_mat = StandardMaterial3D.new()
	_window_lit_mat.albedo_color = Color(0.10, 0.09, 0.08)
	_window_lit_mat.emission_enabled = true
	_window_lit_mat.emission = Color(1.0, 0.62, 0.28)
	_window_lit_mat.emission_energy_multiplier = 0.15

	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.9, 0.85, 0.75)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.80, 0.50)
	_lamp_mat.emission_energy_multiplier = 0.4

	_cone_mat = StandardMaterial3D.new()
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.albedo_color = Color(1.0, 0.80, 0.50, 0.03)

	_smoke_tex = _radial_texture(64)


# ------------------------------------------------------------------ helpers ---

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, facets := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	if facets:
		sm.radial_segments = 8
		sm.rings = 5
	else:
		sm.radial_segments = 12
		sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.position = pos
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


## Wall / furniture block: visible box + matching collision in one node.
func _solid_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if mat != null:
		mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Gable-roof prism: triangular cross-section in XY, ridge running along Z.
func _prism_mesh(hw: float, h: float, d: float) -> ArrayMesh:
	var hd := d * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(0, h, hd), Vector3(0, h, -hd),
		Vector3(-h, hw, 0).normalized()) # left slope
	_quad(st, Vector3(hw, 0, -hd), Vector3(0, h, -hd), Vector3(0, h, hd), Vector3(hw, 0, hd),
		Vector3(h, hw, 0).normalized()) # right slope
	_tri(st, Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(0, h, -hd), Vector3(0, 0, -1)) # gable
	_tri(st, Vector3(hw, 0, hd), Vector3(-hw, 0, hd), Vector3(0, h, hd), Vector3(0, 0, 1)) # gable
	return st.commit()


func _noise_texture(base: Color, variation: float, cells: int, px: int) -> ImageTexture:
	var grid := PackedFloat32Array()
	grid.resize(cells * cells)
	for i in grid.size():
		grid[i] = _rng.randf()
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var gx := float(x) / float(px) * float(cells)
			var gy := float(y) / float(px) * float(cells)
			var x0 := int(floorf(gx)) % cells
			var y0 := int(floorf(gy)) % cells
			var x1 := (x0 + 1) % cells
			var y1 := (y0 + 1) % cells
			var fx := gx - floorf(gx)
			var fy := gy - floorf(gy)
			var a := lerpf(grid[y0 * cells + x0], grid[y0 * cells + x1], fx)
			var b := lerpf(grid[y1 * cells + x0], grid[y1 * cells + x1], fx)
			var v := lerpf(a, b, fy)
			var grain := 0.92 + 0.16 * _rng.randf()
			var shade := (1.0 - variation + variation * v) * grain
			img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	return ImageTexture.create_from_image(img)


func _radial_texture(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var half := float(px) * 0.5
	for y in px:
		for x in px:
			var d := Vector2(float(x) - half + 0.5, float(y) - half + 0.5).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------------- world ---

func _build_ground() -> void:
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _noise_texture(Color(0.16, 0.19, 0.13), 0.45, 10, 128)
	gm.uv1_scale = Vector3(11, 11, 11)
	gm.roughness = 1.0
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(MAP_HALF * 2.0 + 2.0, MAP_HALF * 2.0 + 2.0)
	mi.mesh = pm
	mi.position = Vector3(0, -0.02, 0)
	mi.material_override = gm
	add_child(mi)
	# Simple static floor so the player always has ground collision.
	# QA fix: a real thin box (two-sided) instead of a one-sided world
	# boundary plane — nothing can ever tunnel below it and fall forever.
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(MAP_HALF * 2.0 + 4.0, 1.0, MAP_HALF * 2.0 + 4.0)
	cs.shape = bs
	cs.position = Vector3(0, -0.52, 0) # top face sits at y = -0.02, under the visual plane
	sb.add_child(cs)
	add_child(sb)
	_build_grass_tufts()
	_build_debris()


func _on_grass_ok(p: Vector3) -> bool:
	# Reject roads, sidewalks and house footprints.
	if absf(p.z) < 7.0:
		return false
	if absf(p.x - 20.0) < 7.0:
		return false
	for h in houses:
		var hp := (h as Dictionary)["pos"] as Vector3
		var hw := float((h as Dictionary)["w"]) * 0.5 + 2.5
		var hd := float((h as Dictionary)["d"]) * 0.5 + 2.5
		if absf(p.x - hp.x) < hw and absf(p.z - hp.z) < hd:
			return false
	return true


func _build_grass_tufts() -> void:
	# One draw call: ~220 low-poly tufts scattered on lawns.
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.02
	tuft.bottom_radius = 0.10
	tuft.height = 0.42
	tuft.radial_segments = 5
	tuft.material = _m_tuft
	var xf: Array[Transform3D] = []
	var tries := 0
	while xf.size() < 220 and tries < 1200:
		tries += 1
		var p := Vector3(_rng.randf_range(-70, 70), 0.19, _rng.randf_range(-70, 70))
		if not _on_grass_ok(p):
			continue
		var s := _rng.randf_range(0.7, 1.5)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
		xf.append(Transform3D(b, p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_debris() -> void:
	# One draw call: worn paper/rubble patches near curbs.
	var patch := PlaneMesh.new()
	patch.size = Vector2(0.5, 0.35)
	patch.material = _m_debris
	var xf: Array[Transform3D] = []
	var tries := 0
	while xf.size() < 90 and tries < 600:
		tries += 1
		var p := Vector3(_rng.randf_range(-68, 68), 0.012, _rng.randf_range(-68, 68))
		var near_road := absf(absf(p.z) - 7.5) < 2.5 or absf(absf(p.x - 20.0) - 7.5) < 2.5
		if not near_road:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(
			Vector3(_rng.randf_range(0.6, 1.6), 1.0, _rng.randf_range(0.6, 1.4)))
		xf.append(Transform3D(b, p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = patch
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_roads() -> void:
	var rm := StandardMaterial3D.new()
	rm.albedo_texture = _noise_texture(Color(0.13, 0.13, 0.14), 0.35, 8, 128)
	rm.uv1_scale = Vector3(16, 16, 16)
	rm.roughness = 0.95
	var sm := _std(Color(0.42, 0.42, 0.43), 0.95) # sidewalk
	var dm := _std(Color(0.75, 0.68, 0.35)) # center dashes
	_box(self, Vector3(140, 0.02, 8), Vector3(0, -0.01, 0), rm) # EW road
	_box(self, Vector3(8, 0.02, 140), Vector3(20, -0.01, 0), rm) # NS road
	_box(self, Vector3(140, 0.02, 2), Vector3(0, -0.005, -5), sm) # sidewalks
	_box(self, Vector3(140, 0.02, 2), Vector3(0, -0.005, 5), sm)
	_box(self, Vector3(2, 0.02, 140), Vector3(14, -0.005, 0), sm)
	_box(self, Vector3(2, 0.02, 140), Vector3(26, -0.005, 0), sm)
	# Curbs: raised concrete lips along every sidewalk edge.
	for cz in [-6.05, -3.95, 3.95, 6.05]:
		_box(self, Vector3(140, 0.14, 0.18), Vector3(0, 0.05, cz), _m_curb)
	for cx in [12.95, 15.05, 24.95, 27.05]:
		_box(self, Vector3(0.18, 0.14, 140), Vector3(cx, 0.05, 0), _m_curb)
	for x in range(-66, 67, 6):
		_box(self, Vector3(1.6, 0.012, 0.18), Vector3(x, 0.004, 0), dm)
	for z in range(-66, 67, 6):
		if absf(z) > 7.0: # keep the intersection clear
			_box(self, Vector3(0.18, 0.012, 1.6), Vector3(20, 0.004, z), dm)


func _house(pos: Vector3, face: float, w: float, d: float, wall: Color, roof_c: Color, boarded: bool) -> void:
	# QA pass: houses are enterable — four real walls (front wall has a door
	# gap), a hinged door every house gets, a simple furnished interior, and
	# a roof group that hides while the player is inside (camera would
	# otherwise clip through it).
	# HD pass: trim everywhere — corner boards, foundation skirt, fascia,
	# ridge cap, framed windows with sills + shutters, paneled door with
	# frame + step, per-house roof color, lawn patch.
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var h := 3.2
	var t := 0.3 # wall thickness
	var wall_mat := _std(wall)
	var fz := face * (d * 0.5) # front wall plane (local)
	var door_w := 1.4
	var door_h := 2.2
	# Back wall + side walls (full).
	_solid_box(root, Vector3(w, h, t), Vector3(0, h * 0.5, -face * d * 0.5), wall_mat)
	_solid_box(root, Vector3(t, h, d), Vector3(-w * 0.5, h * 0.5, 0), wall_mat)
	_solid_box(root, Vector3(t, h, d), Vector3(w * 0.5, h * 0.5, 0), wall_mat)
	# Front wall: two segments leaving a door gap, plus a lintel above it.
	var seg_w := (w - door_w) * 0.5
	_solid_box(root, Vector3(seg_w, h, t),
		Vector3(-(door_w * 0.5 + seg_w * 0.5), h * 0.5, fz), wall_mat)
	_solid_box(root, Vector3(seg_w, h, t),
		Vector3(door_w * 0.5 + seg_w * 0.5, h * 0.5, fz), wall_mat)
	_solid_box(root, Vector3(door_w, h - door_h, t),
		Vector3(0, door_h + (h - door_h) * 0.5, fz), wall_mat)
	# Interior wall liner: warmer, darker paint on the inner faces so the
	# roofless interior (roof hides while the player is inside) doesn't
	# blow out under direct sun.
	_box(root, Vector3(w - 0.2, h, 0.08), Vector3(0, h * 0.5, -face * (d * 0.5 - 0.19)), _m_inner)
	_box(root, Vector3(0.08, h, d - 0.2), Vector3(-(w * 0.5 - 0.19), h * 0.5, 0), _m_inner)
	_box(root, Vector3(0.08, h, d - 0.2), Vector3(w * 0.5 - 0.19, h * 0.5, 0), _m_inner)
	_box(root, Vector3(seg_w, h, 0.08),
		Vector3(-(door_w * 0.5 + seg_w * 0.5), h * 0.5, fz - face * 0.19), _m_inner)
	_box(root, Vector3(seg_w, h, 0.08),
		Vector3(door_w * 0.5 + seg_w * 0.5, h * 0.5, fz - face * 0.19), _m_inner)
	# Foundation skirt: concrete base the walls sit on.
	# Foundation skirt: top sits just under the interior floor slab so the
	# floor (not the concrete) is the visible walking surface.
	_box(root, Vector3(w + 0.34, 0.30, d + 0.34), Vector3(0, -0.10, 0), _m_foundation)
	# Corner boards.
	for cx in [-w * 0.5, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			_box(root, Vector3(0.26, h, 0.26), Vector3(cx, h * 0.5, cz), _m_trim)
	# Roof group (hidden while the player is inside).
	var roof_g := Node3D.new()
	root.add_child(roof_g)
	var roof_mat := _std(roof_c, 0.95)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var roof := MeshInstance3D.new()
	roof.mesh = _prism_mesh(w * 0.5 + 0.5, 1.9, d + 1.0)
	roof.position = Vector3(0, h, 0)
	roof.material_override = roof_mat
	roof_g.add_child(roof)
	# Ridge cap + fascia boards along the eaves.
	_box(roof_g, Vector3(0.34, 0.16, d + 1.05), Vector3(0, h + 1.95, 0), roof_mat)
	for ex in [-1.0, 1.0]:
		_box(roof_g, Vector3(0.16, 0.26, d + 1.05),
			Vector3(ex * (w * 0.5 + 0.5), h + 0.10, 0), _m_trim)
	# Chimney with cap.
	_box(roof_g, Vector3(0.6, 1.2, 0.6), Vector3(w * 0.25, h + 1.3, d * 0.12), _m_chimney)
	_box(roof_g, Vector3(0.8, 0.14, 0.8), Vector3(w * 0.25, h + 1.95, d * 0.12), _m_trim)
	# Door frame + paneled door on a hinge pivot (left edge).
	var fz_out := fz + face * (t * 0.5)
	_box(root, Vector3(0.18, door_h + 0.18, 0.16),
		Vector3(-door_w * 0.5 - 0.09, (door_h + 0.18) * 0.5, fz_out), _m_trim)
	_box(root, Vector3(0.18, door_h + 0.18, 0.16),
		Vector3(door_w * 0.5 + 0.09, (door_h + 0.18) * 0.5, fz_out), _m_trim)
	_box(root, Vector3(door_w + 0.36, 0.18, 0.16),
		Vector3(0, door_h + 0.09, fz_out), _m_trim)
	var pivot := Node3D.new()
	pivot.position = Vector3(-door_w * 0.5, 0, fz)
	root.add_child(pivot)
	_box(pivot, Vector3(door_w, door_h, 0.12), Vector3(door_w * 0.5, door_h * 0.5, 0), _m_door)
	# Raised door panels (upper + lower inset look).
	_box(pivot, Vector3(door_w - 0.4, 0.72, 0.05),
		Vector3(door_w * 0.5, 1.62, 0.075), _m_door_panel)
	_box(pivot, Vector3(door_w - 0.4, 0.72, 0.05),
		Vector3(door_w * 0.5, 0.62, 0.075), _m_door_panel)
	# Concrete step.
	_box(root, Vector3(2.3, 0.18, 1.2),
		Vector3(0, 0.07, fz + face * 0.75), _m_step)
	# Doorway blocker: solid while the door is closed, disabled when open.
	var blocker := _solid(root, Vector3(door_w, door_h, 0.24), Vector3(0, door_h * 0.5, fz))
	_build_interior(root, w, d, face)
	# Lawn patch grounding the house.
	_box(root, Vector3(w + 5.0, 0.02, d + 5.0), Vector3(0, 0.005, 0), _m_lawn)
	# Windows: framed, with sills; shutters on the front pair.
	var out_f := face * (d * 0.5 + t * 0.5 + 0.03)
	_window(root, Vector3(-w * 0.28, 1.7, out_f), Vector3(0, 0, face), true)
	_window(root, Vector3(w * 0.28, 1.7, out_f), Vector3(0, 0, face), true)
	_window(root, Vector3(-w * 0.5 - t * 0.5 - 0.03, 1.7, 0.0), Vector3(-1, 0, 0), false)
	_window(root, Vector3(w * 0.5 + t * 0.5 + 0.03, 1.7, 0.0), Vector3(1, 0, 0), false)
	if boarded:
		_boards(root, fz + face * (t * 0.5 + 0.07), w)
		safehouse_door_pivot = pivot
	var door := {
		"pivot": pivot, "blocker": blocker,
		"pos": pos + Vector3(0, 0, fz), "open": false, "safehouse": boarded,
	}
	houses.append({"pos": pos, "w": w, "d": d, "face": face, "roof": roof_g, "door": door})


func _build_interior(root: Node3D, w: float, d: float, face: float) -> void:
	# HD furnished interior. The loot container spot (local x ≈ -w/2+1,
	# front wall) stays clear — main.gd places one searchable container
	# per house there. Door swing zone (x in [-0.7, 0.7] near front) clear.
	_box(root, Vector3(w - 0.7, 0.06, d - 0.7), Vector3(0, 0.03, 0), _m_floor)
	var back := -face * (d * 0.5 - 1.2)
	# Couch: base, back, arms, two cushions — against the back wall, right of the loot corner.
	var cx := w * 0.18
	_solid_box(root, Vector3(2.1, 0.55, 0.95), Vector3(cx, 0.32, back), _m_couch)
	_solid_box(root, Vector3(2.1, 0.75, 0.28), Vector3(cx, 0.65, back - face * 0.42), _m_couch)
	for ax in [-1.0, 1.0]:
		_solid_box(root, Vector3(0.28, 0.85, 0.95), Vector3(cx + ax, 0.48, back), _m_couch)
	_box(root, Vector3(0.82, 0.16, 0.8), Vector3(cx - 0.46, 0.66, back + face * 0.05), _m_cushion)
	_box(root, Vector3(0.82, 0.16, 0.8), Vector3(cx + 0.46, 0.66, back + face * 0.05), _m_cushion)
	# Coffee table with lower shelf.
	var tx := w * 0.18
	var tz := back + face * 1.9
	_box(root, Vector3(1.4, 0.1, 0.8), Vector3(tx, 0.62, tz), _m_table)
	_box(root, Vector3(1.2, 0.06, 0.6), Vector3(tx, 0.22, tz), _m_shelf)
	for sx in [-0.6, 0.6]:
		for sz in [-0.32, 0.32]:
			_box(root, Vector3(0.09, 0.57, 0.09), Vector3(tx + sx, 0.31, tz + sz), _m_table)
	_solid(root, Vector3(1.4, 0.65, 0.8), Vector3(tx, 0.33, tz))
	# Rug: layered flat boxes in the middle of the room.
	_box(root, Vector3(2.8, 0.035, 2.0), Vector3(0.9, 0.075, -face * 0.6), _m_rug_edge)
	_box(root, Vector3(2.4, 0.035, 1.6), Vector3(0.9, 0.085, -face * 0.6), _m_rug)
	# Bookshelf on the right wall with book spines.
	var shx := w * 0.5 - 0.65
	_solid_box(root, Vector3(0.45, 2.0, 1.7), Vector3(shx, 1.0, 0.2), _m_shelf)
	for sy in [0.55, 1.05, 1.55]:
		_box(root, Vector3(0.4, 0.05, 1.6), Vector3(shx - 0.02, sy, 0.2), _m_trim)
		var bx := -0.6
		while bx < 0.6:
			var bw := _rng.randf_range(0.09, 0.16)
			var bh := _rng.randf_range(0.28, 0.42)
			var cols := [Color(0.45, 0.22, 0.16), Color(0.22, 0.30, 0.38),
				Color(0.38, 0.34, 0.22), Color(0.25, 0.32, 0.22)]
			var bcol: Color = cols[_rng.randi() % 4]
			_box(root, Vector3(0.30, bh, bw),
				Vector3(shx - 0.05, sy + 0.03 + bh * 0.5, 0.2 + bx + bw * 0.5), _std(bcol, 0.9))
			bx += bw + 0.02
	# Floor lamp in the back-right corner; shade glows at night.
	var lx := w * 0.5 - 1.2
	var lz := -face * (d * 0.5 - 1.0)
	_cyl(root, 0.05, 0.16, 0.08, Vector3(lx, 0.10, lz), _m_pole)
	_cyl(root, 0.035, 0.035, 1.5, Vector3(lx, 0.85, lz), _m_pole)
	_cyl(root, 0.22, 0.30, 0.34, Vector3(lx, 1.75, lz), _window_lit_mat)
	_solid(root, Vector3(0.35, 1.9, 0.35), Vector3(lx, 0.95, lz))


func _window(root: Node3D, center: Vector3, outward: Vector3, shutters: bool) -> void:
	# Framed window: trim frame behind the pane, sill below, shutters beside.
	var mat: StandardMaterial3D = _window_lit_mat if _rng.randf() < 0.55 else _m_window_dark
	var along_x := absf(outward.z) > 0.5
	var fw := Vector3(1.36, 1.46, 0.08) if along_x else Vector3(0.08, 1.46, 1.36)
	var pw := Vector3(1.10, 1.20, 0.10) if along_x else Vector3(0.10, 1.20, 1.10)
	var sw := Vector3(1.44, 0.10, 0.22) if along_x else Vector3(0.22, 0.10, 1.44)
	_box(root, fw, center - outward * 0.03, _m_trim)
	_box(root, pw, center, mat)
	# Cross muntin so the pane reads as a real window.
	var mw := Vector3(0.06, 1.20, 0.12) if along_x else Vector3(0.12, 1.20, 0.06)
	var mh := Vector3(1.10, 0.06, 0.12) if along_x else Vector3(0.12, 0.06, 1.10)
	_box(root, mw, center + outward * 0.02, _m_trim)
	_box(root, mh, center + outward * 0.02, _m_trim)
	_box(root, sw, center + Vector3(0, -0.76, 0) + outward * 0.08, _m_trim)
	if shutters:
		var off := Vector3(1.02, 0, 0) if along_x else Vector3(0, 0, 1.02)
		var shw := Vector3(0.52, 1.34, 0.06) if along_x else Vector3(0.06, 1.34, 0.52)
		_box(root, shw, center + off, _m_shutter)
		_box(root, shw, center - off, _m_shutter)


func _boards(root: Node3D, fz: float, w: float) -> void:
	# Nailed planks across the door and front windows: the future safehouse.
	# Door planks are tracked so Phase 3 can knock them down on claim.
	for y in [0.8, 1.35, 1.9]:
		var p := _box(root, Vector3(1.7, 0.22, 0.1), Vector3(0, y, fz + 0.10), _m_board)
		p.rotation.z = 0.12 if int(y * 10.0) % 2 == 0 else -0.12
		safehouse_boards.append(p)
	for wx in [-w * 0.28, w * 0.28]:
		for y in [1.45, 1.95]:
			var p2 := _box(root, Vector3(1.6, 0.22, 0.1), Vector3(wx, y, fz + 0.10), _m_board)
			p2.rotation.z = -0.18 if wx < 0.0 else 0.18
			safehouse_boards.append(p2)


func _build_houses() -> void:
	var walls := [
		Color(0.62, 0.58, 0.50), # weathered beige
		Color(0.45, 0.50, 0.55), # gray blue
		Color(0.55, 0.38, 0.32), # faded brick
		Color(0.48, 0.52, 0.42), # sage
		Color(0.58, 0.55, 0.48),
		Color(0.42, 0.44, 0.48),
		Color(0.60, 0.48, 0.38),
	]
	var roofs := [
		Color(0.23, 0.20, 0.18), # charcoal
		Color(0.38, 0.22, 0.16), # brick red
		Color(0.22, 0.23, 0.26), # slate
		Color(0.25, 0.28, 0.20), # moss
	]
	var specs := [
		[Vector3(-46, 0, -20), 1.0, 8.0, 7.0, 0, 0, false],
		[Vector3(-26, 0, -21), 1.0, 7.5, 6.5, 1, 2, false],
		[Vector3(-6, 0, -20), 1.0, 8.5, 7.0, 2, 1, true], # boarded: future safehouse
		[Vector3(-38, 0, 20), -1.0, 8.0, 7.0, 3, 3, false],
		[Vector3(-14, 0, 21), -1.0, 7.0, 6.5, 4, 0, false],
		[Vector3(12, 0, 20), -1.0, 8.0, 7.0, 5, 2, false],
		[Vector3(-56, 0, 8), -1.0, 7.5, 6.5, 6, 1, false],
	]
	for s in specs:
		_house(s[0], s[1], s[2], s[3], walls[int(s[4])], roofs[int(s[5])], bool(s[6]))


func _build_streetlights() -> void:
	var spots := [
		Vector3(-52, 0, -5.6), Vector3(-32, 0, 5.6), Vector3(-12, 0, -5.6),
		Vector3(8, 0, 5.6), Vector3(32, 0, -5.6), Vector3(52, 0, 5.6),
		Vector3(14.4, 0, -30), Vector3(25.6, 0, 26),
	]
	var real_light_idx := {1: true, 2: true, 3: true}
	for i in spots.size():
		var pos: Vector3 = spots[i]
		# Arm reaches toward the nearest road.
		var arm_dir := Vector3(0, 0, 1) if pos.z < 0.0 else Vector3(0, 0, -1)
		if absf(pos.x - 20.0) < absf(pos.z):
			arm_dir = Vector3(1, 0, 0) if pos.x < 20.0 else Vector3(-1, 0, 0)
		_streetlight(pos, arm_dir, real_light_idx.has(i))


func _streetlight(pos: Vector3, arm_dir: Vector3, with_spot: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.16, 0.24, 0.5, Vector3(0, 0.25, 0), _m_pole) # base flare
	_cyl(root, 0.09, 0.12, 5.6, Vector3(0, 2.8, 0), _m_pole)
	var yaw := atan2(-arm_dir.z, arm_dir.x)
	var arm_mid := Vector3(arm_dir.x * 0.85, 5.5, arm_dir.z * 0.85)
	_box(root, Vector3(1.8, 0.1, 0.14), arm_mid, _m_pole, yaw)
	var head := Vector3(arm_dir.x * 1.6, 5.42, arm_dir.z * 1.6)
	_box(root, Vector3(0.55, 0.16, 0.32), head, _m_pole, yaw)
	_sphere(root, 0.14, head + Vector3(0, -0.18, 0), _lamp_mat) # bulb
	_cyl(root, 0.28, 2.3, 5.0, head + Vector3(0, -2.75, 0), _cone_mat) # fake glow cone
	_solid(root, Vector3(0.4, 5.6, 0.4), Vector3(0, 2.8, 0))
	if with_spot:
		var sp := SpotLight3D.new()
		sp.position = head + Vector3(0, -0.3, 0)
		sp.rotation.x = -PI * 0.5
		sp.spot_range = 16.0
		sp.spot_angle = 42.0
		sp.light_color = Color(1.0, 0.75, 0.45)
		sp.light_energy = 0.0
		sp.shadow_enabled = false
		root.add_child(sp)
		_spot_lights.append(sp)


func _build_trees() -> void:
	var spots := [
		Vector3(-58, 0, -32), Vector3(-40, 0, -34), Vector3(-20, 0, -33),
		Vector3(0, 0, -34), Vector3(34, 0, -34), Vector3(56, 0, -32),
		Vector3(-58, 0, 34), Vector3(-38, 0, 36), Vector3(-16, 0, 34),
		Vector3(8, 0, 36), Vector3(36, 0, 34), Vector3(58, 0, 32),
		Vector3(-64, 0, -8), Vector3(-64, 0, 20), Vector3(60, 0, 8),
	]
	for p in spots:
		var j := Vector3(p.x + _rng.randf_range(-2.0, 2.0), 0, p.z + _rng.randf_range(-2.0, 2.0))
		_tree(j, _rng.randf_range(0.85, 1.25))
	# Bushes: faceted squashed spheres near houses and fences.
	var bush_spots := [
		Vector3(-40, 0, -14.5), Vector3(-52, 0, -14.5), Vector3(-20, 0, -15),
		Vector3(0, 0, -14), Vector3(-32, 0, 14.5), Vector3(-8, 0, 15),
		Vector3(18, 0, 14.5), Vector3(-62, 0, 2), Vector3(52, 0, -8),
	]
	for p in bush_spots:
		var b := _sphere(self, _rng.randf_range(0.55, 0.85),
			p + Vector3(0, 0.35, 0), _m_bush, true)
		b.scale.y = 0.65


func _tree(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.13 * s, 0.22 * s, 1.9 * s, Vector3(0, 0.95 * s, 0), _m_bark) # tapered trunk
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.5 * s, 0)
	root.add_child(pivot)
	_sphere(pivot, 1.35 * s, Vector3(0, 0.4 * s, 0), _m_leaf, true) # faceted canopy
	_sphere(pivot, 1.00 * s, Vector3(0.9 * s, -0.1 * s, 0.4 * s), _m_leaf2, true)
	_sphere(pivot, 0.95 * s, Vector3(-0.85 * s, 0.0, -0.35 * s), _m_leaf2, true)
	_sway.append([pivot, _rng.randf() * TAU, 0.035])
	_solid(root, Vector3(0.5, 2.2, 0.5), Vector3(0, 1.1, 0))


func _build_fences() -> void:
	_fence_run(Vector3(-36, 0, -13.5), 12.0)
	_fence_run(Vector3(-16, 0, -13.5), 8.0)
	_fence_run(Vector3(4, 0, -13.5), 8.0)
	_fence_run(Vector3(-26, 0, 13.5), 12.0)
	_fence_run(Vector3(0, 0, 13.5), 10.0)


func _fence_run(center: Vector3, length: float) -> void:
	var root := Node3D.new()
	root.position = center
	add_child(root)
	var n := int(length / 2.0)
	for i in n + 1:
		var px := -length * 0.5 + i * 2.0
		_box(root, Vector3(0.14, 1.1, 0.14), Vector3(px, 0.55, 0), _m_wood)
		_box(root, Vector3(0.2, 0.08, 0.2), Vector3(px, 1.12, 0), _m_wood) # post cap
	_box(root, Vector3(length, 0.09, 0.06), Vector3(0, 0.92, 0), _m_wood) # top cap rail
	for h in [0.35, 0.68]:
		_box(root, Vector3(length, 0.09, 0.06), Vector3(0, h, 0), _m_wood)
	_solid(root, Vector3(length, 1.2, 0.35), Vector3(0, 0.6, 0))


func _build_cars() -> void:
	var colors := [
		Color(0.42, 0.22, 0.15), # rust red
		Color(0.28, 0.34, 0.40), # gray blue
		Color(0.35, 0.36, 0.24), # olive
		Color(0.52, 0.48, 0.38), # beige
		Color(0.17, 0.23, 0.33), # dark blue
	]
	_car(Vector3(-10, 0, 2.2), 0.15, colors[0], false)
	_car(Vector3(4, 0, -2.4), PI - 0.12, colors[1], false)
	_car(Vector3(20, 0, 16), PI * 0.5 + 0.08, colors[2], true) # smoking
	_car(Vector3(-42, 0, -2.2), -0.06, colors[3], false)
	_car(Vector3(46, 0, -12), 2.2, colors[4], false)


func _car(pos: Vector3, rot_y: float, color: Color, smoking: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var paint := _std(color, 0.55, 0.25)
	# Lower hull with stepped hood and trunk.
	_box(root, Vector3(4.2, 0.62, 1.9), Vector3(0, 0.63, 0), paint)
	_box(root, Vector3(1.0, 0.18, 1.7), Vector3(1.65, 0.98, 0), paint) # hood
	_box(root, Vector3(0.9, 0.16, 1.7), Vector3(-1.7, 0.96, 0), paint) # trunk
	# Cabin: lower greenhouse — glass band, thin pillars, roof panel.
	_box(root, Vector3(1.9, 0.5, 1.58), Vector3(-0.25, 1.16, 0), paint)
	_box(root, Vector3(1.92, 0.30, 1.60), Vector3(-0.25, 1.30, 0), _m_glass)
	for px in [-1.05, -0.25, 0.55]:
		_box(root, Vector3(0.08, 0.34, 1.62), Vector3(px, 1.30, 0), paint)
	_box(root, Vector3(1.9, 0.08, 1.58), Vector3(-0.25, 1.49, 0), paint) # roof
	# Raked windshield / rear glass.
	var shield := _box(root, Vector3(0.06, 0.44, 1.5), Vector3(0.74, 1.18, 0), _m_glass)
	shield.rotation.z = -0.28
	var rear := _box(root, Vector3(0.06, 0.44, 1.5), Vector3(-1.24, 1.18, 0), _m_glass)
	rear.rotation.z = 0.28
	# Wheels with hubs.
	for sx in [-1.35, 1.35]:
		for sz in [-0.85, 0.85]:
			var w := _cyl(root, 0.34, 0.34, 0.24, Vector3(sx, 0.34, sz), _m_tire)
			w.rotation.z = PI * 0.5
			var hub := _cyl(root, 0.13, 0.13, 0.26, Vector3(sx, 0.34, sz), _m_hub)
			hub.rotation.z = PI * 0.5
	# Bumpers + headlights.
	_box(root, Vector3(0.28, 0.28, 1.95), Vector3(2.12, 0.55, 0), _m_bumper)
	_box(root, Vector3(0.28, 0.28, 1.95), Vector3(-2.12, 0.55, 0), _m_bumper)
	_box(root, Vector3(0.10, 0.18, 0.34), Vector3(2.12, 0.78, 0.62), _m_headlight)
	_box(root, Vector3(0.10, 0.18, 0.34), Vector3(2.12, 0.78, -0.62), _m_headlight)
	# Small rust patches low on the hull.
	_box(root, Vector3(0.34, 0.16, 0.03), Vector3(0.9, 0.45, 0.96), _m_rust)
	_box(root, Vector3(0.28, 0.14, 0.03), Vector3(-1.4, 0.42, -0.96), _m_rust)
	_solid(root, Vector3(4.3, 1.7, 2.0), Vector3(0, 0.85, 0))
	if smoking:
		_smoke(root, Vector3(1.7, 1.4, 0))


func _smoke(parent: Node3D, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 3.2
	p.preprocess = 3.2
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 9, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 1.7
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color = Color(1, 1, 1, 0.55)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_texture = _smoke_tex
	qm.albedo_color = Color(0.16, 0.16, 0.17, 1.0)
	quad.material = qm
	p.draw_pass_1 = quad
	p.position = pos
	parent.add_child(p)


func _build_gas_station() -> void:
	var root := Node3D.new()
	root.position = Vector3(44, 0, -22)
	add_child(root)
	var canopy_mat := _std(Color(0.72, 0.71, 0.68))
	for px in [-6.0, 6.0]:
		for pz in [-4.0, 4.0]:
			_cyl(root, 0.15, 0.15, 5.0, Vector3(px, 2.5, pz), _m_pole)
			_cyl(root, 0.22, 0.28, 0.4, Vector3(px, 0.2, pz), _m_pole) # footing
	_box(root, Vector3(14, 0.5, 10), Vector3(0, 5.2, 0), canopy_mat)
	_box(root, Vector3(14.15, 0.30, 10.15), Vector3(0, 4.90, 0), _m_canopy_edge) # fascia band
	var pump_mat := _std(Color(0.60, 0.15, 0.12))
	for px in [-3.0, 3.0]:
		_box(root, Vector3(0.9, 1.5, 0.7), Vector3(px, 0.75, 0), pump_mat)
		_box(root, Vector3(0.94, 0.18, 0.74), Vector3(px, 1.58, 0), _m_trim) # pump cap
		_box(root, Vector3(0.5, 0.5, 0.1), Vector3(px, 1.1, -0.36), _m_window_dark)
		_solid(root, Vector3(1.0, 1.6, 0.8), Vector3(px, 0.8, 0))
	# Kiosk with lit windows.
	var kiosk := Vector3(9, 0, -6)
	_box(root, Vector3(6, 3, 4.5), kiosk + Vector3(0, 1.5, 0), _std(Color(0.55, 0.52, 0.46)))
	_box(root, Vector3(6.15, 0.25, 4.65), kiosk + Vector3(0, 0.12, 0), _m_foundation)
	_box(root, Vector3(4.5, 1.2, 0.1), kiosk + Vector3(0, 1.7, -2.26), _window_lit_mat)
	_box(root, Vector3(4.7, 0.12, 0.12), kiosk + Vector3(0, 2.36, -2.26), _m_trim) # window header
	_solid(root, Vector3(6.2, 3.2, 4.7), kiosk + Vector3(0, 1.6, 0))
	# Road sign.
	var sign := Node3D.new()
	sign.position = Vector3(-9, 0, 9)
	root.add_child(sign)
	_cyl(sign, 0.12, 0.12, 7.0, Vector3(0, 3.5, 0), _m_pole)
	_box(sign, Vector3(0.3, 1.6, 3.4), Vector3(0, 6.6, 0), _m_canopy_edge)
	var label := Label3D.new()
	label.text = "GAS"
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.85, 0.6)
	label.shaded = false
	label.position = Vector3(-0.2, 6.6, 0)
	label.rotation.y = -PI * 0.5
	sign.add_child(label)
	var label2 := label.duplicate() as Label3D
	label2.position = Vector3(0.2, 6.6, 0)
	label2.rotation.y = PI * 0.5
	sign.add_child(label2)


func _build_props() -> void:
	# Trash bags near curbs.
	var spots := [
		Vector3(-30, 0, 6.2), Vector3(-2, 0, -6.2), Vector3(18, 0, 6.2),
		Vector3(38, 0, -6.2), Vector3(-48, 0, -14), Vector3(6, 0, 14),
		Vector3(24, 0, -14), Vector3(-20, 0, 26),
	]
	for p in spots:
		var b := _sphere(self, 0.45, p + Vector3(0, 0.3, 0), _m_trash)
		b.scale.y = 0.7
	# Rusted barrels with band rings.
	for p in [Vector3(-44, 0, -25.5), Vector3(50, 0, 18.5), Vector3(-2, 0, 27)]:
		_cyl(self, 0.30, 0.30, 0.9, p + Vector3(0, 0.45, 0), _m_barrel)
		_cyl(self, 0.315, 0.315, 0.07, p + Vector3(0, 0.68, 0), _m_barrel_band)
		_cyl(self, 0.315, 0.315, 0.07, p + Vector3(0, 0.24, 0), _m_barrel_band)
		_solid(self, Vector3(0.65, 0.95, 0.65), p + Vector3(0, 0.48, 0))
	# Fire hydrants.
	for p in [Vector3(-24, 0, 6.0), Vector3(28, 0, -6.0)]:
		_cyl(self, 0.16, 0.18, 0.7, p + Vector3(0, 0.35, 0), _std(Color(0.55, 0.14, 0.10)))
		_cyl(self, 0.20, 0.20, 0.12, p + Vector3(0, 0.72, 0), _std(Color(0.55, 0.14, 0.10)))
		_solid(self, Vector3(0.4, 0.8, 0.4), p + Vector3(0, 0.4, 0))
	# Dumpster behind a house.
	_box(self, Vector3(2.2, 1.3, 1.2), Vector3(-46, 0.65, -27), _std(Color(0.16, 0.28, 0.18)))
	_box(self, Vector3(2.3, 0.12, 1.3), Vector3(-46, 1.35, -27), _m_trim) # lid rim
	_solid(self, Vector3(2.2, 1.3, 1.2), Vector3(-46, 0.65, -27))
	# Wooden crates near the lot corner, with edge trim.
	for i in 3:
		var cp := Vector3(56 + (i % 2) * 1.1, 0.4, 20 + i * 0.4)
		_box(self, Vector3(0.8, 0.8, 0.8), cp, _m_wood, _rng.randf() * 0.6)
		_box(self, Vector3(0.86, 0.1, 0.86), cp + Vector3(0, 0.36, 0), _m_trim, _rng.randf() * 0.6)


func _build_silhouettes() -> void:
	# Distant skyline + treeline so the horizon isn't empty. Unshaded dark
	# slabs outside the boundary; fog hazes them into the background.
	var root := Node3D.new()
	root.name = "Silhouettes"
	add_child(root)
	for i in 18:
		var a := TAU * float(i) / 18.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(88.0, 108.0)
		var bw := _rng.randf_range(8.0, 18.0)
		var bh := _rng.randf_range(9.0, 26.0)
		var p := Vector3(cos(a) * r, bh * 0.5 - 0.5, sin(a) * r)
		_box(root, Vector3(bw, bh, bw * 0.7), p, _m_silhouette, _rng.randf() * TAU)
	for i in 12:
		var a2 := TAU * float(i) / 12.0 + 0.26 + _rng.randf_range(-0.12, 0.12)
		var r2 := _rng.randf_range(82.0, 96.0)
		var th := _rng.randf_range(6.0, 11.0)
		var tp := Vector3(cos(a2) * r2, th * 0.5, sin(a2) * r2)
		_cyl(root, 0.05, 2.6, th, tp, _m_silhouette)


func _build_boundary() -> void:
	var h := MAP_HALF + 0.5
	_solid(self, Vector3(160, 6, 1), Vector3(0, 3, -h))
	_solid(self, Vector3(160, 6, 1), Vector3(0, 3, h))
	_solid(self, Vector3(1, 6, 160), Vector3(-h, 3, 0))
	_solid(self, Vector3(1, 6, 160), Vector3(h, 3, 0))
