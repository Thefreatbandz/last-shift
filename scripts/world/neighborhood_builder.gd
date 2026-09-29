class_name NeighborhoodBuilder
extends Node3D
## Procedurally builds the LAST SHIFT residential neighborhood from a WORLD
## SEED: ground, roads, houses (one boarded-up safehouse), streetlights,
## trees, fences, abandoned cars (one smoking), trash, a gas station corner,
## and invisible boundary walls. Same seed => identical neighborhood, every
## time (all layout RNG flows through one seeded RandomNumberGenerator).
## A new seed => a different street grid, different house placements, a
## different safehouse — every player's world is their own.
##
## Collision is simple StaticBody3D boxes. Shared materials keep draw state
## cheap. HD world pass visuals (trim, shutters, muntins, furnished
## interiors, detailed cars, faceted trees, skyline) are reused as-is —
## only the geography varies per seed.

const MAP_HALF := 74.0

var _rng := RandomNumberGenerator.new()
# Visual-only RNG: seeded from the world seed but independent, so purely
# cosmetic detail (road wear, broken windows, clutter) can never shift the
# shared _rng sequence that determines gameplay layouts.
var _vrng := RandomNumberGenerator.new()
var _time := 0.0
var world_seed := -1 # the seed this neighborhood was built from (-1 = unbuilt)

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

# Seeded-generation layout state (filled by build_world).
var zombie_spawns: Array[Vector3] = [] # 6 scatter points for the zombie pack
var safehouse_index := -1 # which house is the boarded safehouse
var safehouse_door_pos := Vector3.ZERO # world-space front door of the safehouse
var safehouse_porch := Vector3.ZERO # world-space porch (player start / respawn)
var player_start := Vector3.ZERO
var road_ew_z := 0.0 # EW road center line
var road_ns_x := 20.0 # NS road center line
var _road_rects: Array[Rect2] = [] # road footprints (for scatter rejection)
var _lot_rects: Array[Rect2] = [] # house lot footprints (with margins)
var _lot_specs: Array = [] # seeded house lots: {pos, face, w, d}
var _gas_rect := Rect2() # gas station footprint
var _gas_pos := Vector3.ZERO # gas station origin

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
var _m_crack: StandardMaterial3D
var _m_mailbox: StandardMaterial3D
var _m_mailbox_flag: StandardMaterial3D
var _m_ac: StandardMaterial3D
var _m_ac_dark: StandardMaterial3D
var _m_pothole: StandardMaterial3D
var _m_oil: StandardMaterial3D
var _m_leafpile: StandardMaterial3D
var _m_picture: StandardMaterial3D
var _m_curtain: StandardMaterial3D
var _m_counter: StandardMaterial3D
var _m_bed: StandardMaterial3D
var _m_bedding: StandardMaterial3D
var _m_rust_patch: StandardMaterial3D


func _ready() -> void:
	# Materials only. The bootstrap (main.gd) drives build_world(seed) once
	# the player picks a seed on the title screen — so a fresh boot shows
	# the title over an empty lot instead of a pre-built world.
	_make_materials()


## Builds (or rebuilds) the whole neighborhood from a seed. Deterministic:
## the same seed always produces the identical layout. Safe to call twice —
## any previous build is torn down first.
func build_world(seed: int) -> void:
	_clear_world()
	world_seed = seed
	_rng.seed = seed
	_vrng.seed = seed ^ 0x9E3779B9
	_layout_roads()
	_layout_gas_station()
	_layout_house_lots() # lots first: grass/debris/scatter can reject them
	_build_ground()
	_build_roads()
	_build_road_detail()
	_build_houses()
	_build_streetlights()
	_build_trees()
	_build_fences()
	_build_cars()
	_build_gas_station()
	_build_props()
	_build_silhouettes()
	_build_boundary()
	_layout_safehouse_info() # sets player_start / safehouse_porch
	_layout_zombie_spawns()


func _clear_world() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	houses.clear()
	safehouse_boards.clear()
	safehouse_door_pivot = null
	zombie_spawns.clear()
	safehouse_index = -1
	safehouse_door_pos = Vector3.ZERO
	safehouse_porch = Vector3.ZERO
	player_start = Vector3.ZERO
	_road_rects.clear()
	_lot_rects.clear()
	_lot_specs.clear()
	_sway.clear()
	_spot_lights.clear()
	_gas_pos = Vector3.ZERO


# ------------------------------------------------------- seeded layout ---

func _layout_roads() -> void:
	# The road cross moves per seed: EW z and NS x snap to a coarse grid so
	# houses always have room on both sides. Same topology every seed (one
	# EW road + one NS road) — only the position shifts.
	var slots := [-14.0, -7.0, 0.0, 7.0, 14.0]
	road_ew_z = slots[_rng.randi() % slots.size()]
	road_ns_x = slots[_rng.randi() % slots.size()]
	_road_rects = [
		Rect2(-MAP_HALF, road_ew_z - 7.0, MAP_HALF * 2.0, 14.0),
		Rect2(road_ns_x - 7.0, -MAP_HALF, 14.0, MAP_HALF * 2.0),
	]


func _layout_gas_station() -> void:
	# One quadrant of the road intersection, reserved before house lots.
	# Pushed well clear of the house bands so lots rarely compete with it.
	var qx := 1.0 if _rng.randf() < 0.5 else -1.0
	var qz := 1.0 if _rng.randf() < 0.5 else -1.0
	var gx := clampf(road_ns_x + qx * 34.0, -54.0, 54.0)
	var gz := clampf(road_ew_z + qz * 30.0, -54.0, 54.0)
	_gas_pos = Vector3(gx, 0, gz)
	_gas_rect = Rect2(gx - 11.0, gz - 9.0, 22.0, 18.0)


func _on_road(p: Vector3, margin := 0.0) -> bool:
	for r in _road_rects:
		if r.grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _point_in_lots(p: Vector3, margin := 0.0) -> bool:
	for l in _lot_rects:
		if l.grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	if _gas_rect.has_area() and _gas_rect.grow(margin).has_point(Vector2(p.x, p.z)):
		return true
	return false


func _lot_free(rect: Rect2) -> bool:
	for r in _road_rects:
		if r.grow(2.0).intersects(rect):
			return false
	for l in _lot_rects:
		if l.intersects(rect):
			return false
	if _gas_rect.has_area() and _gas_rect.grow(2.0).intersects(rect):
		return false
	return true


func _curb_spot(visual: bool = false) -> Vector3:
	# Random point just off a road edge (trash bags, hydrants).
	# visual=true routes through the cosmetic RNG so purely decorative
	# scatter never shifts the layout RNG sequence.
	var r := _vrng if visual else _rng
	if r.randf() < 0.5:
		var s := 1.0 if r.randf() < 0.5 else -1.0
		return Vector3(r.randf_range(-64, 64), 0,
			road_ew_z + s * r.randf_range(6.3, 7.3))
	var s2 := 1.0 if r.randf() < 0.5 else -1.0
	return Vector3(road_ns_x + s2 * r.randf_range(6.3, 7.3), 0,
		r.randf_range(-64, 64))


func _open_spot(margin := 1.0) -> Vector3:
	# Rejection-sampled open ground: not on roads, lots, or the gas station.
	for _i in 200:
		var p := Vector3(_rng.randf_range(-62, 62), 0, _rng.randf_range(-62, 62))
		if _on_road(p, margin) or _point_in_lots(p, margin):
			continue
		return p
	return Vector3(road_ns_x + 10.0, 0, road_ew_z + 10.0) # fallback: near intersection


func _layout_zombie_spawns() -> void:
	# Six scatter points: open ground, away from the player start and the
	# safehouse porch, spread apart.
	zombie_spawns.clear()
	var tries := 0
	while zombie_spawns.size() < 6 and tries < 400:
		tries += 1
		var p := _open_spot(2.0)
		p.y = 0.3
		if p.distance_to(player_start) < 16.0:
			continue
		if p.distance_to(safehouse_porch) < 10.0:
			continue
		var ok := true
		for s in zombie_spawns:
			if p.distance_to(s) < 8.0:
				ok = false
				break
		if not ok:
			continue
		zombie_spawns.append(p)


func _layout_safehouse_info() -> void:
	var sh := houses[safehouse_index] as Dictionary
	var pos := sh["pos"] as Vector3
	var face := float(sh["face"])
	var d := float(sh["d"])
	var w := float(sh["w"])
	safehouse_door_pos = pos + Vector3(0, 0, face * (d * 0.5))
	safehouse_porch = pos + Vector3(0, 0, face * (d * 0.5 + 3.0))
	player_start = safehouse_porch + Vector3(0, 0.3, 0)
	# Faint smoke column from the safehouse chimney: find home from afar.
	# DISABLED (2026-09-29): the particle column renders as an opaque tan
	# pillar instead of faint smoke — worse than nothing. The boarded
	# safehouse + [F] CLAIM prompt already mark it. Revisit with a proper
	# soft shader if a locator is still wanted.
	#_beacon(self, pos + Vector3(w * 0.25, 5.4, d * 0.12))


## Deterministic layout fingerprint (tests): same seed => identical string.
func layout_hash() -> String:
	var parts: Array[String] = []
	parts.append("seed:%d" % world_seed)
	parts.append("roads:%.1f,%.1f" % [road_ew_z, road_ns_x])
	parts.append("houses:%d" % houses.size())
	for h in houses:
		var hd := h as Dictionary
		var p := hd["pos"] as Vector3
		parts.append("h:%.2f,%.2f|w:%.2f|d:%.2f|f:%.1f" % [
			p.x, p.z, float(hd["w"]), float(hd["d"]), float(hd["face"])])
	parts.append("sh:%d" % safehouse_index)
	parts.append("porch:%.2f,%.2f" % [safehouse_porch.x, safehouse_porch.z])
	for s in zombie_spawns:
		parts.append("z:%.2f,%.2f" % [s.x, s.z])
	return "|".join(parts)


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
	_m_crack = _std(Color(0.75, 0.78, 0.80), 0.4) # pale shattered-glass lines
	_m_mailbox = _std(Color(0.25, 0.30, 0.38), 0.7, 0.3) # dusty blue mailbox
	_m_mailbox_flag = _std(Color(0.65, 0.16, 0.12), 0.7) # red flag
	_m_ac = _std(Color(0.55, 0.56, 0.55), 0.6, 0.4) # AC condenser
	_m_ac_dark = _std(Color(0.20, 0.20, 0.21), 0.7) # grille, lid
	_m_pothole = _std(Color(0.07, 0.07, 0.08), 1.0) # broken asphalt
	_m_oil = _std(Color(0.05, 0.05, 0.07), 0.35, 0.4) # oil stain, slight sheen
	_m_leafpile = _std(Color(0.42, 0.28, 0.12), 1.0) # dead leaves
	_m_picture = _std(Color(0.30, 0.24, 0.16), 0.8) # framed pictures
	_m_curtain = _std(Color(0.48, 0.38, 0.30), 0.95) # dusty curtains
	_m_counter = _std(Color(0.55, 0.53, 0.48), 0.7) # kitchen counter
	_m_bed = _std(Color(0.32, 0.24, 0.16), 0.85) # bed frame
	_m_bedding = _std(Color(0.50, 0.46, 0.40), 0.95) # mattress + blanket
	_m_rust_patch = _std(Color(0.36, 0.20, 0.10), 1.0) # rust patches

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
	# Reject roads, sidewalks, gas station and house footprints.
	if _on_road(p):
		return false
	if _point_in_lots(p, 2.5):
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
		var near_road := absf(absf(p.z - road_ew_z) - 7.5) < 2.5 \
			or absf(absf(p.x - road_ns_x) - 7.5) < 2.5
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
	var ez := road_ew_z
	var nx := road_ns_x
	_box(self, Vector3(140, 0.02, 8), Vector3(0, -0.01, ez), rm) # EW road
	_box(self, Vector3(8, 0.02, 140), Vector3(nx, -0.01, 0), rm) # NS road
	_box(self, Vector3(140, 0.02, 2), Vector3(0, -0.005, ez - 5), sm) # sidewalks
	_box(self, Vector3(140, 0.02, 2), Vector3(0, -0.005, ez + 5), sm)
	_box(self, Vector3(2, 0.02, 140), Vector3(nx - 6, -0.005, 0), sm)
	_box(self, Vector3(2, 0.02, 140), Vector3(nx + 6, -0.005, 0), sm)
	# Curbs: raised concrete lips along every sidewalk edge.
	for cz in [ez - 6.05, ez - 3.95, ez + 3.95, ez + 6.05]:
		_box(self, Vector3(140, 0.14, 0.18), Vector3(0, 0.05, cz), _m_curb)
	for cx in [nx - 7.05, nx - 4.95, nx + 4.95, nx + 7.05]:
		_box(self, Vector3(0.18, 0.14, 140), Vector3(cx, 0.05, 0), _m_curb)
	for x in range(-66, 67, 6):
		_box(self, Vector3(1.6, 0.012, 0.18), Vector3(x, 0.004, ez), dm)
	for z in range(-66, 67, 6):
		if absf(z - ez) > 7.0: # keep the intersection clear
			_box(self, Vector3(0.18, 0.012, 1.6), Vector3(nx, 0.004, z), dm)


func _build_road_detail() -> void:
	# Seeded wear: potholes, oil stains on the asphalt; leaf piles drifted
	# against curbs. Flat, cheap, purely visual (uses _vrng: never touches
	# the layout RNG).
	var ez := road_ew_z
	var nx := road_ns_x
	for _i in 8:
		var on_ew := _vrng.randf() < 0.6
		var px: float
		var pz: float
		if on_ew:
			px = _vrng.randf_range(-66.0, 66.0)
			pz = ez + _vrng.randf_range(-3.0, 3.0)
		else:
			px = nx + _vrng.randf_range(-3.0, 3.0)
			pz = _vrng.randf_range(-66.0, 66.0)
		if _vrng.randf() < 0.5:
			# Pothole: dark sunken disc.
			var r := _vrng.randf_range(0.35, 0.7)
			_cyl(self, r, r, 0.018, Vector3(px, 0.008, pz), _m_pothole)
		else:
			# Oil stain: flat dark quad, slight sheen.
			var s := _vrng.randf_range(0.8, 1.6)
			_box(self, Vector3(s, 0.012, s * _vrng.randf_range(0.6, 1.0)),
				Vector3(px, 0.006, pz), _m_oil, _vrng.randf() * TAU)
	for _i in 6:
		# Leaf piles against curbs and fences. Faceted: lumpy low-poly reads
		# fine and saves ~100 verts per pile.
		var lp := _curb_spot(true)
		for _k in 2:
			var r := _vrng.randf_range(0.16, 0.30)
			_sphere(self, r, lp + Vector3(_vrng.randf_range(-0.5, 0.5), r * 0.4,
				_vrng.randf_range(-0.5, 0.5)), _m_leafpile, true)


func _house(pos: Vector3, face: float, w: float, d: float, wall: Color, roof_c: Color) -> void:
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
	# Windows: framed, with sills; shutters on the front pair. About a
	# quarter are smashed — the apocalypse shows. (Uses _vrng: cosmetic.)
	var out_f := face * (d * 0.5 + t * 0.5 + 0.03)
	_window(root, Vector3(-w * 0.28, 1.7, out_f), Vector3(0, 0, face), true,
		_vrng.randf() < 0.25)
	_window(root, Vector3(w * 0.28, 1.7, out_f), Vector3(0, 0, face), true,
		_vrng.randf() < 0.25)
	_window(root, Vector3(-w * 0.5 - t * 0.5 - 0.03, 1.7, 0.0), Vector3(-1, 0, 0),
		false, _vrng.randf() < 0.25)
	_window(root, Vector3(w * 0.5 + t * 0.5 + 0.03, 1.7, 0.0), Vector3(1, 0, 0),
		false, _vrng.randf() < 0.25)
	# Porch posts flanking the door step.
	for rx in [-1.45, 1.45]:
		_box(root, Vector3(0.09, 0.85, 0.09), Vector3(rx, 0.42, fz + face * 1.15),
			_m_trim)
	# Mailbox on a post near the walk.
	var mbx := w * 0.5 + 1.6
	_box(root, Vector3(0.09, 1.05, 0.09), Vector3(mbx, 0.52, fz + face * 2.2),
		_m_wood)
	_box(root, Vector3(0.28, 0.22, 0.5), Vector3(mbx, 1.12, fz + face * 2.2),
		_m_mailbox)
	_box(root, Vector3(0.05, 0.18, 0.05), Vector3(mbx + 0.17, 1.28, fz + face * 2.2),
		_m_mailbox_flag) # red flag up
	# AC unit humming against the side wall.
	var acx := w * 0.5 + 0.45
	_box(root, Vector3(0.75, 0.65, 0.65), Vector3(acx, 0.33, 0.5), _m_ac)
	_box(root, Vector3(0.5, 0.4, 0.03), Vector3(acx - 0.38, 0.33, 0.5),
		_m_ac_dark) # fan grille
	var door := {
		"pivot": pivot, "blocker": blocker,
		"pos": pos + Vector3(0, 0, fz), "open": false, "safehouse": false,
	}
	houses.append({"pos": pos, "w": w, "d": d, "face": face, "roof": roof_g, "door": door})


## Boards up one house as the safehouse: planks across the door and front
## windows, tracked so claiming can knock them down. Called after the
## seeded lot layout picks which house it is.
func _board_house(h: Dictionary) -> void:
	var door := h["door"] as Dictionary
	var pivot := door["pivot"] as Node3D
	var root := pivot.get_parent() as Node3D
	var face := float(h["face"])
	var w := float(h["w"])
	var d := float(h["d"])
	var t := 0.3
	var fz := face * (d * 0.5)
	_boards(root, fz + face * (t * 0.5 + 0.07), w)
	safehouse_door_pivot = pivot
	door["safehouse"] = true


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
	# Coffee table with lower shelf; slab sides instead of four legs.
	var tx := w * 0.18
	var tz := back + face * 1.9
	_box(root, Vector3(1.4, 0.1, 0.8), Vector3(tx, 0.62, tz), _m_table)
	_box(root, Vector3(1.2, 0.06, 0.6), Vector3(tx, 0.22, tz), _m_shelf)
	for sx in [-0.6, 0.6]:
		_box(root, Vector3(0.09, 0.57, 0.7), Vector3(tx + sx, 0.31, tz), _m_table)
	_solid(root, Vector3(1.4, 0.65, 0.8), Vector3(tx, 0.33, tz))
	# Rug: layered flat boxes in the middle of the room.
	_box(root, Vector3(2.8, 0.035, 2.0), Vector3(0.9, 0.08, -face * 0.6), _m_rug)
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
	_cyl(root, 0.035, 0.05, 1.6, Vector3(lx, 0.80, lz), _m_pole)
	_cyl(root, 0.22, 0.30, 0.34, Vector3(lx, 1.75, lz), _window_lit_mat)
	_solid(root, Vector3(0.35, 1.9, 0.35), Vector3(lx, 0.95, lz))
	# Framed picture above the couch, on the back inner wall.
	var pic_z := -face * (d * 0.5 - 0.30)
	_box(root, Vector3(0.5, 0.62, 0.05), Vector3(cx, 2.05, pic_z), _m_picture)
	# Dusty curtains on the front windows (inside), one per window.
	var fz_in := face * (d * 0.5 - 0.30)
	for wx in [-w * 0.28, w * 0.28]:
		_box(root, Vector3(0.34, 1.5, 0.10),
			Vector3(wx + 0.95, 1.65, fz_in), _m_curtain)
	# Kitchen counter along the left wall.
	var kx := -(w * 0.5 - 0.55)
	_solid_box(root, Vector3(0.62, 0.90, 2.2), Vector3(kx, 0.45, 0.6), _m_counter)
	_box(root, Vector3(0.66, 0.06, 2.26), Vector3(kx, 0.93, 0.6), _m_trim)
	# Bed in the back-left corner: frame, mattress, pillow.
	var bedx := -(w * 0.5 - 1.35)
	var bedz := -face * (d * 0.5 - 1.75)
	_solid_box(root, Vector3(1.7, 0.32, 1.15), Vector3(bedx, 0.22, bedz), _m_bed)
	_box(root, Vector3(1.6, 0.18, 1.05), Vector3(bedx, 0.47, bedz), _m_bedding)
	_box(root, Vector3(0.45, 0.12, 0.7), Vector3(bedx - 0.5, 0.60, bedz), _m_cushion)


func _window(root: Node3D, center: Vector3, outward: Vector3, shutters: bool,
		broken := false) -> void:
	# Framed window: trim frame behind the pane, sill below, shutters beside.
	# Broken variant: shattered pane (dark + pale crack lines + a missing
	# shard showing the dark interior behind).
	# NOTE: the lit-window roll always consumes one _rng draw (even when
	# broken) so the layout RNG sequence matches the pre-HD-pass order.
	var lit := _rng.randf() < 0.55
	var mat: StandardMaterial3D
	if broken:
		mat = _m_window_dark
	elif lit:
		mat = _window_lit_mat
	else:
		mat = _m_window_dark
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
	if broken:
		# Jagged crack across the pane + one punched-out shard.
		var c1 := Vector3(0.03, 0.55, 0.02) if along_x else Vector3(0.02, 0.55, 0.03)
		var k1 := _box(root, c1, center + outward * 0.04, _m_crack)
		k1.rotation.z = 0.5
		_box(root, Vector3(0.30, 0.28, 0.02) if along_x else Vector3(0.02, 0.28, 0.30),
			center + Vector3(-0.25, 0.28, 0) + outward * 0.01, _m_inner)
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


## Seeded lot layout: random house count, positions, sizes. Lots keep clear
## of roads, the gas station and each other, and face the EW road. Runs
## before ground scatter so grass/debris reject house footprints.
func _layout_house_lots() -> void:
	var target := _rng.randi_range(7, 9)
	var tries := 0
	while _lot_specs.size() < target and tries < 400:
		tries += 1
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var hx := _rng.randf_range(-58.0, 34.0)
		if absf(hx - road_ns_x) < 11.0: # keep the intersection clear
			continue
		var hz: float = road_ew_z + side * _rng.randf_range(15.0, 23.0)
		if absf(hz) > 60.0:
			continue
		var w := _rng.randf_range(6.8, 8.6)
		var d := _rng.randf_range(6.2, 7.6)
		var rect := Rect2(hx - w * 0.5 - 3.0, hz - d * 0.5 - 3.0, w + 6.0, d + 6.0)
		if not _lot_free(rect):
			continue
		_lot_rects.append(rect)
		_lot_specs.append({"pos": Vector3(hx, 0, hz), "face": -side, "w": w, "d": d})
	# Ironclad guarantee: the map is mostly empty, so a coarse grid scan
	# always finds room to reach the target count.
	if _lot_specs.size() < target:
		var bx := -60.0
		while bx <= 48.0 and _lot_specs.size() < target:
			for side in [1.0, -1.0]:
				if _lot_specs.size() >= target:
					break
				if absf(bx - road_ns_x) < 12.0:
					continue
				var hz: float = road_ew_z + side * 19.0
				if absf(hz) > 60.0:
					continue
				var rect := Rect2(bx - 7.3, hz - 6.8, 14.6, 13.6)
				if not _lot_free(rect):
					continue
				_lot_rects.append(rect)
				_lot_specs.append({"pos": Vector3(bx, 0, hz),
					"face": -side, "w": 8.0, "d": 7.0})
			bx += 12.0
	if _lot_specs.is_empty():
		# Paranoia fallback: force one house on open ground.
		_lot_rects.append(Rect2(-37.0, road_ew_z + 13.5, 14.0, 13.0))
		_lot_specs.append({"pos": Vector3(-30, 0, road_ew_z + 20.0),
			"face": -1.0, "w": 8.0, "d": 7.0})


func _build_houses() -> void:
	# Builds every seeded lot (all enterable, furnished interiors); then one
	# random house becomes the boarded safehouse.
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
	for spec in _lot_specs:
		var s := spec as Dictionary
		_house(s["pos"], float(s["face"]), float(s["w"]), float(s["d"]),
			walls[_rng.randi() % walls.size()],
			roofs[_rng.randi() % roofs.size()])
	# The safehouse: one random house gets the boards.
	safehouse_index = _rng.randi() % houses.size()
	_board_house(houses[safehouse_index] as Dictionary)


func _build_streetlights() -> void:
	# Seeded: lamps march along both roads, alternating sides.
	var spots: Array[Vector3] = []
	var x := -60.0
	var side := 1.0
	while x < 44.0:
		spots.append(Vector3(x, 0, road_ew_z + side * 5.6))
		x += _rng.randf_range(18.0, 26.0)
		side = -side
	var z := -52.0
	var side2 := 1.0
	while z < 56.0:
		spots.append(Vector3(road_ns_x + side2 * 5.6, 0, z))
		z += _rng.randf_range(24.0, 34.0)
		side2 = -side2
	var real_light_idx := {1: true, 2: true, 3: true}
	for i in spots.size():
		var pos: Vector3 = spots[i]
		# Arm reaches toward the nearest road.
		var arm_dir := Vector3(0, 0, 1) if pos.z < road_ew_z else Vector3(0, 0, -1)
		if absf(pos.x - road_ns_x) < absf(pos.z - road_ew_z):
			arm_dir = Vector3(1, 0, 0) if pos.x < road_ns_x else Vector3(-1, 0, 0)
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
	# Seeded scatter: trees on open ground, bushes in front of houses.
	var placed := 0
	var tries := 0
	while placed < 14 and tries < 300:
		tries += 1
		var p := Vector3(_rng.randf_range(-64, 64), 0, _rng.randf_range(-64, 64))
		if _on_road(p, 3.0) or _point_in_lots(p, 3.0):
			continue
		_tree(p, _rng.randf_range(0.85, 1.25))
		placed += 1
	for h in houses:
		var hd := h as Dictionary
		var hp := hd["pos"] as Vector3
		var face := float(hd["face"])
		var w := float(hd["w"])
		var d := float(hd["d"])
		for _k in _rng.randi_range(1, 2):
			var bx := hp.x + _rng.randf_range(-w * 0.5, w * 0.5)
			var bz := hp.z + face * (d * 0.5 + _rng.randf_range(1.2, 2.2))
			var b := _sphere(self, _rng.randf_range(0.55, 0.85),
				Vector3(bx, 0.35, bz), _m_bush, true)
			b.scale.y = 0.65


func _tree(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.13 * s, 0.22 * s, 1.9 * s, Vector3(0, 0.95 * s, 0), _m_bark) # tapered trunk
	_cyl(root, 0.30 * s, 0.38 * s, 0.35 * s, Vector3(0, 0.16 * s, 0), _m_bark) # root flare
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.5 * s, 0)
	root.add_child(pivot)
	_sphere(pivot, 1.35 * s, Vector3(0, 0.4 * s, 0), _m_leaf, true) # faceted canopy
	_sphere(pivot, 1.00 * s, Vector3(0.9 * s, -0.1 * s, 0.4 * s), _m_leaf2, true)
	_sphere(pivot, 0.95 * s, Vector3(-0.85 * s, 0.0, -0.35 * s), _m_leaf2, true)
	_sphere(pivot, 0.70 * s, Vector3(0.1 * s, 1.15 * s, -0.2 * s), _m_leaf, true) # crown
	_sway.append([pivot, _rng.randf() * TAU, 0.035])
	_solid(root, Vector3(0.5, 2.2, 0.5), Vector3(0, 1.1, 0))


func _build_fences() -> void:
	# Seeded: short fence runs beside random houses, clear of the door path.
	var count := 0
	for h in houses:
		if count >= 5:
			break
		if _rng.randf() < 0.35:
			continue
		var hd := h as Dictionary
		var hp := hd["pos"] as Vector3
		var face := float(hd["face"])
		var w := float(hd["w"])
		var d := float(hd["d"])
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var fx := hp.x + side * (w * 0.5 + 4.5)
		var fz := hp.z + face * (d * 0.5 + 3.0)
		_fence_run(Vector3(fx, 0, fz), _rng.randf_range(4.0, 7.0))
		count += 1


func _fence_run(center: Vector3, length: float) -> void:
	var root := Node3D.new()
	root.position = center
	add_child(root)
	var n := int(length / 2.0)
	var lean_i := _vrng.randi_range(0, n) if n > 0 else -1 # one tired post leans
	for i in n + 1:
		var px := -length * 0.5 + i * 2.0
		var post := _box(root, Vector3(0.14, 1.1, 0.14), Vector3(px, 0.55, 0), _m_wood)
		var cap := _box(root, Vector3(0.2, 0.08, 0.2), Vector3(px, 1.12, 0), _m_wood)
		if i == lean_i:
			post.rotation.z = 0.16
			cap.position.x += 0.09
			cap.rotation.z = 0.16
	_box(root, Vector3(length, 0.09, 0.06), Vector3(0, 0.92, 0), _m_wood) # top cap rail
	for h in [0.35, 0.68]:
		_box(root, Vector3(length, 0.09, 0.06), Vector3(0, h, 0), _m_wood)
	_solid(root, Vector3(length, 1.2, 0.35), Vector3(0, 0.6, 0))


func _build_cars() -> void:
	# Seeded: 4-6 abandoned cars parked along both roads, one smoking.
	var colors := [
		Color(0.42, 0.22, 0.15), # rust red
		Color(0.28, 0.34, 0.40), # gray blue
		Color(0.35, 0.36, 0.24), # olive
		Color(0.52, 0.48, 0.38), # beige
		Color(0.17, 0.23, 0.33), # dark blue
	]
	var n := _rng.randi_range(4, 6)
	var smoking_idx := _rng.randi() % n
	var placed: Array[Vector3] = []
	for i in n:
		var col: Color = colors[_rng.randi() % colors.size()]
		var cp := Vector3.ZERO
		var rot := 0.0
		var found := false
		for _t in 40:
			if _rng.randf() < 0.6:
				var cx := _rng.randf_range(-60.0, 40.0)
				if absf(cx - road_ns_x) < 8.0: # keep the intersection clear
					continue
				var cz := road_ew_z + (2.2 if _rng.randf() < 0.5 else -2.2)
				rot = _rng.randf_range(-0.15, 0.15) + (0.0 if cz > road_ew_z else PI)
				cp = Vector3(cx, 0, cz)
			else:
				var nz := _rng.randf_range(-56.0, 56.0)
				if absf(nz - road_ew_z) < 8.0:
					continue
				var nx2 := road_ns_x + (2.2 if _rng.randf() < 0.5 else -2.2)
				rot = PI * 0.5 + _rng.randf_range(-0.1, 0.1)
				cp = Vector3(nx2, 0, nz)
			var clash := false
			for q in placed:
				if cp.distance_to(q) < 7.0:
					clash = true
					break
			if clash:
				continue
			found = true
			break
		if not found:
			continue
		placed.append(cp)
		_car(cp, rot, col, i == smoking_idx)


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
	root.position = _gas_pos # seeded quadrant of the road intersection
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
	# Seeded scatter. Trash bags + hydrants hug the curbs; barrels sit on
	# open ground; the dumpster hides behind a random house; crates stack
	# by the gas station.
	for _i in _rng.randi_range(6, 9):
		var p := _curb_spot()
		var b := _sphere(self, 0.45, p + Vector3(0, 0.3, 0), _m_trash)
		b.scale.y = 0.7
	for _i in 3:
		var p2 := _open_spot(1.0)
		_cyl(self, 0.30, 0.30, 0.9, p2 + Vector3(0, 0.45, 0), _m_barrel)
		_cyl(self, 0.315, 0.315, 0.07, p2 + Vector3(0, 0.68, 0), _m_barrel_band)
		_cyl(self, 0.315, 0.315, 0.07, p2 + Vector3(0, 0.24, 0), _m_barrel_band)
		_cyl(self, 0.29, 0.29, 0.04, p2 + Vector3(0, 0.92, 0), _m_barrel_band) # lid
		# Rust patches eating through the paint. (Cosmetic: _vrng.)
		_box(self, Vector3(0.16, 0.20, 0.02), p2 + Vector3(0.22, 0.55, 0.20),
			_m_rust_patch, _vrng.randf() * TAU)
		_box(self, Vector3(0.12, 0.14, 0.02), p2 + Vector3(-0.18, 0.30, -0.22),
			_m_rust_patch, _vrng.randf() * TAU)
		_solid(self, Vector3(0.65, 0.95, 0.65), p2 + Vector3(0, 0.48, 0))
	for _i in 2:
		var p3 := _curb_spot()
		var hm := _std(Color(0.55, 0.14, 0.10))
		_cyl(self, 0.16, 0.18, 0.7, p3 + Vector3(0, 0.35, 0), hm)
		_cyl(self, 0.20, 0.20, 0.12, p3 + Vector3(0, 0.72, 0), hm)
		_cyl(self, 0.09, 0.09, 0.10, p3 + Vector3(0, 0.80, 0), hm) # top nut
		# Side hose caps.
		_box(self, Vector3(0.10, 0.14, 0.14), p3 + Vector3(0.18, 0.48, 0),
			_m_barrel_band)
		_box(self, Vector3(0.10, 0.14, 0.14), p3 + Vector3(-0.18, 0.48, 0),
			_m_barrel_band)
		_solid(self, Vector3(0.4, 0.8, 0.4), p3 + Vector3(0, 0.4, 0))
	if not houses.is_empty():
		var hh := houses[_rng.randi() % houses.size()] as Dictionary
		var hp := hh["pos"] as Vector3
		var dp := hp + Vector3(-float(hh["w"]) * 0.5 - 2.5, 0,
			-float(hh["face"]) * (float(hh["d"]) * 0.5 + 2.0))
		_box(self, Vector3(2.2, 1.3, 1.2), dp + Vector3(0, 0.65, 0), _std(Color(0.16, 0.28, 0.18)))
		_box(self, Vector3(2.3, 0.12, 1.3), dp + Vector3(0, 1.35, 0), _m_trim)
		# Split lid + a rust streak down the side.
		_box(self, Vector3(2.14, 0.06, 1.28), dp + Vector3(0, 1.43, 0), _m_trim)
		_box(self, Vector3(0.25, 0.8, 0.02), dp + Vector3(0.4, 0.7, 0.61),
			_m_rust_patch)
		_solid(self, Vector3(2.2, 1.3, 1.2), dp + Vector3(0, 0.65, 0))
	for i in 3:
		var cp := _gas_pos + Vector3(12.0 + (i % 2) * 1.1, 0.4, 8.0 + i * 0.4)
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


## Minimap: road + gas-station footprints for the map (seeded layout data).
func get_road_rects() -> Array[Rect2]:
	return _road_rects


func get_gas_rect() -> Rect2:
	return _gas_rect
