class_name NeighborhoodBuilder
extends Node3D
## Procedurally builds the Phase 1 residential neighborhood from a fixed seed:
## ground, roads + sidewalks, houses (one boarded-up future safehouse),
## streetlights, trees, fences, abandoned cars (one smoking), trash,
## a gas station corner, and invisible boundary walls. All collision is
## simple StaticBody3D boxes. Shared materials keep draw state cheap.

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


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
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
	for x in range(-66, 67, 6):
		_box(self, Vector3(1.6, 0.012, 0.18), Vector3(x, 0.004, 0), dm)
	for z in range(-66, 67, 6):
		if absf(z) > 7.0: # keep the intersection clear
			_box(self, Vector3(0.18, 0.012, 1.6), Vector3(20, 0.004, z), dm)


func _house(pos: Vector3, face: float, w: float, d: float, wall: Color, boarded: bool) -> void:
	# QA pass: houses are enterable — four real walls (front wall has a door
	# gap), a hinged door every house gets, a simple furnished interior, and
	# a roof group that hides while the player is inside (camera would
	# otherwise clip through it).
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
	# Roof group (hidden while the player is inside).
	var roof_g := Node3D.new()
	root.add_child(roof_g)
	var roof := MeshInstance3D.new()
	roof.mesh = _prism_mesh(w * 0.5 + 0.5, 1.9, d + 1.0)
	roof.position = Vector3(0, h, 0)
	roof.material_override = _m_roof
	roof_g.add_child(roof)
	_box(roof_g, Vector3(0.6, 1.2, 0.6), Vector3(w * 0.25, h + 1.3, d * 0.12), _m_chimney)
	# Door on a hinge pivot (left edge) so it can swing open.
	var pivot := Node3D.new()
	pivot.position = Vector3(-door_w * 0.5, 0, fz)
	root.add_child(pivot)
	_box(pivot, Vector3(door_w, door_h, 0.12), Vector3(door_w * 0.5, door_h * 0.5, 0), _m_door)
	# Doorway blocker: solid while the door is closed, disabled when open.
	var blocker := _solid(root, Vector3(door_w, door_h, 0.24), Vector3(0, door_h * 0.5, fz))
	_build_interior(root, w, d, face)
	# Windows sit on the outer faces of the new walls.
	var out_f := face * (d * 0.5 + t * 0.5 + 0.03)
	_window(root, Vector3(-w * 0.28, 1.7, out_f), face, false)
	_window(root, Vector3(w * 0.28, 1.7, out_f), face, false)
	_window(root, Vector3(-w * 0.5 - t * 0.5 - 0.03, 1.7, 0.0), -1.0, true)
	_window(root, Vector3(w * 0.5 + t * 0.5 + 0.03, 1.7, 0.0), 1.0, true)
	if boarded:
		_boards(root, fz + face * (t * 0.5 + 0.07), w)
		safehouse_door_pivot = pivot
	var door := {
		"pivot": pivot, "blocker": blocker,
		"pos": pos + Vector3(0, 0, fz), "open": false, "safehouse": boarded,
	}
	houses.append({"pos": pos, "w": w, "d": d, "face": face, "roof": roof_g, "door": door})


func _build_interior(root: Node3D, w: float, d: float, face: float) -> void:
	# Cheap furnished interior: dark wood floor, couch + table + shelf.
	# Kept clear of the door swing (door at local x in [-0.7, 0.7]).
	var floor_mat := _std(Color(0.30, 0.23, 0.16))
	_box(root, Vector3(w - 0.7, 0.06, d - 0.7), Vector3(0, 0.03, 0), floor_mat)
	var couch_mat := _std(Color(0.32, 0.27, 0.23))
	var table_mat := _std(Color(0.36, 0.28, 0.18))
	var back := -face * (d * 0.5 - 1.0)
	_solid_box(root, Vector3(2.0, 0.7, 0.9), Vector3(-w * 0.22, 0.35, back), couch_mat)
	_solid_box(root, Vector3(2.0, 0.5, 0.25), Vector3(-w * 0.22, 0.95, back - face * 0.35), couch_mat)
	_solid_box(root, Vector3(1.3, 0.12, 0.9), Vector3(w * 0.20, 0.68, back + face * 1.3), table_mat)
	for sx in [-0.55, 0.55]:
		for sz in [-0.35, 0.35]:
			_box(root, Vector3(0.1, 0.62, 0.1),
				Vector3(w * 0.20 + sx, 0.31, back + face * 1.3 + sz), table_mat)
	_solid_box(root, Vector3(0.5, 2.0, 1.6), Vector3(w * 0.5 - 0.55, 1.0, 0), table_mat)


func _window(root: Node3D, pos: Vector3, face: float, side: bool) -> void:
	var mat: StandardMaterial3D = _window_lit_mat if _rng.randf() < 0.55 else _m_window_dark
	var size := Vector3(0.1, 1.2, 1.1) if side else Vector3(1.1, 1.2, 0.1)
	_box(root, size, pos, mat)


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
	var specs := [
		[Vector3(-46, 0, -20), 1.0, 8.0, 7.0, 0, false],
		[Vector3(-26, 0, -21), 1.0, 7.5, 6.5, 1, false],
		[Vector3(-6, 0, -20), 1.0, 8.5, 7.0, 2, true], # boarded: future safehouse
		[Vector3(-38, 0, 20), -1.0, 8.0, 7.0, 3, false],
		[Vector3(-14, 0, 21), -1.0, 7.0, 6.5, 4, false],
		[Vector3(12, 0, 20), -1.0, 8.0, 7.0, 5, false],
		[Vector3(-56, 0, 8), -1.0, 7.5, 6.5, 6, false],
	]
	for s in specs:
		_house(s[0], s[1], s[2], s[3], walls[int(s[4])], bool(s[5]))


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


func _tree(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.14 * s, 0.20 * s, 1.9 * s, Vector3(0, 0.95 * s, 0), _m_bark)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.5 * s, 0)
	root.add_child(pivot)
	_sphere(pivot, 1.35 * s, Vector3(0, 0.4 * s, 0), _m_leaf)
	_sphere(pivot, 1.00 * s, Vector3(0.9 * s, -0.1 * s, 0.4 * s), _m_leaf2)
	_sphere(pivot, 0.95 * s, Vector3(-0.85 * s, 0.0, -0.35 * s), _m_leaf2)
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
		_box(root, Vector3(0.14, 1.1, 0.14), Vector3(-length * 0.5 + i * 2.0, 0.55, 0), _m_wood)
	for h in [0.35, 0.85]:
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
	_box(root, Vector3(4.2, 0.8, 1.9), Vector3(0, 0.72, 0), paint)
	_box(root, Vector3(2.1, 0.62, 1.7), Vector3(-0.25, 1.32, 0), paint)
	_box(root, Vector3(2.12, 0.34, 1.72), Vector3(-0.25, 1.44, 0), _m_glass)
	for sx in [-1.35, 1.35]:
		for sz in [-0.85, 0.85]:
			var w := _cyl(root, 0.34, 0.34, 0.24, Vector3(sx, 0.34, sz), _m_tire)
			w.rotation.z = PI * 0.5
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
	var stripe_mat := _std(Color(0.62, 0.16, 0.12))
	for px in [-6.0, 6.0]:
		for pz in [-4.0, 4.0]:
			_cyl(root, 0.15, 0.15, 5.0, Vector3(px, 2.5, pz), _m_pole)
	_box(root, Vector3(14, 0.5, 10), Vector3(0, 5.2, 0), canopy_mat)
	_box(root, Vector3(14.1, 0.35, 0.4), Vector3(0, 4.95, -5.0), stripe_mat)
	_box(root, Vector3(14.1, 0.35, 0.4), Vector3(0, 4.95, 5.0), stripe_mat)
	var pump_mat := _std(Color(0.60, 0.15, 0.12))
	for px in [-3.0, 3.0]:
		_box(root, Vector3(0.9, 1.5, 0.7), Vector3(px, 0.75, 0), pump_mat)
		_box(root, Vector3(0.5, 0.5, 0.1), Vector3(px, 1.1, -0.36), _m_window_dark)
		_solid(root, Vector3(1.0, 1.6, 0.8), Vector3(px, 0.8, 0))
	# Kiosk with lit windows.
	var kiosk := Vector3(9, 0, -6)
	_box(root, Vector3(6, 3, 4.5), kiosk + Vector3(0, 1.5, 0), _std(Color(0.55, 0.52, 0.46)))
	_box(root, Vector3(4.5, 1.2, 0.1), kiosk + Vector3(0, 1.7, -2.26), _window_lit_mat)
	_solid(root, Vector3(6.2, 3.2, 4.7), kiosk + Vector3(0, 1.6, 0))
	# Road sign.
	var sign := Node3D.new()
	sign.position = Vector3(-9, 0, 9)
	root.add_child(sign)
	_cyl(sign, 0.12, 0.12, 7.0, Vector3(0, 3.5, 0), _m_pole)
	_box(sign, Vector3(0.3, 1.6, 3.4), Vector3(0, 6.6, 0), stripe_mat)
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
	# Fire hydrants.
	for p in [Vector3(-24, 0, 6.0), Vector3(28, 0, -6.0)]:
		_cyl(self, 0.16, 0.18, 0.7, p + Vector3(0, 0.35, 0), _std(Color(0.55, 0.14, 0.10)))
		_solid(self, Vector3(0.4, 0.8, 0.4), p + Vector3(0, 0.4, 0))
	# Dumpster behind a house.
	_box(self, Vector3(2.2, 1.3, 1.2), Vector3(-46, 0.65, -27), _std(Color(0.16, 0.28, 0.18)))
	_solid(self, Vector3(2.2, 1.3, 1.2), Vector3(-46, 0.65, -27))
	# Wooden crates near the warehouse-less lot corner.
	for i in 3:
		var cp := Vector3(56 + (i % 2) * 1.1, 0.4, 20 + i * 0.4)
		_box(self, Vector3(0.8, 0.8, 0.8), cp, _m_wood, _rng.randf() * 0.6)


func _build_boundary() -> void:
	var h := MAP_HALF + 0.5
	_solid(self, Vector3(160, 6, 1), Vector3(0, 3, -h))
	_solid(self, Vector3(160, 6, 1), Vector3(0, 3, h))
	_solid(self, Vector3(1, 6, 160), Vector3(-h, 3, 0))
	_solid(self, Vector3(1, 6, 160), Vector3(h, 3, 0))
