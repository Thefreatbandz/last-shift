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

const MAP_HALF := 100.0 # playable half-extent (m); world is 200x200m

var _rng := RandomNumberGenerator.new()
# Visual-only RNG: seeded from the world seed but independent, so purely
# cosmetic detail (road wear, broken windows, clutter) can never shift the
# shared _rng sequence that determines gameplay layouts.
var _vrng := RandomNumberGenerator.new()
# Loot RNG: seeded from the world seed but independent, so outdoor loot
# variety/placement never shifts the layout RNG stream either.
var _lrng := RandomNumberGenerator.new()
# Chop RNG: own stream for choppable dead trees (wood economy), so tree
# placement never shifts layout, visual, or loot RNG streams.
var _crng := RandomNumberGenerator.new()
# Detail-pass RNG: dedicated stream for the v3 dressing/trim passes (seeded
# from world_seed), so new cosmetic detail never shifts layout, visual,
# loot, or chop streams.
var _drng := RandomNumberGenerator.new()
var _time := 0.0
var world_seed := -1 # the seed this neighborhood was built from (-1 = unbuilt)
var choppable_trees: Array = [] # ChoppableTree nodes (wood economy)

# Animated / night-driven materials.
var _window_lit_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _cone_mat: StandardMaterial3D
var _spot_lights: Array[SpotLight3D] = []
var _porch_lights: Array[OmniLight3D] = [] # real porch lights (safehouse)
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

# Commercial buildings (BuildingTypes): entries are Dictionaries:
# {pos, w, d, face, roof (Node3D), door: {pivot, blocker, pos, open,
#  safehouse, locked}, kind, name}
var buildings: Array = []
var building_loot: Array = [] # dicts {pos: Vector3, items: Array}
var outdoor_loot: Array = [] # dicts {pos: Vector3, kind: String, items: Array}
const OUTDOOR_LOOT_COUNT := 18 # trash 5, corpses 4, toolbox 2, firstaid 2, duffel 2, crate 3
var brute_spawns: Array[Vector3] = [] # interior Brute spawn points
var building_zombie_spawns: Array[Vector3] = [] # interior Walker spawn points
var _building_specs: Array = [] # seeded commercial lots: {kind, pos, face, w, d, h}
var _interior_parts: Array[String] = [] # seeded interior feature tags (for hash)
var _bx_mats: Dictionary = {} # material lookup for BuildingTypes
var interior_zones: InteriorZones = null # hidden interior zones (compound-inside)

# Seeded-generation layout state (filled by build_world).
var zombie_spawns: Array[Vector3] = [] # 6 scatter points for the zombie pack
var safehouse_index := -1 # which house is the boarded safehouse
var safehouse_door_pos := Vector3.ZERO # world-space front door of the safehouse
var safehouse_porch := Vector3.ZERO # world-space porch (player start / respawn)
var player_start := Vector3.ZERO
var road_ew_z := 0.0 # EW road center line
var road_ns_x := 20.0 # NS road center line
var _road_rects: Array[Rect2] = [] # road footprints (for scatter rejection)
var _dirt_rects: Array[Rect2] = [] # dirt-road footprints: subset of _road_rects (props/tests)
var _lot_rects: Array[Rect2] = [] # house lot footprints (with margins)
var _lot_specs: Array = [] # seeded house lots: {pos, face, w, d}
var _gas_rect := Rect2() # gas station footprint
var _gas_pos := Vector3.ZERO # gas station origin

# Static shared materials.
var _m_roof: StandardMaterial3D
var _m_chimney: StandardMaterial3D
var _m_door: StandardMaterial3D
var _m_veil: StandardMaterial3D # dark doorway veil: blocks see-through from outside
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
var _m_board_dark: StandardMaterial3D
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
var _m_dash_faded: StandardMaterial3D
var _m_joint: StandardMaterial3D
var _m_asphalt_crack: StandardMaterial3D
var _m_paper: StandardMaterial3D
var _m_rubble: StandardMaterial3D
var _m_dent: StandardMaterial3D
var _m_window_hole: StandardMaterial3D
var _m_leaf_dead: StandardMaterial3D
var _m_branch: StandardMaterial3D
var _m_rock: StandardMaterial3D
var _m_pine_dark: StandardMaterial3D
var _m_trunk_dark: StandardMaterial3D
var _m_leafpile: StandardMaterial3D
var _m_picture: StandardMaterial3D
var _m_curtain: StandardMaterial3D
var _m_counter: StandardMaterial3D
var _m_bed: StandardMaterial3D
var _m_bedding: StandardMaterial3D
var _m_rust_patch: StandardMaterial3D
var _m_dumpster: StandardMaterial3D # rusted green dumpster body
var _m_newspaper: StandardMaterial3D # newspaper-vending box blue
var _m_bottle: StandardMaterial3D # bottle/can glass
var _m_sign: StandardMaterial3D # aged hanging sign board
var _m_awning: StandardMaterial3D # terracotta awning canvas
var _m_awning_stripe: StandardMaterial3D # pale awning stripe/valance
var _m_downspout: StandardMaterial3D # galvanized gutter metal
var _m_bench: StandardMaterial3D # bus-stop bench slats
var _m_brushwall: StandardMaterial3D # dense dark undergrowth: the visible map edge
var _m_grime: StandardMaterial3D # dark weather grime at wall bases
var _m_patch_dirt: StandardMaterial3D # ground variation: worn dirt patch
var _m_patch_dark: StandardMaterial3D # ground variation: dark trampled grass
var _m_patch_ash: StandardMaterial3D # ground variation: pale ash/scorch
var _m_hydrant: StandardMaterial3D # fire hydrant red
var _m_hydrant_dark: StandardMaterial3D
var _m_cone: StandardMaterial3D # traffic cone orange
var _m_cone_band: StandardMaterial3D # cone reflective band


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
	_lrng.seed = seed ^ 0xC10C41
	_crng.seed = seed ^ 0x5EED71
	_drng.seed = absi(hash([world_seed, 0xD371]))
	_layout_roads()
	_layout_gas_station()
	_layout_house_lots() # lots first: grass/debris/scatter can reject them
	_layout_building_lots() # commercial lots: same rejection guarantees
	_build_ground()
	_build_roads()
	_build_road_detail()
	_build_houses()
	_build_commercial() # before trees/props so they reject building lots
	_build_streetlights()
	_build_trees()
	_build_nature_v2() # rocks, extra bushes, curb saplings (cosmetic scatter)
	_build_fences()
	_build_cars()
	_build_gas_station()
	_build_props()
	_build_silhouettes()
	_build_treeline() # dense forest wall at the boundary: "forest beyond"
	_build_choppables() # dead trees you can chop for wood (own RNG stream)
	_build_boundary()
	_layout_safehouse_info() # sets player_start / safehouse_porch
	_layout_zombie_spawns()
	_layout_outdoor_loot() # seeded container variety, own RNG stream
	_build_props_v2() # density pass: pallets, dirt-road fences, sandbags, trash
	_build_ground_patches() # quality pass: dirt/ash/dark-grass variation
	_build_street_props() # quality pass: hydrants + traffic cones
	_build_dressing_v3() # v3 density: bus stop, dumpsters, news boxes, bottles, branches
	_build_house_trim_v2() # v3 trim: gutters, downspouts, window boxes, awnings
	_build_commercial_trim_v2() # v3 trim: blade signs, roof AC, awnings, gutters
	_build_ground_detail_v2() # v3 ground: more patches, oil, leaf piles, pavement tufts


func _clear_world() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	houses.clear()
	safehouse_boards.clear()
	safehouse_door_pivot = null
	interior_zones = null # freed with the other children above; rebuilt next
	zombie_spawns.clear()
	buildings.clear()
	building_loot.clear()
	outdoor_loot.clear()
	choppable_trees.clear()
	brute_spawns.clear()
	building_zombie_spawns.clear()
	_building_specs.clear()
	_interior_parts.clear()
	# NOTE: _bx_mats is NOT cleared here — materials are built once in _ready().
	safehouse_index = -1
	safehouse_door_pos = Vector3.ZERO
	safehouse_porch = Vector3.ZERO
	player_start = Vector3.ZERO
	_road_rects.clear()
	_dirt_rects.clear()
	_lot_rects.clear()
	_lot_specs.clear()
	_sway.clear()
	_spot_lights.clear()
	_porch_lights.clear()
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
	# --- World-density pass: two dirt roads, seeded from the cosmetic
	# stream (like the warehouse) so the anchor layout draws above never
	# shift. Dirt A runs from the main grid out to the forest edge;
	# dirt B connects the blocks behind the house bands. ~4m wide, brown
	# packed earth, no lane paint / sidewalks / curbs. The offsets are
	# chosen so neither dirt road can touch the gas-station rect
	# (gas sits at road +/-46 x, road +/-42 z with half-extents 11 x 9).
	_dirt_rects.clear()
	var dx1: float = [18.0, 24.0, 30.0][_vrng.randi() % 3]
	var sx1 := 1.0 if _vrng.randf() < 0.5 else -1.0
	var sz1 := 1.0 if _vrng.randf() < 0.5 else -1.0
	var d1x := road_ns_x + sx1 * dx1
	var d1z0 := minf(road_ew_z, sz1 * MAP_HALF)
	var d1z1 := maxf(road_ew_z, sz1 * MAP_HALF)
	_dirt_rects.append(Rect2(d1x - 2.0, d1z0, 4.0, d1z1 - d1z0))
	var dz2: float = [18.0, 24.0, 28.0][_vrng.randi() % 3]
	var sz2 := 1.0 if _vrng.randf() < 0.5 else -1.0
	var d2z := road_ew_z + sz2 * dz2
	_dirt_rects.append(Rect2(road_ns_x - 62.0, d2z - 2.0, 124.0, 4.0))
	_road_rects.append_array(_dirt_rects)


func _layout_gas_station() -> void:
	# One quadrant of the road intersection, reserved before house lots.
	# Pushed well clear of the house bands so lots rarely compete with it.
	var qx := 1.0 if _rng.randf() < 0.5 else -1.0
	var qz := 1.0 if _rng.randf() < 0.5 else -1.0
	var gx := clampf(road_ns_x + qx * 46.0, -78.0, 78.0)
	var gz := clampf(road_ew_z + qz * 42.0, -78.0, 78.0)
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
		return Vector3(r.randf_range(-92, 92), 0,
			road_ew_z + s * r.randf_range(6.3, 7.3))
	var s2 := 1.0 if r.randf() < 0.5 else -1.0
	return Vector3(road_ns_x + s2 * r.randf_range(6.3, 7.3), 0,
		r.randf_range(-92, 92))


func _open_spot(margin := 1.0) -> Vector3:
	# Rejection-sampled open ground: not on roads, lots, or the gas station.
	for _i in 200:
		var p := Vector3(_rng.randf_range(-90, 90), 0, _rng.randf_range(-90, 90))
		if _on_road(p, margin) or _point_in_lots(p, margin):
			continue
		return p
	return Vector3(road_ns_x + 10.0, 0, road_ew_z + 10.0) # fallback: near intersection


func _open_spot_visual(margin := 1.0) -> Vector3:
	# Cosmetic twin of _open_spot: rejection-samples open ground through
	# the cosmetic RNG so decorative scatter (fences) never shifts the
	# layout RNG sequence (zombie spawns, loot) or the layout hash.
	for _i in 200:
		var p := Vector3(_vrng.randf_range(-90, 90), 0, _vrng.randf_range(-90, 90))
		if _on_road(p, margin) or _point_in_lots(p, margin):
			continue
		return p
	return Vector3(road_ns_x + 10.0, 0, road_ew_z + 10.0)


func _layout_zombie_spawns() -> void:
	# Ten scatter points on the expanded map (same density as the old six):
	# open ground, away from the player start and the safehouse porch,
	# spread apart. 32m from the player start keeps day-1 zombies offscreen
	# (field report: "random spawning zombies" popping into view).
	zombie_spawns.clear()
	var tries := 0
	while zombie_spawns.size() < 10 and tries < 600:
		tries += 1
		var p := _open_spot(2.0)
		p.y = 0.3
		if p.distance_to(player_start) < 32.0:
			continue
		if p.distance_to(safehouse_porch) < 12.0:
			continue
		var ok := true
		for s in zombie_spawns:
			if p.distance_to(s) < 8.0:
				ok = false
				break
		if not ok:
			continue
		zombie_spawns.append(p)


## Seeded outdoor loot variety (Phase 2): distinct container types placed
## "in the right places" — corpses near building entrances and the road
## cross where the fighting happened, trash scattered on open ground,
## toolboxes at the warehouse/gas station, first-aid near houses, duffels
## dropped by roadsides, crates behind commercial buildings. Always
## produces exactly OUTDOOR_LOOT_COUNT spots (fallbacks included).
func _layout_outdoor_loot() -> void:
	outdoor_loot.clear()
	var plan := [
		["trash", 5], ["corpse", 2], ["fresh_corpse", 2], ["toolbox", 2],
		["firstaid", 2], ["duffel", 2], ["crate", 3],
	]
	for entry in plan:
		var kind := String(entry[0])
		for _i in int(entry[1]):
			var p := _loot_spot_for(kind)
			outdoor_loot.append({"pos": p, "kind": kind,
				"items": _loot_table(kind)})


func _loot_open_spot(margin := 1.0) -> Vector3:
	# Rejection-sampled open ground through the loot RNG (never touches
	# the layout stream).
	for _i in 200:
		var p := Vector3(_lrng.randf_range(-90, 90), 0,
			_lrng.randf_range(-90, 90))
		if _on_road(p, margin) or _point_in_lots(p, margin):
			continue
		if p.distance_to(player_start) < 6.0:
			continue
		return p
	return Vector3(road_ns_x + 12.0, 0, road_ew_z + 12.0) # near the cross


func _loot_spot_for(kind: String) -> Vector3:
	match kind:
		"corpse", "fresh_corpse":
			# Where the fighting happened: building entrances, or the road
			# intersection. Uses _building_specs (layout-phase data).
			if not _building_specs.is_empty() and _lrng.randf() < 0.7:
				var spec := _building_specs[_lrng.randi() % _building_specs.size()] as Dictionary
				var bp := spec["pos"] as Vector3
				var face := float(spec["face"])
				var d := float(spec["d"])
				var p := bp + Vector3(_lrng.randf_range(-3.0, 3.0), 0,
					face * (d * 0.5 + _lrng.randf_range(1.5, 3.5)))
				if not _on_road(p, 0.5) and not _point_in_lots(p, 0.5):
					return p
			# Fallback: near the road cross.
			for _i in 60:
				var p2 := Vector3(
					road_ns_x + _lrng.randf_range(-14.0, 14.0), 0,
					road_ew_z + _lrng.randf_range(-14.0, 14.0))
				if _on_road(p2, 2.5) or _point_in_lots(p2, 0.5):
					continue
				return p2
			return _loot_open_spot()
		"toolbox":
			# Warehouses and the gas station: tools live where work happened.
			for spec in _building_specs:
				var sd := spec as Dictionary
				if String(sd["kind"]) == "warehouse":
					var wp := sd["pos"] as Vector3
					var p := wp + Vector3(_lrng.randf_range(-4.0, 4.0), 0,
						float(sd["face"]) * (float(sd["d"]) * 0.5 + 2.0))
					if not _on_road(p, 0.5) and not _point_in_lots(p, 0.5):
						return p
			if _gas_rect.has_area():
				var gp := Vector3(_gas_pos.x + _lrng.randf_range(-6.0, 6.0), 0,
					_gas_pos.z + _lrng.randf_range(-4.0, 4.0))
				if not _on_road(gp, 0.5) and not _point_in_lots(gp, 0.5):
					return gp
			return _loot_open_spot()
		"firstaid":
			# Front yards: medicine cabinets raided, kits dropped outside.
			if not _lot_specs.is_empty():
				var spec := _lot_specs[_lrng.randi() % _lot_specs.size()] as Dictionary
				var hp := spec["pos"] as Vector3
				var face := float(spec["face"])
				var p := hp + Vector3(_lrng.randf_range(-3.0, 3.0), 0,
					face * (float(spec["d"]) * 0.5 + _lrng.randf_range(2.0, 4.0)))
				if not _on_road(p, 0.5) and not _point_in_lots(p, 0.5):
					return p
			return _loot_open_spot()
		"duffel":
			# Dropped by the roadside: someone ran and didn't make it.
			for _i in 60:
				var p := _curb_spot_loot()
				if _on_road(p, 1.0) or _point_in_lots(p, 0.5):
					continue
				return p
			return _loot_open_spot()
		_: # "trash", "crate": scattered open ground
			return _loot_open_spot()


func _curb_spot_loot() -> Vector3:
	# Loot-RNG twin of _curb_spot: just off a road edge.
	if _lrng.randf() < 0.5:
		var s := 1.0 if _lrng.randf() < 0.5 else -1.0
		return Vector3(_lrng.randf_range(-90, 90), 0,
			road_ew_z + s * _lrng.randf_range(8.0, 10.0))
	var s2 := 1.0 if _lrng.randf() < 0.5 else -1.0
	return Vector3(road_ns_x + s2 * _lrng.randf_range(8.0, 10.0), 0,
		_lrng.randf_range(-90, 90))


## Fitting loot tables per container kind. No new item types (parked) —
## just sensible mixes of the existing economy.
func _loot_table(kind: String) -> Array:
	match kind:
		"trash":
			var t: Array = [["scrap", _lrng.randi_range(1, 2)]]
			if _lrng.randf() < 0.4:
				t.append(["cloth", 1])
			if _lrng.randf() < 0.25:
				t.append(["canned_food", 1])
			if _lrng.randf() < 0.20:
				t.append(["water", 1])
			if _lrng.randf() < 0.25:
				t.append(["wood", _lrng.randi_range(1, 2)]) # wave loop: barricades
			return t
		"corpse":
			var t: Array = [["cloth", _lrng.randi_range(1, 2)]]
			if _lrng.randf() < 0.5:
				t.append(["scrap", 1])
			if _lrng.randf() < 0.3:
				t.append(["bandage", 1])
			if _lrng.randf() < 0.15:
				t.append(["painkillers", 1])
			return t
		"fresh_corpse":
			var t: Array = [["bandage", 1]]
			if _lrng.randf() < 0.45:
				t.append(["medkit", 1])
			if _lrng.randf() < 0.35:
				t.append(["canned_food", 1])
			if _lrng.randf() < 0.3:
				t.append(["water", 1])
			if _lrng.randf() < 0.20:
				t.append(["health_kit", 1])
			return t
		"toolbox":
			var t: Array = [["scrap", _lrng.randi_range(2, 3)]]
			if _lrng.randf() < 0.4:
				t.append(["cloth", 1])
			if _lrng.randf() < 0.30:
				t.append(["wood", 2])
			if _lrng.randf() < 0.10:
				t.append(["fire_axe", 1]) # rare: a real tool
			return t
		"firstaid":
			var t: Array = [["bandage", _lrng.randi_range(1, 2)]]
			if _lrng.randf() < 0.5:
				t.append(["medkit", 1])
			if _lrng.randf() < 0.25:
				t.append(["painkillers", 1])
			if _lrng.randf() < 0.15:
				t.append(["health_kit", 1])
			return t
		"duffel":
			var t: Array = [["canned_food", 1], ["water", 1]]
			if _lrng.randf() < 0.5:
				t.append(["cloth", 1])
			if _lrng.randf() < 0.15:
				t.append(["ammo_9mm", _lrng.randi_range(4, 8)])
			if _lrng.randf() < 0.08:
				t.append(["shells", _lrng.randi_range(2, 4)])
			if _lrng.randf() < 0.06:
				t.append(["pistol", 1]) # rare street gun
			return t
		_: # "crate"
			var t: Array = [["scrap", 2], ["cloth", 1]]
			if _lrng.randf() < 0.5:
				t.append(["wood", _lrng.randi_range(2, 3)])
			if _lrng.randf() < 0.12:
				t.append(["machete", 1]) # rare: packed blade
			return t


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
	parts.append("bld:%d" % buildings.size())
	for b in buildings:
		var bd := b as Dictionary
		var bp := bd["pos"] as Vector3
		parts.append("b:%s:%.2f,%.2f|f:%.1f" % [
			String(bd["kind"]), bp.x, bp.z, float(bd["face"])])
	parts.append("dirt:%d" % _dirt_rects.size())
	for dr in _dirt_rects:
		parts.append("dr:%.2f,%.2f|%.1fx%.1f" % [
			dr.position.x, dr.position.y, dr.size.x, dr.size.y])
	for ip in _interior_parts:
		parts.append("in:" + ip)
	return "|".join(parts)


## Hash of just the seeded interior variation (building kinds, room/prop
## layouts, container and zombie spawn tags). Same seed => same hash;
## different seeds => different interiors.
func interior_hash() -> String:
	var parts: Array[String] = []
	for b in buildings:
		parts.append(String((b as Dictionary)["kind"]))
	parts.append("---")
	for ip in _interior_parts:
		parts.append(ip)
	return str("|".join(parts).hash())


# ------------------------------------------------- commercial buildings ---

## Seeded commercial-lot placement. Runs right after _layout_house_lots so
## grass, debris and scatter reject building lots exactly like house lots.
func _layout_building_lots() -> void:
	var bt := BuildingTypes.new()
	_building_specs = bt.layout_lots(self, BuildingTypes.pick_kinds(_rng))
	# World-density pass: 4 extra commercial lots in empty areas, reusing
	# existing kinds. Placed from the cosmetic stream (like the warehouse)
	# so the anchor layout draws never shift; they flow through the normal
	# _build_commercial() path, so loot, zombie spawns and door wiring all
	# work exactly like the anchors.
	for kind in _pick_extra_kinds():
		var spec := _place_extra_lot(String(kind))
		if not spec.is_empty():
			_building_specs.append(spec)


## Expansion kinds: generic non-zoned kinds only (corner store, grocery).
## Zoned kinds are deliberately excluded — InteriorZones keys exterior
## roots by kind name ("bld_<kind>"), so a duplicate zoned kind would wire
## its teleport trigger to the wrong building.
func _pick_extra_kinds() -> Array:
	var pool: Array = [BuildingTypes.CORNER, BuildingTypes.GROCERY]
	var kinds: Array = []
	while kinds.size() < 4:
		kinds.append(pool[_vrng.randi() % pool.size()])
	return kinds


## Expansion-lot placement: mirrors BuildingTypes._place_lot, but draws
## from the cosmetic stream (like the warehouse) so the anchor layout RNG
## sequence never shifts. Lots reject roads (dirt included), house lots,
## the gas station and each other, and face the EW main road.
func _place_extra_lot(kind: String) -> Dictionary:
	var dim: Vector3 = BuildingTypes.DIMS[kind]
	for _attempt in 160:
		var x := _vrng.randf_range(-86.0, 86.0)
		var z := _vrng.randf_range(-86.0, 86.0)
		var p := Vector3(x, 0, z)
		var m := maxf(dim.x, dim.z) * 0.5 + 3.0
		if _on_road(p, m + 4.0):
			continue
		var rect := Rect2(x - dim.x * 0.5 - 2.0, z - dim.z * 0.5 - 2.0,
			dim.x + 4.0, dim.z + 4.0)
		if not _lot_free(rect):
			continue
		if _point_in_lots(p, m + 2.0):
			continue
		_lot_rects.append(rect)
		# Face the east-west main road (all building doors sit on local +/-Z).
		var face := -signf(p.z - road_ew_z)
		if face == 0.0:
			face = 1.0
		return {"kind": kind, "pos": p, "face": face,
			"w": dim.x, "d": dim.z, "h": dim.y}
	return {}


## Builds the commercial buildings (after houses, before trees/props).
func _build_commercial() -> void:
	var bt := BuildingTypes.new()
	bt.build(self, _building_specs)
	# Hidden interior zones for the zoned kinds (police, hospital,
	# warehouse, office_tall): built LAST in the world-gen order so their
	# seeded draws never shift the map layout. Zone loot / brute / walker
	# spawns flow through the normal channels (bx_add_loot, bx_brute,
	# bx_zombie) so counts and container ids keep their meaning.
	if interior_zones == null:
		interior_zones = InteriorZones.new()
		interior_zones.name = "InteriorZones"
		add_child(interior_zones)
	interior_zones.build(self)


# --------------------------------- public build API for BuildingTypes ----
# All commercial-building geometry flows through these so the seeded world
# (and its hash) stays deterministic. RNG: bx_rng() = layout RNG,
# bx_vrng() = cosmetic RNG.

func bx_rng() -> RandomNumberGenerator:
	return _rng


func bx_vrng() -> RandomNumberGenerator:
	return _vrng


func bx_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_y := 0.0) -> MeshInstance3D:
	return _box(parent, size, pos, mat, rot_y)


func bx_solid_box(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material) -> StaticBody3D:
	return _solid_box(parent, size, pos, mat)


func bx_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	return _cyl(parent, r_top, r_bot, h, pos, mat)


func bx_sphere(parent: Node3D, r: float, pos: Vector3, mat: Material,
		facets := false) -> MeshInstance3D:
	return _sphere(parent, r, pos, mat, facets)


func bx_solid(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	return _solid(parent, size, pos)


func bx_window(root: Node3D, center: Vector3, outward: Vector3,
		shutters: bool, broken := false) -> void:
	_window(root, center, outward, shutters, broken)


func bx_std(c: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	return _std(c, rough, metallic)


func bx_mat(key: String) -> Material:
	return _bx_mats.get(key)


func bx_lot_free(rect: Rect2) -> bool:
	return _lot_free(rect)


func bx_on_road(p: Vector3, margin := 0.0) -> bool:
	return _on_road(p, margin)


func bx_point_in_lots(p: Vector3, margin := 0.0) -> bool:
	return _point_in_lots(p, margin)


func bx_add_lot(rect: Rect2) -> void:
	_lot_rects.append(rect)


func bx_register(entry: Dictionary) -> void:
	buildings.append(entry)


func bx_add_loot(pos: Vector3, items: Array, kind := "crate",
		exempt_guns := false) -> void:
	building_loot.append({"pos": pos, "items": items, "kind": kind,
		"exempt_guns": exempt_guns})


func bx_brute(pos: Vector3) -> void:
	brute_spawns.append(pos)


func bx_zombie(pos: Vector3) -> void:
	building_zombie_spawns.append(pos)


func bx_track_interior(tag: String) -> void:
	_interior_parts.append(tag)


func _process(delta: float) -> void:
	_time += delta
	for s in _sway:
		var n := s[0] as Node3D
		var phase := float(s[1])
		var amp := float(s[2])
		n.rotation.z = sin(_time * 1.3 + phase) * amp
		n.rotation.x = cos(_time * 0.9 + phase) * amp * 0.6


func set_night_factor(f: float) -> void:
	_window_lit_mat.emission_energy_multiplier = lerpf(0.15, 3.2, f)
	_lamp_mat.emission_energy_multiplier = lerpf(0.4, 5.0, f)
	var c := _cone_mat.albedo_color
	c.a = lerpf(0.03, 0.28, f)
	_cone_mat.albedo_color = c
	for sp in _spot_lights:
		sp.light_energy = lerpf(0.0, 4.5, f)
	for pl in _porch_lights:
		pl.light_energy = lerpf(0.0, 3.2, f)


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
	_m_veil = _std(Color(0.012, 0.012, 0.016))
	_m_veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_m_veil.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	_m_board_dark = _std(Color(0.20, 0.15, 0.10)) # plank seams / shadow gaps
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
	_m_dash_faded = _std(Color(0.45, 0.40, 0.22), 0.95) # worn lane paint
	_m_joint = _std(Color(0.09, 0.09, 0.10), 1.0) # sidewalk seams
	_m_asphalt_crack = _std(Color(0.06, 0.06, 0.07), 1.0) # asphalt cracks
	_m_paper = _std(Color(0.62, 0.60, 0.55), 1.0) # scattered papers
	_m_rubble = _std(Color(0.23, 0.22, 0.20), 1.0) # concrete rubble chunks
	_m_leaf_dead = _std(Color(0.45, 0.42, 0.20), 0.95) # sickly yellow-green canopy
	_m_branch = _std(Color(0.32, 0.28, 0.24), 1.0) # dead gray-brown wood
	_m_rock = _std(Color(0.38, 0.37, 0.35), 0.98) # granite rocks
	_m_pine_dark = _std(Color(0.09, 0.13, 0.08), 1.0) # treeline canopy, near-black
	_m_trunk_dark = _std(Color(0.16, 0.12, 0.09), 1.0) # treeline trunks
	_m_leafpile = _std(Color(0.42, 0.28, 0.12), 1.0) # dead leaves
	_m_picture = _std(Color(0.30, 0.24, 0.16), 0.8) # framed pictures
	_m_curtain = _std(Color(0.48, 0.38, 0.30), 0.95) # dusty curtains
	_m_counter = _std(Color(0.55, 0.53, 0.48), 0.7) # kitchen counter
	_m_bed = _std(Color(0.32, 0.24, 0.16), 0.85) # bed frame
	_m_bedding = _std(Color(0.50, 0.46, 0.40), 0.95) # mattress + blanket
	_m_rust_patch = _std(Color(0.36, 0.20, 0.10), 1.0) # rust patches
	_m_brushwall = _std(Color(0.10, 0.14, 0.08), 1.0) # dense dark undergrowth: the visible map edge
	_m_grime = _std(Color(0.070, 0.063, 0.055), 1.0) # V2: heavy grime at wall bases
	# Quality pass: ground variation patches (cheap flat quads, shared mats).
	_m_patch_dirt = _std(Color(0.30, 0.24, 0.15), 1.0) # worn dirt
	_m_patch_dark = _std(Color(0.13, 0.17, 0.09), 1.0) # trampled dark grass
	_m_patch_ash = _std(Color(0.42, 0.40, 0.36), 1.0) # pale ash / scorch
	_m_hydrant = _std(Color(0.62, 0.14, 0.10), 0.6)
	_m_hydrant_dark = _std(Color(0.30, 0.08, 0.06), 0.7)
	_m_cone = _std(Color(0.75, 0.32, 0.08), 0.8)
	_m_cone_band = _std(Color(0.80, 0.80, 0.78), 0.5)
	# V3 dressing/trim materials (quality pass part 2).
	_m_dumpster = _std(Color(0.16, 0.30, 0.18), 0.7, 0.2)
	_m_newspaper = _std(Color(0.14, 0.20, 0.34), 0.7, 0.2)
	_m_bottle = _std(Color(0.12, 0.30, 0.16), 0.25, 0.6)
	_m_sign = _std(Color(0.52, 0.42, 0.26), 0.8)
	_m_awning = _std(Color(0.48, 0.28, 0.16), 0.9)
	_m_awning_stripe = _std(Color(0.74, 0.66, 0.52), 0.9)
	_m_downspout = _std(Color(0.55, 0.55, 0.57), 0.55, 0.5)
	_m_bench = _std(Color(0.36, 0.26, 0.16), 0.85)

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
	_window_lit_mat.emission_energy_multiplier = 0.6 # V2: warm windows glow at night

	_m_window_hole = StandardMaterial3D.new()
	_m_window_hole.albedo_color = Color(0.008, 0.008, 0.010)
	_m_window_hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # smashed = black hole

	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.9, 0.85, 0.75)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.80, 0.50)
	_lamp_mat.emission_energy_multiplier = 0.8 # V2: brighter bulbs

	_cone_mat = StandardMaterial3D.new()
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.albedo_color = Color(1.0, 0.80, 0.50, 0.06) # V2: visible light pools

	_smoke_tex = _radial_texture(64)

	# Material lookup for commercial buildings (BuildingTypes bx_mat()).
	_bx_mats = {
		"trim": _m_trim, "foundation": _m_foundation, "step": _m_step,
		"floor": _m_floor, "inner": _m_inner, "door": _m_door,
		"veil": _m_veil,
		"door_panel": _m_door_panel, "window_dark": _m_window_dark,
		"glass": _m_glass, "pole": _m_pole, "wood": _m_wood,
		"counter": _m_counter, "shelf": _m_shelf, "table": _m_table,
		"couch": _m_couch, "barrel": _m_barrel, "trash": _m_trash,
		"curb": _m_curb, "crack": _m_crack, "mailbox": _m_mailbox,
		"curtain": _m_curtain, "picture": _m_picture, "bed": _m_bed,
		"bedding": _m_bedding, "grime": _m_grime, "rust_patch": _m_rust_patch,
	}


# ------------------------------------------------------------------ helpers ---

## Tag a node as interior furniture. The interior_furniture_qa suite collects
## every node with this meta under a house/building root and asserts its
## world AABB stays inside that building's footprint.
func _furn(n: Node) -> Node:
	n.set_meta("furniture", true)
	return n


## Public wrapper so BuildingTypes can tag its furniture without a cast.
func bx_furn(n: Node) -> Node:
	return _furn(n)


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


func _noise_texture(base: Color, variation: float, cells: int, px: int,
		r: RandomNumberGenerator = null) -> ImageTexture:
	# r=null keeps the legacy behavior (layout stream); pass _vrng for
	# cosmetic-only textures so the layout RNG sequence never shifts.
	var rr := _rng if r == null else r
	var grid := PackedFloat32Array()
	grid.resize(cells * cells)
	for i in grid.size():
		grid[i] = rr.randf()
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
			var grain := 0.92 + 0.16 * rr.randf()
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
	while xf.size() < 320 and tries < 1800:
		tries += 1
		var p := Vector3(_rng.randf_range(-96, 96), 0.19, _rng.randf_range(-96, 96))
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
	while xf.size() < 130 and tries < 900:
		tries += 1
		var p := Vector3(_rng.randf_range(-94, 94), 0.012, _rng.randf_range(-94, 94))
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
		if _vrng.randf() < 0.28:
			continue # worn-away lane paint: the dashes break up
		var dw := 1.6 * _vrng.randf_range(0.55, 1.0) # some dashes half-gone
		_box(self, Vector3(dw, 0.012, 0.18), Vector3(x, 0.004, ez),
			_m_dash_faded if _vrng.randf() < 0.35 else dm)
	for z in range(-66, 67, 6):
		if absf(z - ez) > 7.0: # keep the intersection clear
			if _vrng.randf() < 0.28:
				continue
			var dw2 := 1.6 * _vrng.randf_range(0.55, 1.0)
			_box(self, Vector3(0.18, 0.012, dw2), Vector3(nx, 0.004, z),
				_m_dash_faded if _vrng.randf() < 0.35 else dm)
	# Sidewalk expansion joints: thin dark seams every ~6m, one draw call.
	_build_sidewalk_joints(ez, nx)
	# Manhole covers, storm drains, faded crosswalks.
	_build_street_details(ez, nx)
	# Dirt roads: brown packed-earth strips with wheel ruts.
	_build_dirt_roads()


## Dirt roads: brown packed-earth strips with wheel ruts — no lane paint,
## no sidewalks, no curbs. Tagged with the "dirt_road" meta for QA.
func _build_dirt_roads() -> void:
	if _dirt_rects.is_empty():
		return
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _noise_texture(Color(0.30, 0.225, 0.14), 0.55, 8, 128, _vrng)
	dm.uv1_scale = Vector3(10, 10, 10)
	dm.roughness = 1.0
	var rut_mat := _std(Color(0.20, 0.15, 0.10), 1.0) # packed wheel ruts
	for dr in _dirt_rects:
		var c := dr.get_center()
		var strip := _box(self, Vector3(dr.size.x, 0.02, dr.size.y),
			Vector3(c.x, -0.008, c.y), dm)
		strip.set_meta("dirt_road", true)
		# Two darker packed ruts where tires wore the earth down.
		var along_x := dr.size.x > dr.size.y
		for s in [-0.9, 0.9]:
			var rut: MeshInstance3D
			if along_x:
				rut = _box(self, Vector3(dr.size.x, 0.012, 0.5),
					Vector3(c.x, 0.004, c.y + s), rut_mat)
			else:
				rut = _box(self, Vector3(0.5, 0.012, dr.size.y),
					Vector3(c.x + s, 0.004, c.y), rut_mat)
			rut.set_meta("dirt_road", true)


## Manhole covers, storm drains and worn crosswalks. (Cosmetic: _vrng only.)
func _build_street_details(ez: float, nx: float) -> void:
	var drain_mat := _std(Color(0.10, 0.10, 0.11), 0.7, 0.4)
	var walk_mat := _std(Color(0.55, 0.55, 0.52), 0.95) # worn crosswalk paint
	# Manhole covers: dark iron discs wandering down both roads.
	for _i in 7:
		_cyl(self, 0.45, 0.45, 0.025,
			Vector3(_vrng.randf_range(-62.0, 62.0), 0.005, ez + _vrng.randf_range(-2.4, 2.4)),
			drain_mat)
	for _i in 7:
		_cyl(self, 0.45, 0.45, 0.025,
			Vector3(nx + _vrng.randf_range(-2.4, 2.4), 0.005, _vrng.randf_range(-62.0, 62.0)),
			drain_mat)
	# Storm drains: grate boxes tucked against the curbs.
	for _i in 10:
		var on_ew := _vrng.randf() < 0.5
		var side := 1.0 if _vrng.randf() < 0.5 else -1.0
		if on_ew:
			var dx := Vector3(_vrng.randf_range(-62.0, 62.0), 0.02, ez + side * 3.7)
			_box(self, Vector3(0.9, 0.05, 0.5), dx, drain_mat)
		else:
			var dz := Vector3(nx + side * 4.7, 0.02, _vrng.randf_range(-62.0, 62.0))
			_box(self, Vector3(0.5, 0.05, 0.9), dz, drain_mat)
	# Faded crosswalks: worn white bars across the EW road, clear of the
	# intersection and the dashes.
	for cx in [-14.0, 22.0]:
		for bi in 6:
			var worn := _vrng.randf() < 0.45
			if worn:
				continue
			_box(self, Vector3(0.55, 0.012, 6.4),
				Vector3(cx + bi * 1.1 - 2.75, 0.004, ez), walk_mat)


## Sidewalk expansion joints + asphalt cracks + repair patches, all in one
## MultiMesh draw call. Seeded wear that makes the roads read as roads.
## (Cosmetic: _vrng only.)
func _build_sidewalk_joints(ez: float, nx: float) -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _m_joint
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	# Sidewalk seams across both walks.
	for x in range(-96, 97, 6):
		for sz in [ez - 5.0, ez + 5.0]:
			xf.append(Transform3D(
				Basis(Vector3.UP, 0.0).scaled(Vector3(0.09, 1, 2.0)),
				Vector3(x + _vrng.randf_range(-0.4, 0.4), 0.008, sz)))
			cols.append(Color(1, 1, 1))
	for z in range(-96, 97, 6):
		if absf(z - ez) < 8.0:
			continue
		for sx in [nx - 6.0, nx + 6.0]:
			xf.append(Transform3D(
				Basis(Vector3.UP, 0.0).scaled(Vector3(2.0, 1, 0.09)),
				Vector3(sx, 0.008, z + _vrng.randf_range(-0.4, 0.4))))
			cols.append(Color(1, 1, 1))
	# Asphalt cracks: jagged dark slashes wandering across the lanes.
	for _i in 48:
		var on_ew := _vrng.randf() < 0.6
		var px := _vrng.randf_range(-92.0, 92.0) if on_ew else nx + _vrng.randf_range(-3.2, 3.2)
		var pz := ez + _vrng.randf_range(-3.2, 3.2) if on_ew else _vrng.randf_range(-92.0, 92.0)
		var segs := _vrng.randi_range(2, 4)
		var dir := _vrng.randf() * TAU
		for _s in segs:
			var ln := _vrng.randf_range(0.8, 2.2)
			xf.append(Transform3D(
				Basis(Vector3.UP, dir + _vrng.randf_range(-0.5, 0.5)).scaled(
					Vector3(0.10, 1, ln)),
				Vector3(px, 0.006, pz)))
			cols.append(Color(0.55, 0.55, 0.58)) # darker: asphalt crack tint
			px += cos(dir) * ln * 0.8
			pz += sin(dir) * ln * 0.8
			dir += _vrng.randf_range(-0.7, 0.7)
	# Tar repair patches: big dark rectangles over the worst of it.
	for _i in 18:
		var on_ew2 := _vrng.randf() < 0.6
		var qx := _vrng.randf_range(-92.0, 92.0) if on_ew2 else nx + _vrng.randf_range(-3.0, 3.0)
		var qz := ez + _vrng.randf_range(-3.0, 3.0) if on_ew2 else _vrng.randf_range(-92.0, 92.0)
		xf.append(Transform3D(
			Basis(Vector3.UP, _vrng.randf() * TAU).scaled(
				Vector3(_vrng.randf_range(1.2, 2.6), 1, _vrng.randf_range(0.9, 1.8))),
			Vector3(qx, 0.005, qz)))
		cols.append(Color(0.75, 0.75, 0.78))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_road_detail() -> void:
	# Seeded wear: potholes, oil stains on the asphalt; leaf piles drifted
	# against curbs. Flat, cheap, purely visual (uses _vrng: never touches
	# the layout RNG). V2: more of everything — the roads should look
	# chewed up.
	var ez := road_ew_z
	var nx := road_ns_x
	for _i in 28:
		var on_ew := _vrng.randf() < 0.6
		var px: float
		var pz: float
		if on_ew:
			px = _vrng.randf_range(-94.0, 94.0)
			pz = ez + _vrng.randf_range(-3.0, 3.0)
		else:
			px = nx + _vrng.randf_range(-3.0, 3.0)
			pz = _vrng.randf_range(-94.0, 94.0)
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
	_build_dressing_v2()


## V2 set dressing: scattered papers, curb grass, rubble chunks. Three
## MultiMesh draw calls total. (Cosmetic: _vrng + _open_spot_visual only.)
func _build_dressing_v2() -> void:
	# Scattered papers: pale quads tumbling near curbs.
	var paper := PlaneMesh.new()
	paper.size = Vector2(0.32, 0.42)
	paper.material = _m_paper
	var pxf: Array[Transform3D] = []
	var ptries := 0
	while pxf.size() < 70 and ptries < 500:
		ptries += 1
		var p := _curb_spot(true)
		pxf.append(Transform3D(
			Basis(Vector3.UP, _vrng.randf() * TAU).scaled(
				Vector3(_vrng.randf_range(0.7, 1.3), 1, _vrng.randf_range(0.7, 1.3))),
			p + Vector3(0, 0.015, 0)))
	_paper_mm(paper, pxf)
	# Curb grass: dead-yellow tufts forcing through the concrete edges.
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.02
	tuft.bottom_radius = 0.09
	tuft.height = 0.5
	tuft.radial_segments = 5
	tuft.material = _m_tuft
	var txf: Array[Transform3D] = []
	var tcol: Array[Color] = []
	var ttries := 0
	while txf.size() < 130 and ttries < 800:
		ttries += 1
		var tp := _curb_spot(true)
		var s := _vrng.randf_range(0.8, 1.7)
		txf.append(Transform3D(
			Basis(Vector3.UP, _vrng.randf() * TAU).scaled(Vector3(s, s, s)),
			tp + Vector3(0, 0.22, 0)))
		# Dead-grass tint: green -> straw yellow.
		tcol.append(Color(1, 1, 1).lerp(Color(1.9, 1.5, 0.6), _vrng.randf() * 0.75))
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.mesh = tuft
	tmm.instance_count = txf.size()
	for i in txf.size():
		tmm.set_instance_transform(i, txf[i])
		tmm.set_instance_color(i, tcol[i])
	var tmmi := MultiMeshInstance3D.new()
	tmmi.multimesh = tmm
	add_child(tmmi)
	# Rubble chunks: dark concrete teeth along the roads.
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.5, 0.3, 0.4)
	chunk.material = _m_rubble
	var rxf: Array[Transform3D] = []
	var rtries := 0
	while rxf.size() < 46 and rtries < 400:
		rtries += 1
		var rp := _curb_spot(true)
		rxf.append(Transform3D(
			Basis(Vector3.UP, _vrng.randf() * TAU).scaled(
				Vector3(_vrng.randf_range(0.5, 1.6), _vrng.randf_range(0.4, 1.0),
					_vrng.randf_range(0.5, 1.4))),
			rp + Vector3(0, 0.08, 0)))
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.mesh = chunk
	rmm.instance_count = rxf.size()
	for i in rxf.size():
		rmm.set_instance_transform(i, rxf[i])
	var rmmi := MultiMeshInstance3D.new()
	rmmi.multimesh = rmm
	add_child(rmmi)


func _paper_mm(paper: PlaneMesh, xf: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = paper
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _house(pos: Vector3, face: float, w: float, d: float, wall: Color, roof_c: Color,
		shack := false) -> void:
	# QA pass: houses are enterable — four real walls (front wall has a door
	# gap), a hinged door every house gets, a simple furnished interior, and
	# a roof group that hides while the player is inside (camera would
	# otherwise clip through it).
	# HD pass: trim everywhere — corner boards, foundation skirt, fascia,
	# ridge cap, framed windows with sills + shutters, paneled door with
	# frame + step, per-house roof color, lawn patch.
	# Shack variant (kit-inspired 8x2.9x6-ish cabin): weathered plank walls
	# with seams, squat roof, no chimney/AC/mailbox — same door/interior
	# contract, so safehouse/furniture/minimap all keep working.
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var h := 2.9 if shack else 3.2
	var t := 0.3 # wall thickness
	if shack:
		# Weathered plank: gray-brown or sun-bleached gray.
		wall = Color(0.40, 0.31, 0.22) if _vrng.randf() < 0.5 \
			else Color(0.45, 0.44, 0.40)
	var wall_mat := _std(wall)
	# V2: per-house tonal drift — no two facades weather the same.
	# (Cosmetic: _vrng only; the seeded palette draw above is untouched.)
	var drift := _vrng.randf_range(0.78, 1.06)
	wall_mat.albedo_color = wall * Color(drift, drift * _vrng.randf_range(0.97, 1.03), drift * _vrng.randf_range(0.94, 1.02))
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
	# Grime band: dark weather staining on the wall bases — the apocalypse
	# shows at the bottom of every wall. A ring of thin strips proud of
	# the walls (front split for the door gap), so it never blocks entry.
	# V2: tall rot band; each strip gets its own height so it reads as
	# creeping rot, not a painted stripe. (Cosmetic: no _rng.)
	var gout := 0.16 # strip center offset from the wall plane
	var gh := [_vrng.randf_range(0.65, 1.05), _vrng.randf_range(0.65, 1.05),
		_vrng.randf_range(0.65, 1.05), _vrng.randf_range(0.65, 1.05),
		_vrng.randf_range(0.65, 1.05)]
	_box(root, Vector3(w + 0.08, gh[0], 0.06),
		Vector3(0, gh[0] * 0.5 + 0.05, -face * (d * 0.5) - face * gout), _m_grime)
	_box(root, Vector3(0.06, gh[1], d + 0.08),
		Vector3(-w * 0.5 - gout, gh[1] * 0.5 + 0.05, 0), _m_grime)
	_box(root, Vector3(0.06, gh[2], d + 0.08),
		Vector3(w * 0.5 + gout, gh[2] * 0.5 + 0.05, 0), _m_grime)
	_box(root, Vector3(seg_w + 0.04, gh[3], 0.06),
		Vector3(-(door_w * 0.5 + seg_w * 0.5), gh[3] * 0.5 + 0.05, fz + face * gout), _m_grime)
	_box(root, Vector3(seg_w + 0.04, gh[4], 0.06),
		Vector3(door_w * 0.5 + seg_w * 0.5, gh[4] * 0.5 + 0.05, fz + face * gout), _m_grime)
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
	var prism_h := 1.1 if shack else 1.9 # shacks get a squat cabin roof
	roof.mesh = _prism_mesh(w * 0.5 + 0.5, prism_h, d + 1.0)
	roof.position = Vector3(0, h, 0)
	roof.material_override = roof_mat
	roof_g.add_child(roof)
	# Ridge cap + fascia boards along the eaves.
	_box(roof_g, Vector3(0.34, 0.16, d + 1.05), Vector3(0, h + prism_h + 0.05, 0), roof_mat)
	for ex in [-1.0, 1.0]:
		_box(roof_g, Vector3(0.16, 0.26, d + 1.05),
			Vector3(ex * (w * 0.5 + 0.5), h + 0.10, 0), _m_trim)
	if not shack:
		# Chimney with cap (houses only — shacks heat with a barrel stove).
		_box(roof_g, Vector3(0.6, 1.2, 0.6), Vector3(w * 0.25, h + 1.3, d * 0.12), _m_chimney)
		_box(roof_g, Vector3(0.8, 0.14, 0.8), Vector3(w * 0.25, h + 1.95, d * 0.12), _m_trim)
	else:
		# Vertical plank seams on the shack walls.
		var seam_x := -w * 0.5 + 0.9
		while seam_x < w * 0.5 - 0.5:
			_box(root, Vector3(0.05, h, 0.04),
				Vector3(seam_x, h * 0.5, fz + face * (t * 0.5 + 0.01)), _m_board_dark)
			_box(root, Vector3(0.05, h, 0.04),
				Vector3(seam_x, h * 0.5, -face * (d * 0.5) - face * (t * 0.5 + 0.01)), _m_board_dark)
			seam_x += 0.9
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
	# Porch light: bracket + warm lamp beside the door (glows at night
	# with the other warm lights).
	_box(root, Vector3(0.10, 0.22, 0.10),
		Vector3(door_w * 0.5 + 0.35, 2.45, fz_out), _m_trim)
	_box(root, Vector3(0.16, 0.20, 0.16),
		Vector3(door_w * 0.5 + 0.35, 2.28, fz_out + face * 0.04), _window_lit_mat)
	# Doorway blocker: solid while the door is closed, disabled when open.
	var blocker := _solid(root, Vector3(door_w, door_h, 0.24), Vector3(0, door_h * 0.5, fz))
	# Doorway veil: dark quad just inside the doorway. Visible while the
	# player is outside so an open door never reveals the interior;
	# hidden when the player goes inside (see house_doors.gd).
	var veil := _box(root, Vector3(door_w - 0.08, door_h - 0.08, 0.05),
		Vector3(0, door_h * 0.5, fz - face * 0.06), _m_veil)
	_build_interior(root, w, d, face)
	# Lawn patch grounding the house.
	_box(root, Vector3(w + 5.0, 0.02, d + 5.0), Vector3(0, 0.005, 0), _m_lawn)
	# Windows: framed, with sills; shutters on the front pair. V2: ~40%
	# are smashed — broken dark holes, not just cracked glass. (Uses
	# _vrng: cosmetic.)
	var out_f := face * (d * 0.5 + t * 0.5 + 0.03)
	var broke_chance := 0.55 if shack else 0.40 # shacks are rougher
	var win_y := 1.6 if shack else 1.7
	_window(root, Vector3(-w * 0.28, win_y, out_f), Vector3(0, 0, face), not shack,
		_vrng.randf() < broke_chance)
	_window(root, Vector3(w * 0.28, win_y, out_f), Vector3(0, 0, face), not shack,
		_vrng.randf() < broke_chance)
	if shack:
		# One small side window, usually smashed; then a discard draw so the
		# layout RNG consumes 4 window rolls per house either way.
		_window(root, Vector3(w * 0.5 + t * 0.5 + 0.03, win_y, 0.0), Vector3(1, 0, 0),
			false, _vrng.randf() < 0.65)
		_rng.randf()
	else:
		_window(root, Vector3(-w * 0.5 - t * 0.5 - 0.03, 1.7, 0.0), Vector3(-1, 0, 0),
			false, _vrng.randf() < 0.40)
		_window(root, Vector3(w * 0.5 + t * 0.5 + 0.03, 1.7, 0.0), Vector3(1, 0, 0),
			false, _vrng.randf() < 0.40)
	if not shack:
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
		"pivot": pivot, "blocker": blocker, "veil": veil,
		"pos": pos + Vector3(0, 0, fz), "open": false, "safehouse": false,
	}
	houses.append({"pos": pos, "w": w, "d": d, "face": face, "roof": roof_g, "door": door, "root": root})


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
	# Real porch light (no shadows): a warm pool at the home base at night.
	# Position matches the emissive porch lamp built in _house().
	var pl := OmniLight3D.new()
	pl.position = Vector3(1.05, 2.3, fz + face * 0.5)
	pl.light_color = Color(1.0, 0.78, 0.52)
	pl.light_energy = 0.0
	pl.omni_range = 9.0
	pl.shadow_enabled = false
	root.add_child(pl)
	_porch_lights.append(pl)


func _build_interior(root: Node3D, w: float, d: float, face: float) -> void:
	# HD furnished interior. The loot container spot (local x ≈ -w/2+1,
	# front wall) stays clear — main.gd places one searchable container
	# per house there. Door swing zone (x in [-0.7, 0.7] near front) clear.
	_box(root, Vector3(w - 0.7, 0.06, d - 0.7), Vector3(0, 0.03, 0), _m_floor)
	var back := -face * (d * 0.5 - 1.2)
	# Couch: base, back, arms, two cushions — against the back wall, right of the loot corner.
	var cx := w * 0.18
	_furn(_solid_box(root, Vector3(2.1, 0.55, 0.95), Vector3(cx, 0.32, back), _m_couch))
	_furn(_solid_box(root, Vector3(2.1, 0.75, 0.28), Vector3(cx, 0.65, back - face * 0.42), _m_couch))
	for ax in [-1.0, 1.0]:
		_furn(_solid_box(root, Vector3(0.28, 0.85, 0.95), Vector3(cx + ax, 0.48, back), _m_couch))
	_furn(_box(root, Vector3(0.82, 0.16, 0.8), Vector3(cx - 0.46, 0.66, back + face * 0.05), _m_cushion))
	_furn(_box(root, Vector3(0.82, 0.16, 0.8), Vector3(cx + 0.46, 0.66, back + face * 0.05), _m_cushion))
	# Coffee table with lower shelf; slab sides instead of four legs.
	var tx := w * 0.18
	var tz := back + face * 1.9
	_furn(_box(root, Vector3(1.4, 0.1, 0.8), Vector3(tx, 0.62, tz), _m_table))
	_furn(_box(root, Vector3(1.2, 0.06, 0.6), Vector3(tx, 0.22, tz), _m_shelf))
	for sx in [-0.6, 0.6]:
		_furn(_box(root, Vector3(0.09, 0.57, 0.7), Vector3(tx + sx, 0.31, tz), _m_table))
	_furn(_solid(root, Vector3(1.4, 0.65, 0.8), Vector3(tx, 0.33, tz)))
	# Rug: layered flat boxes in the middle of the room.
	_furn(_box(root, Vector3(2.8, 0.035, 2.0), Vector3(0.9, 0.08, -face * 0.6), _m_rug))
	# Bookshelf on the right wall with book spines.
	var shx := w * 0.5 - 0.65
	_furn(_solid_box(root, Vector3(0.45, 2.0, 1.7), Vector3(shx, 1.0, 0.2), _m_shelf))
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
	_furn(_solid(root, Vector3(0.35, 1.9, 0.35), Vector3(lx, 0.95, lz)))
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
	_furn(_solid_box(root, Vector3(0.62, 0.90, 2.2), Vector3(kx, 0.45, 0.6), _m_counter))
	_box(root, Vector3(0.66, 0.06, 2.26), Vector3(kx, 0.93, 0.6), _m_trim)
	# Bed in the back-left corner: frame, mattress, pillow.
	var bedx := -(w * 0.5 - 1.35)
	var bedz := -face * (d * 0.5 - 1.75)
	_furn(_solid_box(root, Vector3(1.7, 0.32, 1.15), Vector3(bedx, 0.22, bedz), _m_bed))
	_box(root, Vector3(1.6, 0.18, 1.05), Vector3(bedx, 0.47, bedz), _m_bedding)
	_box(root, Vector3(0.45, 0.12, 0.7), Vector3(bedx - 0.5, 0.60, bedz), _m_cushion)
	# End table beside the couch (fixed spot, no RNG draws) + a mug on top.
	var etx := cx + 1.75
	_furn(_solid_box(root, Vector3(0.5, 0.5, 0.5), Vector3(etx, 0.25, back), _m_table))
	_cyl(root, 0.05, 0.04, 0.10, Vector3(etx, 0.55, back), _m_cushion)
	# Potted plant in the front-right corner (fixed spot, no RNG draws).
	var ppx := w * 0.5 - 1.0
	var ppz := face * (d * 0.5 - 1.0)
	_cyl(root, 0.20, 0.15, 0.35, Vector3(ppx, 0.175, ppz),
		_std(Color(0.45, 0.28, 0.20), 0.9))
	_furn(_solid(root, Vector3(0.45, 0.4, 0.45), Vector3(ppx, 0.2, ppz)))
	_sphere(root, 0.30, Vector3(ppx, 0.62, ppz), _m_bush, true)
	_sphere(root, 0.20, Vector3(ppx + 0.12, 0.85, ppz - 0.08), _m_bush, true)
	# --- Detail-density pass: baseboards, ceiling light, stocked shelf. ---
	# Baseboards: trim strips proud of the interior liner on all walls.
	var bb := 0.065 # offset from liner plane toward room center
	var _door_w := 1.4
	var _seg_w := (w - _door_w) * 0.5
	var _fz := face * (d * 0.5)
	_box(root, Vector3(w - 0.2, 0.14, 0.05),
		Vector3(0, 0.10, -face * (d * 0.5 - 0.19) + face * bb), _m_trim)
	_box(root, Vector3(0.05, 0.14, d - 0.2),
		Vector3(-(w * 0.5 - 0.19) + bb, 0.10, 0), _m_trim)
	_box(root, Vector3(0.05, 0.14, d - 0.2),
		Vector3(w * 0.5 - 0.19 - bb, 0.10, 0), _m_trim)
	_box(root, Vector3(_seg_w, 0.14, 0.05),
		Vector3(-(_door_w * 0.5 + _seg_w * 0.5), 0.10, _fz - face * 0.19 + face * bb), _m_trim)
	_box(root, Vector3(_seg_w, 0.14, 0.05),
		Vector3(_door_w * 0.5 + _seg_w * 0.5, 0.10, _fz - face * 0.19 + face * bb), _m_trim)
	# Ceiling light: mount + warm emissive panel at room center.
	_box(root, Vector3(0.22, 0.08, 0.22), Vector3(0.4, 2.90, 0), _m_trim)
	_box(root, Vector3(0.44, 0.05, 0.44), Vector3(0.4, 2.84, 0), _window_lit_mat)
	# Wall shelf with cans on the left wall, above the kitchen counter.
	var shlf_x := -(w * 0.5 - 0.19) + 0.20
	var shlf_z := -0.9
	_furn(_box(root, Vector3(0.36, 0.05, 1.3), Vector3(shlf_x, 1.55, shlf_z), _m_shelf))
	_furn(_box(root, Vector3(0.36, 0.05, 1.3), Vector3(shlf_x, 1.95, shlf_z), _m_shelf))
	var can_mats := [_m_canopy_edge, _m_dash_faded, _m_curb, _m_rust]
	var can_z := shlf_z - 0.5
	for ci in 5:
		var cm: StandardMaterial3D = can_mats[_vrng.randi() % can_mats.size()]
		_cyl(root, 0.055, 0.055, 0.15,
			Vector3(shlf_x + _vrng.randf_range(-0.06, 0.06), 1.655, can_z), cm)
		if _vrng.randf() < 0.7:
			_cyl(root, 0.055, 0.055, 0.15,
				Vector3(shlf_x + _vrng.randf_range(-0.06, 0.06), 2.055, can_z + 0.18), cm)
		can_z += 0.25
	# Second framed picture (seeded spot on the right wall).
	var pic2_z := _vrng.randf_range(-1.6, 1.2)
	_box(root, Vector3(0.05, 0.55, 0.42),
		Vector3(w * 0.5 - 0.24, 1.95, pic2_z), _m_picture)


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
		mat = _m_window_hole # V2: smashed panes are near-black holes
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
		# Half the smashed windows get nailed planks: the world fought back.
		# (Cosmetic: _vrng only — layout RNG untouched.)
		if _vrng.randf() < 0.5:
			var bw := Vector3(1.55, 0.17, 0.07) if along_x else Vector3(0.07, 0.17, 1.55)
			var off1 := Vector3(0, 0.28, 0)
			var off2 := Vector3(0, -0.30, 0)
			var p1 := _box(root, bw, center + off1 + outward * 0.14, _m_board)
			var p2 := _box(root, bw, center + off2 + outward * 0.14, _m_board)
			p1.rotation.z = 0.30 if along_x else 0.0
			p2.rotation.z = -0.34 if along_x else 0.0
			if not along_x:
				p1.rotation.x = 0.30
				p2.rotation.x = -0.34
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
	var target := _rng.randi_range(12, 14)
	var tries := 0
	while _lot_specs.size() < target and tries < 500:
		tries += 1
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var hx := _rng.randf_range(-86.0, 86.0)
		if absf(hx - road_ns_x) < 11.0: # keep the intersection clear
			continue
		var hz: float = road_ew_z + side * _rng.randf_range(15.0, 23.0)
		if absf(hz) > 92.0:
			continue
		var w := _rng.randf_range(6.8, 8.6)
		var d := _rng.randf_range(6.2, 7.6)
		var rect := Rect2(hx - w * 0.5 - 3.0, hz - d * 0.5 - 3.0, w + 6.0, d + 6.0)
		if not _lot_free(rect):
			continue
		_lot_rects.append(rect)
		_lot_specs.append({"pos": Vector3(hx, 0, hz), "face": -side, "w": w, "d": d})
	# Ironclad guarantee: the map is mostly empty, so a coarse full-map grid
	# scan always finds room to reach the target count (the old single-row
	# fallback could be fully blocked by a dirt road).
	if _lot_specs.size() < target:
		var gx := -84.0
		while gx <= 84.0 and _lot_specs.size() < target:
			var gz := -84.0
			while gz <= 84.0 and _lot_specs.size() < target:
				if absf(gx - road_ns_x) > 10.0 or absf(gz - road_ew_z) > 10.0:
					var rect := Rect2(gx - 7.3, gz - 6.8, 14.6, 13.6)
					if _lot_free(rect):
						_lot_rects.append(rect)
						var gface := -signf(gz - road_ew_z)
						if gface == 0.0:
							gface = 1.0
						_lot_specs.append({"pos": Vector3(gx, 0, gz),
							"face": gface, "w": 8.0, "d": 7.0})
				gz += 18.0
			gx += 18.0
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
		# Palette draws stay in seed order. (The shack-variant experiment was
		# reverted: replacing houses changed the layout hash and violated the
		# purely-additive rule, so every house builds at its spec'd dims.)
		var wc: Color = walls[_rng.randi() % walls.size()]
		var rc: Color = roofs[_rng.randi() % roofs.size()]
		var sw := float(s["w"])
		var sd := float(s["d"])
		_house(s["pos"], float(s["face"]), sw, sd, wc, rc, false)
	# The safehouse: one random house gets the boards.
	safehouse_index = _rng.randi() % houses.size()
	_board_house(houses[safehouse_index] as Dictionary)


func _build_streetlights() -> void:
	# Seeded: lamps march along both roads, alternating sides.
	var spots: Array[Vector3] = []
	var x := -86.0
	var side := 1.0
	while x < 86.0:
		spots.append(Vector3(x, 0, road_ew_z + side * 5.6))
		x += _rng.randf_range(18.0, 26.0)
		side = -side
	var z := -80.0
	var side2 := 1.0
	while z < 86.0:
		spots.append(Vector3(road_ns_x + side2 * 5.6, 0, z))
		z += _rng.randf_range(24.0, 34.0)
		side2 = -side2
	for i in spots.size():
		var pos: Vector3 = spots[i]
		# Arm reaches toward the nearest road.
		var arm_dir := Vector3(0, 0, 1) if pos.z < road_ew_z else Vector3(0, 0, -1)
		if absf(pos.x - road_ns_x) < absf(pos.z - road_ew_z):
			arm_dir = Vector3(1, 0, 0) if pos.x < road_ns_x else Vector3(-1, 0, 0)
		# Every 3rd lamp gets a real spotlight (no shadows): warm pools of
		# light along the roads at night. Capped: ~5 of ~14 lamps.
		_streetlight(pos, arm_dir, i % 3 == 1)


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
	while placed < 20 and tries < 400:
		tries += 1
		var p := Vector3(_rng.randf_range(-90, 90), 0, _rng.randf_range(-90, 90))
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
	# One layout-RNG draw per tree (sway phase), exactly as before — the
	# variant itself is cosmetic (_vrng) so the layout stream never shifts.
	var phase := _rng.randf() * TAU
	var kind := _vrng.randf()
	if kind < 0.35:
		_tree_dead_pine(pos, s, phase)
	elif kind < 0.60:
		_tree_bare_oak(pos, s, phase)
	else:
		_tree_leafy(pos, s, phase, _vrng.randf() < 0.35)


func _tree_leafy(pos: Vector3, s: float, phase: float, sickly: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.13 * s, 0.22 * s, 1.9 * s, Vector3(0, 0.95 * s, 0), _m_bark) # tapered trunk
	_cyl(root, 0.30 * s, 0.38 * s, 0.35 * s, Vector3(0, 0.16 * s, 0), _m_bark) # root flare
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.5 * s, 0)
	root.add_child(pivot)
	# Sickly trees keep the shape but wear the dying-yellow canopy.
	var leaf_a := _m_leaf_dead if sickly else _m_leaf
	# Canopies cast no shadow: at the flattened morning/evening sun angle a
	# faceted canopy throws an oversized blobby shadow that reads as a
	# rendering bug on porches (Tbandz iPhone field report). The trunk keeps
	# casting, so trees still ground themselves in the scene.
	for c in [
		_sphere(pivot, 1.35 * s, Vector3(0, 0.4 * s, 0), leaf_a, true),
		_sphere(pivot, 1.00 * s, Vector3(0.9 * s, -0.1 * s, 0.4 * s), _m_leaf2, true),
		_sphere(pivot, 0.95 * s, Vector3(-0.85 * s, 0.0, -0.35 * s), _m_leaf2, true),
		_sphere(pivot, 0.70 * s, Vector3(0.1 * s, 1.15 * s, -0.2 * s), leaf_a, true),
	]:
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sway.append([pivot, phase, 0.035])
	_solid(root, Vector3(0.5, 2.2, 0.5), Vector3(0, 1.1, 0))


func _tree_dead_pine(pos: Vector3, s: float, phase: float) -> void:
	# A pine that didn't make it: snapped top, bare gray limbs, no needles.
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.10 * s, 0.20 * s, 3.4 * s, Vector3(0, 1.7 * s, 0), _m_branch)
	_cyl(root, 0.26 * s, 0.34 * s, 0.40 * s, Vector3(0, 0.2 * s, 0), _m_branch)
	_cyl(root, 0.09 * s, 0.05 * s, 0.5 * s, Vector3(0.14 * s, 3.55 * s, 0), _m_branch) # snapped tip
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.4 * s, 0)
	root.add_child(pivot)
	for _i in _vrng.randi_range(3, 4):
		var a := _vrng.randf() * TAU
		var lean := _vrng.randf_range(0.5, 1.0)
		var ln := _vrng.randf_range(0.8, 1.3) * s
		var br := _cyl(pivot, 0.02 * s, 0.05 * s, ln,
			Vector3(cos(a) * ln * 0.32, _vrng.randf_range(-0.3, 0.4) * s,
				sin(a) * ln * 0.32), _m_branch)
		br.rotation = Vector3(sin(a) * lean, 0.0, -cos(a) * lean)
	_sway.append([pivot, phase, 0.02])
	_solid(root, Vector3(0.5, 3.2, 0.5), Vector3(0, 1.6, 0))


func _tree_bare_oak(pos: Vector3, s: float, phase: float) -> void:
	# Twisted leafless oak: thick trunk, gnarled branches reaching up.
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_cyl(root, 0.16 * s, 0.30 * s, 2.4 * s, Vector3(0, 1.2 * s, 0), _m_bark)
	_cyl(root, 0.36 * s, 0.46 * s, 0.40 * s, Vector3(0, 0.2 * s, 0), _m_bark)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.3 * s, 0)
	root.add_child(pivot)
	for _i in _vrng.randi_range(4, 6):
		var a := _vrng.randf() * TAU
		var lean := _vrng.randf_range(0.3, 0.8)
		var ln := _vrng.randf_range(1.0, 1.8) * s
		var br := _cyl(pivot, 0.03 * s, 0.07 * s, ln,
			Vector3(cos(a) * ln * 0.30, ln * 0.30, sin(a) * ln * 0.30), _m_bark)
		br.rotation = Vector3(sin(a) * lean, 0.0, -cos(a) * lean)
		# A forked twig off the main limb.
		if _vrng.randf() < 0.5:
			var tw := _cyl(br, 0.015 * s, 0.03 * s, ln * 0.5,
				Vector3(0, ln * 0.35, 0), _m_branch)
			tw.rotation.z = _vrng.randf_range(-0.7, 0.7)
	_sway.append([pivot, phase, 0.025])
	_solid(root, Vector3(0.6, 2.6, 0.6), Vector3(0, 1.3, 0))


## V2 nature scatter: rocks, extra bushes, curb saplings. Purely cosmetic
## (_vrng + _open_spot_visual): never touches layout RNG or the hash.
func _build_nature_v2() -> void:
	# Granite rocks: one or two faceted lumps each.
	for _i in 16:
		var p := _open_spot_visual(1.5)
		var s := _vrng.randf_range(0.5, 1.3)
		var r1 := _sphere(self, 0.55 * s, p + Vector3(0, 0.22 * s, 0), _m_rock, true)
		r1.scale.y = 0.6
		if _vrng.randf() < 0.6:
			var r2 := _sphere(self, 0.32 * s,
				p + Vector3(0.45 * s, 0.12 * s, 0.25 * s), _m_rock, true)
			r2.scale.y = 0.5
	# Extra bushes clustered on open ground (the house-front ones stay).
	for _i in 18:
		var bp := _open_spot_visual(1.0)
		var b := _sphere(self, _vrng.randf_range(0.5, 0.9),
			bp + Vector3(0, 0.32, 0), _m_bush, true)
		b.scale.y = 0.65
	# Curb saplings: small dead pines leaning over the sidewalks.
	for _i in 8:
		var sp := _curb_spot(true)
		_tree_dead_pine(sp, _vrng.randf_range(0.35, 0.55), _vrng.randf() * TAU)


## Dense treeline ringing the neighborhood edge — the visible natural
## boundary ("forest beyond"): dark, thick, swallowing the road ends.
## Three MultiMesh draw calls total. (Cosmetic: _vrng only.)
func _build_choppables() -> void:
	# Wood economy: dead trees you can chop (2 hits -> 2-3 wood). Eight
	# scattered on open ground, eight hugging the forest edge. Own RNG
	# stream (_crng) so placement never shifts layout/visual/loot streams.
	choppable_trees.clear()
	var placed := 0
	var tries := 0
	while placed < 8 and tries < 400:
		tries += 1
		var p := Vector3(_crng.randf_range(-85, 85), 0, _crng.randf_range(-85, 85))
		if _on_road(p, 2.0) or _point_in_lots(p, 2.0):
			continue
		if p.distance_to(player_start) < 8.0:
			continue
		_add_choppable(p)
		placed += 1
	placed = 0
	tries = 0
	while placed < 8 and tries < 400:
		tries += 1
		var a := _crng.randf() * TAU
		var r := _crng.randf_range(68.0, 84.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _on_road(p, 2.5) or _point_in_lots(p, 2.5):
			continue
		_add_choppable(p)
		placed += 1


func _add_choppable(p: Vector3) -> void:
	var t := ChoppableTree.new()
	add_child(t)
	t.build(Vector3(p.x, 0, p.z), _crng.randf_range(0.9, 1.2), _crng.randi())
	choppable_trees.append(t)


func _build_treeline() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 5
	trunk_mesh.material = _m_trunk_dark
	var cone_low := CylinderMesh.new()
	cone_low.top_radius = 0.0
	cone_low.bottom_radius = 2.2
	cone_low.height = 4.2
	cone_low.radial_segments = 6
	cone_low.material = _m_pine_dark
	var cone_top := CylinderMesh.new()
	cone_top.top_radius = 0.0
	cone_top.bottom_radius = 1.5
	cone_top.height = 3.2
	cone_top.radial_segments = 6
	cone_top.material = _m_pine_dark
	var t_xf: Array[Transform3D] = []
	var l_xf: Array[Transform3D] = []
	var u_xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var n := 124
	for i in n:
		var a := TAU * float(i) / float(n) + _vrng.randf_range(-0.05, 0.05)
		var r := _vrng.randf_range(88.0, 96.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _on_road(p, 4.5):
			continue # the roads run out into the forest, not through trees
		if _point_in_lots(p, 2.0):
			continue # never swallow a house lot
		var s := _vrng.randf_range(0.85, 1.3)
		var yaw := _vrng.randf() * TAU
		t_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
			Vector3(p.x, 1.2 * s, p.z)))
		l_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
			Vector3(p.x, 3.9 * s, p.z)))
		u_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
			Vector3(p.x, 6.2 * s, p.z)))
		# Dark canopy tint: deep green -> dead brown.
		cols.append(Color(1, 1, 1).lerp(Color(1.5, 1.0, 0.7), _vrng.randf()))
	_add_treeline_mm(trunk_mesh, t_xf, [])
	_add_treeline_mm(cone_low, l_xf, cols)
	_add_treeline_mm(cone_top, u_xf, cols)


func _add_treeline_mm(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color]) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if not cols.is_empty():
		mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


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


func _fence_run(center: Vector3, length: float, rot_y := 0.0) -> void:
	var root := Node3D.new()
	root.position = center
	root.rotation.y = rot_y
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
	var n := _rng.randi_range(6, 9)
	var smoking_idx := _rng.randi() % n
	var placed: Array[Vector3] = []
	for i in n:
		var col: Color = colors[_rng.randi() % colors.size()]
		var cp := Vector3.ZERO
		var rot := 0.0
		var found := false
		for _t in 40:
			if _rng.randf() < 0.6:
				var cx := _rng.randf_range(-86.0, 80.0)
				if absf(cx - road_ns_x) < 8.0: # keep the intersection clear
					continue
				var cz := road_ew_z + (2.2 if _rng.randf() < 0.5 else -2.2)
				rot = _rng.randf_range(-0.15, 0.15) + (0.0 if cz > road_ew_z else PI)
				cp = Vector3(cx, 0, cz)
			else:
				var nz := _rng.randf_range(-86.0, 86.0)
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
	# V2: ~35% of cars are wrecks — missing a wheel, dented panels, sitting
	# crooked. (Cosmetic: _vrng only.)
	var wrecked := _vrng.randf() < 0.35
	if wrecked:
		root.rotation.z = _vrng.randf_range(-0.06, 0.06)
		root.rotation.x = _vrng.randf_range(-0.04, 0.04)
	var paint := _std(color, 0.55, 0.25)
	if wrecked:
		# Sun-faded, dustier paint on wrecks.
		paint.albedo_color = color.lerp(Color(0.45, 0.42, 0.38), 0.35)
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
	# Wheels with hubs — wrecks lose one.
	var missing_wheel := -1
	if wrecked:
		missing_wheel = _vrng.randi() % 4
	var wi := 0
	for sx in [-1.35, 1.35]:
		for sz in [-0.85, 0.85]:
			if wi != missing_wheel:
				var w := _cyl(root, 0.34, 0.34, 0.24, Vector3(sx, 0.34, sz), _m_tire)
				w.rotation.z = PI * 0.5
				var hub := _cyl(root, 0.13, 0.13, 0.26, Vector3(sx, 0.34, sz), _m_hub)
				hub.rotation.z = PI * 0.5
			wi += 1
	# Bumpers + headlights.
	_box(root, Vector3(0.28, 0.28, 1.95), Vector3(2.12, 0.55, 0), _m_bumper)
	_box(root, Vector3(0.28, 0.28, 1.95), Vector3(-2.12, 0.55, 0), _m_bumper)
	_box(root, Vector3(0.10, 0.18, 0.34), Vector3(2.12, 0.78, 0.62), _m_headlight)
	_box(root, Vector3(0.10, 0.18, 0.34), Vector3(2.12, 0.78, -0.62), _m_headlight)
	# Small rust patches low on the hull.
	_box(root, Vector3(0.34, 0.16, 0.03), Vector3(0.9, 0.45, 0.96), _m_rust)
	_box(root, Vector3(0.28, 0.14, 0.03), Vector3(-1.4, 0.42, -0.96), _m_rust)
	if wrecked:
		# Dents: dark crumpled quads slapped on the hull and hood.
		for _d in _vrng.randi_range(2, 4):
			var dx := _vrng.randf_range(-1.8, 1.8)
			var dz := 0.97 if _vrng.randf() < 0.5 else -0.97
			_box(root, Vector3(_vrng.randf_range(0.4, 0.9), _vrng.randf_range(0.2, 0.4), 0.03),
				Vector3(dx, _vrng.randf_range(0.45, 0.85), dz), _m_dent,
				_vrng.randf() * 0.6)
		# Smashed windshield on half the wrecks.
		if _vrng.randf() < 0.5:
			_box(root, Vector3(0.05, 0.4, 1.3), Vector3(0.76, 1.18, 0), _m_window_hole)
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
			# Rust bands eating the pole bases. (Cosmetic: fixed geometry.)
			_cyl(root, 0.17, 0.20, 0.55, Vector3(px, 0.55, pz), _m_rust_patch)
	_box(root, Vector3(14, 0.5, 10), Vector3(0, 5.2, 0), canopy_mat)
	_box(root, Vector3(14.15, 0.30, 10.15), Vector3(0, 4.90, 0), _m_canopy_edge) # fascia band
	var pump_mat := _std(Color(0.60, 0.15, 0.12))
	for px in [-3.0, 3.0]:
		_box(root, Vector3(0.9, 1.5, 0.7), Vector3(px, 0.75, 0), pump_mat)
		_box(root, Vector3(0.94, 0.18, 0.74), Vector3(px, 1.58, 0), _m_trim) # pump cap
		_box(root, Vector3(0.5, 0.5, 0.1), Vector3(px, 1.1, -0.36), _m_window_dark)
		# Rust streaks bleeding down the pump faces.
		_box(root, Vector3(0.20, 0.85, 0.03), Vector3(px + 0.25, 0.95, 0.36), _m_rust_patch)
		_box(root, Vector3(0.14, 0.60, 0.03), Vector3(px - 0.30, 0.80, 0.36), _m_rust_patch)
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
	# Weathered plank fences: a few runs on open ground, solid so the
	# player and zombies walk around them. (Cosmetic: _vrng +
	# _open_spot_visual — no layout RNG, no lot registration, hash safe.)
	for _fi in 3:
		var froot := Node3D.new()
		froot.position = _open_spot_visual(3.0)
		froot.rotation.y = _vrng.randf() * TAU
		add_child(froot)
		var flen := _vrng.randf_range(4.0, 6.5)
		var fposts := int(flen / 1.5) + 1
		for pi in fposts:
			var lx := -flen * 0.5 + float(pi) * 1.5
			_box(froot, Vector3(0.14, 1.15, 0.14), Vector3(lx, 0.57, 0), _m_board)
		_box(froot, Vector3(flen + 0.1, 0.12, 0.06), Vector3(0, 0.92, 0), _m_board)
		_box(froot, Vector3(flen + 0.1, 0.12, 0.06), Vector3(0, 0.48, 0), _m_board)
		_solid(froot, Vector3(flen + 0.2, 1.15, 0.35), Vector3(0, 0.57, 0))


## World-density pass (runs LAST in build_world, after the safehouse porch
## and player start are known): wooden pallet stacks, extra fences flanking
## the dirt roads, sandbag lines, extra trash piles. All cosmetic (_vrng +
## visual spot samplers): the layout RNG stream and the hash are untouched.
func _build_props_v2() -> void:
	var sand_mat := _std(Color(0.55, 0.48, 0.34), 1.0)
	# Pallet stacks on open ground, clear of the porch / spawn.
	for _i in 6:
		var p := _porch_safe_spot(2.0, 8.0)
		var n := _vrng.randi_range(3, 5)
		for k in n:
			_box(self, Vector3(1.2, 0.14, 1.0),
				p + Vector3(_vrng.randf_range(-0.1, 0.1), 0.10 + k * 0.16,
					_vrng.randf_range(-0.1, 0.1)),
				_m_wood, _vrng.randf_range(-0.2, 0.2))
		_solid(self, Vector3(1.3, 0.9, 1.1), p + Vector3(0, 0.45, 0))
	# Fences flanking the dirt roads (never on the road, a lot, or the porch).
	for dr in _dirt_rects:
		for _fi in 2:
			var along_x := dr.size.x > dr.size.y
			var c := dr.get_center()
			var t := _vrng.randf_range(0.15, 0.85)
			var side := 1.0 if _vrng.randf() < 0.5 else -1.0
			var fp: Vector3
			var rot := 0.0
			if along_x:
				fp = Vector3(c.x + (t - 0.5) * dr.size.x, 0,
					c.y + side * (dr.size.y * 0.5 + 3.4))
			else:
				rot = PI * 0.5
				fp = Vector3(c.x + side * (dr.size.x * 0.5 + 3.4), 0,
					c.y + (t - 0.5) * dr.size.y)
			if _on_road(fp, 1.0) or _point_in_lots(fp, 1.5):
				continue
			if fp.distance_to(player_start) < 6.0 \
					or fp.distance_to(safehouse_porch) < 6.0:
				continue
			_fence_run(fp, _vrng.randf_range(4.0, 6.5), rot)
	# Sandbag lines: low cover rows near commercial fronts, off to the side
	# of the door path.
	for _i in 4:
		if _building_specs.is_empty():
			break
		var spec := _building_specs[_vrng.randi() % _building_specs.size()] as Dictionary
		var bp := spec["pos"] as Vector3
		var bw := float(spec["w"])
		var bd := float(spec["d"])
		var face := float(spec["face"])
		var sp := bp + Vector3(bw * 0.5 + _vrng.randf_range(2.5, 4.5), 0,
			face * (bd * 0.5 + _vrng.randf_range(1.0, 3.0)))
		if _on_road(sp, 1.0) or _point_in_lots(sp, 1.0):
			continue
		if sp.distance_to(player_start) < 6.0 \
				or sp.distance_to(safehouse_porch) < 6.0:
			continue
		_sandbag_line(sp, _vrng.randf() * TAU, sand_mat)
	# Extra trash piles: curbsides and dirt-road shoulders.
	for _i in 12:
		var tp: Vector3
		if not _dirt_rects.is_empty() and _vrng.randf() < 0.5:
			tp = _dirt_side_spot()
		else:
			tp = _curb_spot(true)
		if _point_in_lots(tp, 0.5):
			continue
		var tb := _sphere(self, _vrng.randf_range(0.35, 0.5),
			tp + Vector3(0, 0.28, 0), _m_trash)
		tb.scale.y = 0.7


func _build_ground_patches() -> void:
	# Quality pass: flat ground-variation quads (worn dirt, trampled dark
	# grass, pale ash) scattered on open grass. Cosmetic RNG only — the
	# layout stream never shifts. Rejects roads, lots, the porch and the
	# player start so nothing sits underfoot where it matters.
	var mats := [_m_patch_dirt, _m_patch_dark, _m_patch_ash]
	var placed := 0
	var tries := 0
	while placed < 48 and tries < 300:
		tries += 1
		var p := Vector3(_vrng.randf_range(-88, 88), 0, _vrng.randf_range(-88, 88))
		if _on_road(p, 1.5) or _point_in_lots(p, 1.0):
			continue
		if p.distance_to(player_start) < 5.0 or p.distance_to(safehouse_porch) < 5.0:
			continue
		var s := _vrng.randf_range(1.6, 4.2)
		_box(self, Vector3(s, 0.012, s * _vrng.randf_range(0.6, 1.0)),
			Vector3(p.x, 0.018, p.z), mats[_vrng.randi() % 3],
			_vrng.randf_range(0.0, TAU))
		placed += 1
	# Road cracks: thin dark seams on the asphalt.
	var cracked := 0
	tries = 0
	while cracked < 22 and tries < 120:
		tries += 1
		var on_ew := _vrng.randf() < 0.5
		var p := Vector3(_vrng.randf_range(-70, 70), 0, 0)
		if on_ew:
			p = Vector3(p.x, 0, road_ew_z + _vrng.randf_range(-3.2, 3.2))
		else:
			p = Vector3(road_ns_x + _vrng.randf_range(-3.2, 3.2), 0, p.x)
		_box(self, Vector3(_vrng.randf_range(0.10, 0.22), 0.012,
				_vrng.randf_range(1.2, 3.4)),
			Vector3(p.x, 0.012, p.z), _m_asphalt_crack,
			_vrng.randf_range(-0.4, 0.4))
		cracked += 1


func _build_street_props() -> void:
	# Quality pass: fire hydrants on sidewalk corners + knocked-over
	# traffic cones near the roads. Cosmetic RNG only.
	for _i in 6:
		var p := _curb_spot(true)
		if _point_in_lots(p, 0.5):
			continue
		_hydrant(p)
	for _i in 9:
		var p := _road_point_near()
		_cone(p, _vrng.randf() < 0.35)


func _hydrant(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _vrng.randf() * TAU
	add_child(root)
	_cyl(root, 0.16, 0.20, 0.62, Vector3(0, 0.31, 0), _m_hydrant) # body
	_cyl(root, 0.20, 0.20, 0.10, Vector3(0, 0.05, 0), _m_hydrant_dark) # base
	_sphere(root, 0.15, Vector3(0, 0.68, 0), _m_hydrant) # dome cap
	_cyl(root, 0.09, 0.09, 0.44, Vector3(0, 0.42, 0), _m_hydrant_dark) # side caps bar
	_box(root, Vector3(0.10, 0.10, 0.10), Vector3(0, 0.78, 0), _m_hydrant_dark) # top nut
	_solid(root, Vector3(0.4, 0.7, 0.4), Vector3(0, 0.35, 0))


func _cone(p: Vector3, tipped: bool) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _vrng.randf() * TAU
	add_child(root)
	if tipped:
		root.rotation.z = PI * 0.5 - _vrng.randf_range(0.0, 0.2)
		root.position.y = 0.18
	_cyl(root, 0.03, 0.16, 0.52, Vector3(0, 0.28, 0), _m_cone) # cone
	_cyl(root, 0.085, 0.115, 0.10, Vector3(0, 0.33, 0), _m_cone_band) # band
	_box(root, Vector3(0.34, 0.04, 0.34), Vector3(0, 0.02, 0), _m_cone) # base


func _road_point_near() -> Vector3:
	# A point just off a road edge (for cones).
	if _vrng.randf() < 0.5:
		return Vector3(_vrng.randf_range(-70, 70), 0,
			road_ew_z + (4.6 if _vrng.randf() < 0.5 else -4.6))
	return Vector3(road_ns_x + (4.6 if _vrng.randf() < 0.5 else -4.6), 0,
		_vrng.randf_range(-70, 70))


## A low sandbag line: two staggered rows of bags, solid low cover.
func _sandbag_line(center: Vector3, rot_y: float, mat: Material) -> void:
	var root := Node3D.new()
	root.position = center
	root.rotation.y = rot_y
	add_child(root)
	var n := _vrng.randi_range(5, 8)
	for i in n:
		var lx := (float(i) - float(n - 1) * 0.5) * 0.62
		_box(root, Vector3(0.58, 0.24, 0.36), Vector3(lx, 0.13, 0), mat,
			_vrng.randf_range(-0.12, 0.12))
		if _vrng.randf() < 0.7:
			_box(root, Vector3(0.58, 0.24, 0.36),
				Vector3(lx + 0.3, 0.36, _vrng.randf_range(-0.05, 0.05)), mat,
				_vrng.randf_range(-0.15, 0.15))
	_solid(root, Vector3(n * 0.62, 0.6, 0.45), Vector3(0, 0.3, 0))


## Random point just off a dirt-road shoulder (cosmetic stream).
func _dirt_side_spot() -> Vector3:
	var dr := _dirt_rects[_vrng.randi() % _dirt_rects.size()]
	var c := dr.get_center()
	var along_x := dr.size.x > dr.size.y
	var t := _vrng.randf_range(0.05, 0.95)
	var side := 1.0 if _vrng.randf() < 0.5 else -1.0
	var off := _vrng.randf_range(2.8, 4.2)
	if along_x:
		return Vector3(c.x + (t - 0.5) * dr.size.x, 0,
			c.y + side * (dr.size.y * 0.5 + off))
	return Vector3(c.x + side * (dr.size.x * 0.5 + off), 0,
		c.y + (t - 0.5) * dr.size.y)


## Visual open-ground sampler that also keeps clear of the safehouse porch
## and the player start (both known: props_v2 runs after _layout_safehouse_info).
func _porch_safe_spot(margin := 2.0, keep_away := 8.0) -> Vector3:
	for _i in 200:
		var p := Vector3(_vrng.randf_range(-90, 90), 0,
			_vrng.randf_range(-90, 90))
		if _on_road(p, margin) or _point_in_lots(p, margin):
			continue
		if p.distance_to(player_start) < keep_away:
			continue
		if p.distance_to(safehouse_porch) < keep_away * 0.75:
			continue
		return p
	return Vector3(road_ns_x + 14.0, 0, road_ew_z - 14.0)


func _build_silhouettes() -> void:
	# Distant skyline + treeline so the horizon isn't empty. Unshaded dark
	# slabs outside the boundary; fog hazes them into the background.
	var root := Node3D.new()
	root.name = "Silhouettes"
	add_child(root)
	for i in 18:
		var a := TAU * float(i) / 18.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(118.0, 148.0)
		var bw := _rng.randf_range(8.0, 18.0)
		var bh := _rng.randf_range(9.0, 26.0)
		var p := Vector3(cos(a) * r, bh * 0.5 - 0.5, sin(a) * r)
		_box(root, Vector3(bw, bh, bw * 0.7), p, _m_silhouette, _rng.randf() * TAU)
	for i in 12:
		var a2 := TAU * float(i) / 12.0 + 0.26 + _rng.randf_range(-0.12, 0.12)
		var r2 := _rng.randf_range(112.0, 130.0)
		var th := _rng.randf_range(6.0, 11.0)
		var tp := Vector3(cos(a2) * r2, th * 0.5, sin(a2) * r2)
		_cyl(root, 0.05, 2.6, th, tp, _m_silhouette)


func _build_boundary() -> void:
	# Hard collision walls (invisible) + a VISIBLE overgrown barrier just
	# inside them: dense dark brush the player can see, so the map edge
	# reads as "impenetrable forest" instead of a magic wall. Fallen logs
	# and bush clumps (cosmetic _vrng) break up the silhouette.
	var h := MAP_HALF + 0.5
	var w := MAP_HALF * 2.0 + 16.0
	_solid(self, Vector3(w, 6, 1), Vector3(0, 3, -h))
	_solid(self, Vector3(w, 6, 1), Vector3(0, 3, h))
	_solid(self, Vector3(1, 6, w), Vector3(-h, 3, 0))
	_solid(self, Vector3(1, 6, w), Vector3(h, 3, 0))
	var bh := MAP_HALF - 1.2
	var bw := MAP_HALF * 2.0 - 2.0
	var root := Node3D.new()
	root.name = "EdgeBrush"
	add_child(root)
	# Four long brush walls (visual only — collision comes from the walls
	# 1.7m behind them, so the player stops right at the greenery).
	_box(root, Vector3(bw, 3.4, 2.6), Vector3(0, 1.7, -bh), _m_brushwall)
	_box(root, Vector3(bw, 3.4, 2.6), Vector3(0, 1.7, bh), _m_brushwall)
	_box(root, Vector3(2.6, 3.4, bw), Vector3(-bh, 1.7, 0), _m_brushwall)
	_box(root, Vector3(2.6, 3.4, bw), Vector3(bh, 1.7, 0), _m_brushwall)
	# Ragged top: bush clumps + fallen logs along the barrier (cosmetic).
	var per := int(bw / 4.0)
	for i in per:
		var t := -bw * 0.5 + float(i) * 4.0 + _vrng.randf_range(-1.5, 1.5)
		for sz in [-1.0, 1.0]:
			var bp := Vector3(t, 0, sz * (bh + _vrng.randf_range(-1.2, 1.2)))
			var bush := _sphere(root, _vrng.randf_range(1.1, 1.9), bp + Vector3(0, 2.6, 0), _m_brushwall, true)
			bush.scale.y = 0.8
			if _vrng.randf() < 0.4:
				var logm := _box(root, Vector3(_vrng.randf_range(2.0, 3.6), 0.5, 0.5),
					Vector3(t + _vrng.randf_range(-1.0, 1.0), 0.35, sz * (bh - 2.6)), _m_trunk_dark,
					_vrng.randf() * TAU)
				logm.rotation.z = _vrng.randf_range(-0.12, 0.12)
		for sx in [-1.0, 1.0]:
			var bp2 := Vector3(sx * (bh + _vrng.randf_range(-1.2, 1.2)), 0, t)
			var bush2 := _sphere(root, _vrng.randf_range(1.1, 1.9), bp2 + Vector3(0, 2.6, 0), _m_brushwall, true)
			bush2.scale.y = 0.8


## Minimap: road + gas-station footprints for the map (seeded layout data).
func get_road_rects() -> Array[Rect2]:
	return _road_rects


func get_gas_rect() -> Rect2:
	return _gas_rect


## ------------------------------------------------- v3 dressing / trim ----
# Quality pass part 2 (2026-10-02): denser exterior dressing, per-building
# trim, extra ground variation. ALL of these run at the very end of
# build_world and draw randomness ONLY from _drng (seeded from
# world_seed) — the layout (_rng), visual (_vrng), loot (_lrng) and chop
# (_crng) streams are never touched, so layout/interior hashes and every
# pre-existing placement are byte-identical to before.

## One shared MultiMesh commit helper for the v3 scatter.
func _add_dressing_mm(mesh: Mesh, xf: Array[Transform3D]) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## A point on a dirt-road rect (not the shoulder).
func _dirt_on_spot() -> Vector3:
	var dr := _dirt_rects[_drng.randi() % _dirt_rects.size()]
	var c := dr.get_center()
	var t := _drng.randf_range(-0.4, 0.4)
	if dr.size.x > dr.size.y:
		return Vector3(c.x + t * dr.size.x, 0,
			c.y + _drng.randf_range(-1.0, 1.0))
	return Vector3(c.x + _drng.randf_range(-1.0, 1.0), 0,
		c.y + t * dr.size.y)


## V3 set dressing: bus stop shelter, dumpsters behind commercial lots,
## newspaper boxes, bottles/cans (one MultiMesh), fallen branches, extra
## trash bags, dirt-road manhole covers.
func _build_dressing_v3() -> void:
	# Bus stop: shelter posts + roof + bench + sign pole at one curb.
	var bp := _curb_spot(true)
	if not _point_in_lots(bp, 1.5):
		_bus_stop(bp)
	# Dumpsters behind commercial buildings (deterministic per index).
	for bi in buildings.size():
		if _drng.randf() < 0.35:
			_dumpster(buildings[bi] as Dictionary)
	# Newspaper vending boxes on curb spots.
	for _i in 3:
		var np := _curb_spot(true)
		if _point_in_lots(np, 0.5):
			continue
		_newspaper_box(np)
	# Bottles/cans: small glass cylinders near curbs, one draw call.
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.045
	bmesh.bottom_radius = 0.05
	bmesh.height = 0.24
	bmesh.radial_segments = 6
	bmesh.material = _m_bottle
	var bxf: Array[Transform3D] = []
	var btries := 0
	while bxf.size() < 26 and btries < 200:
		btries += 1
		var cp := _curb_spot(true)
		var b := Basis(Vector3.UP, _drng.randf() * TAU)
		var y := 0.12
		if _drng.randf() < 0.6: # most are tipped over
			b = b * Basis(Vector3.RIGHT, PI * 0.5 + _drng.randf_range(-0.2, 0.2))
			y = 0.05
		bxf.append(Transform3D(b, cp + Vector3(0, y, 0)))
	_add_dressing_mm(bmesh, bxf)
	# Fallen branches on open ground.
	for _i in 8:
		var fp := _open_spot_visual(1.0)
		if fp.distance_to(player_start) < 6.0 \
				or fp.distance_to(safehouse_porch) < 6.0:
			continue
		var br := _box(self, Vector3(_drng.randf_range(1.2, 2.4), 0.09, 0.11),
			fp + Vector3(0, 0.06, 0), _m_branch, _drng.randf() * TAU)
		br.rotation.z = _drng.randf_range(-0.06, 0.06)
	# Tied trash bags on curbs.
	for _i in 8:
		var tp := _curb_spot(true)
		if _point_in_lots(tp, 0.5):
			continue
		var bag := _sphere(self, _drng.randf_range(0.28, 0.42),
			tp + Vector3(0, 0.22, 0), _m_trash)
		bag.scale.y = 0.72
	# Manhole covers on the dirt roads too.
	if not _dirt_rects.is_empty():
		var drain_mat := _std(Color(0.10, 0.10, 0.11), 0.7, 0.4)
		for _i in 4:
			var dp := _dirt_on_spot()
			_cyl(self, 0.40, 0.40, 0.022, dp + Vector3(0, 0.004, 0), drain_mat)


func _bus_stop(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _drng.randf() * TAU
	add_child(root)
	for px in [-1.6, 1.6]: # shelter posts
		_box(root, Vector3(0.12, 2.4, 0.12), Vector3(px, 1.2, 0), _m_pole)
	_box(root, Vector3(3.8, 0.10, 1.6), Vector3(0, 2.45, 0), _m_bench) # roof
	_box(root, Vector3(3.8, 0.35, 0.06), Vector3(0, 2.24, -0.77), _m_sign) # back board
	for bx in [-1.2, 0.0, 1.2]: # bench seat slats
		_box(root, Vector3(0.9, 0.07, 0.45), Vector3(bx, 0.55, 0), _m_bench)
	_box(root, Vector3(0.06, 2.2, 0.06), Vector3(2.4, 1.1, 0), _m_pole) # sign pole
	_box(root, Vector3(0.55, 0.35, 0.04), Vector3(2.4, 2.0, 0), _m_sign) # sign
	_solid(root, Vector3(3.9, 2.5, 1.7), Vector3(0, 1.25, 0))


func _dumpster(bd: Dictionary) -> void:
	var pos := bd["pos"] as Vector3
	var w := float(bd["w"])
	var d := float(bd["d"])
	var face := float(bd["face"])
	# Behind the building (opposite the door face), off to one side.
	var side := 1.0 if _drng.randf() < 0.5 else -1.0
	var p := pos + Vector3(side * (w * 0.5 + _drng.randf_range(2.0, 3.5)), 0,
		-face * (d * 0.5 + _drng.randf_range(1.5, 2.5)))
	if _on_road(p, 1.5) or _point_in_lots(p, 1.0):
		return
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _drng.randf() * TAU
	add_child(root)
	_box(root, Vector3(2.2, 1.15, 1.2), Vector3(0, 0.62, 0), _m_dumpster) # body
	_box(root, Vector3(2.24, 0.08, 1.24), Vector3(0, 1.24, 0), _m_dumpster) # lid
	_box(root, Vector3(2.24, 0.10, 0.12), Vector3(0, 1.30, 0.56), _m_trash) # lid lip
	for wx in [-0.85, 0.85]: # caster wheels
		for wz in [-0.45, 0.45]:
			_cyl(root, 0.09, 0.09, 0.12, Vector3(wx, 0.06, wz), _m_tire)
	_solid(root, Vector3(2.3, 1.4, 1.3), Vector3(0, 0.7, 0))


func _newspaper_box(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _drng.randf() * TAU
	add_child(root)
	_box(root, Vector3(0.55, 0.85, 0.45), Vector3(0, 0.55, 0), _m_newspaper)
	_box(root, Vector3(0.50, 0.28, 0.03), Vector3(0, 0.75, 0.24), _m_paper) # window
	_box(root, Vector3(0.59, 0.10, 0.49), Vector3(0, 1.02, 0), _m_newspaper) # cap


## V3 house trim: gutters + downspouts on every house, window boxes and
## door awnings on a seeded subset, side shutters where the facade missed
## them. Deterministic per building index via _drng.
func _build_house_trim_v2() -> void:
	for hi in houses.size():
		var hd := houses[hi] as Dictionary
		var root := hd["root"] as Node3D
		var w := float(hd["w"])
		var d := float(hd["d"])
		var face := float(hd["face"])
		# Wall height: the roof mesh sits at y == wall top.
		var roof_g := hd["roof"] as Node3D
		var h := 3.2
		if roof_g.get_child_count() > 0:
			h = (roof_g.get_child(0) as Node3D).position.y
		var shack := h < 3.0
		# Gutter along the front eave + downspouts at both front corners.
		_box(root, Vector3(w + 1.0, 0.12, 0.16),
			Vector3(0, h + 0.02, face * (d * 0.5 + 0.52)), _m_downspout)
		for cx in [-w * 0.5 + 0.15, w * 0.5 - 0.15]:
			_box(root, Vector3(0.10, h, 0.10),
				Vector3(cx, h * 0.5, face * (d * 0.5 + 0.55)), _m_downspout)
			_box(root, Vector3(0.10, 0.14, 0.30),
				Vector3(cx, 0.07, face * (d * 0.5 + 0.65)), _m_downspout) # foot
		if shack:
			continue # shacks stay rough: gutter only
		# Window boxes with weeds under the front windows (seeded subset).
		if _drng.randf() < 0.5:
			for wx in [-w * 0.28, w * 0.28]:
				_box(root, Vector3(1.3, 0.24, 0.34),
					Vector3(wx, 0.78, face * (d * 0.5 + 0.28)), _m_wood)
				for ti in 3:
					_sphere(root, _drng.randf_range(0.10, 0.16),
						Vector3(wx + float(ti - 1) * 0.36, 0.98,
							face * (d * 0.5 + 0.28)),
						_m_bush, true)
		# Door awning over a seeded subset of doors.
		if _drng.randf() < 0.42:
			var aw := _box(root, Vector3(2.2, 0.07, 1.15),
				Vector3(0, 2.72, face * (d * 0.5 + 0.62)), _m_awning)
			aw.rotation.x = face * -0.28
			_box(root, Vector3(2.2, 0.16, 0.07),
				Vector3(0, 2.52, face * (d * 0.5 + 1.14)),
				_m_awning_stripe) # valance
			for ax in [-0.95, 0.95]: # angled support arms
				var arm := _box(root, Vector3(0.06, 0.06, 1.0),
					Vector3(ax, 2.45, face * (d * 0.5 + 0.55)), _m_pole)
				arm.rotation.x = face * 0.5
		# Side shutters where the facade missed them.
		if _drng.randf() < 0.35:
			for sx in [-1.0, 1.0]:
				var wx2: float = float(sx) * (w * 0.5 + 0.19)
				for sz in [-1.02, 1.02]:
					_box(root, Vector3(0.06, 1.34, 0.52),
						Vector3(wx2, 1.7, sz), _m_shutter)


## V3 commercial trim: hanging blade signs, roof AC units, storefront
## awnings, facade gutters. Deterministic per building index via _drng.
## (Wall signs already exist in BuildingTypes — these are the
## perpendicular blade signs that read from down the street.)
func _build_commercial_trim_v2() -> void:
	for bi in buildings.size():
		var bd := buildings[bi] as Dictionary
		var spec := _building_specs[bi] as Dictionary
		var pos := bd["pos"] as Vector3
		var w := float(bd["w"])
		var d := float(bd["d"])
		var h := float(spec["h"])
		var face := float(bd["face"])
		var kind := String(bd["kind"])
		var root := Node3D.new()
		root.position = pos
		add_child(root)
		var fz := face * (d * 0.5)
		# Hanging blade sign: bracket arm from the facade, board hanging
		# perpendicular. Not on the police station (kept official). Offset
		# to the side so it never fights the central wall sign.
		if _drng.randf() < 0.55 and kind != "police":
			var side := 1.0 if _drng.randf() < 0.5 else -1.0
			var sx := side * _drng.randf_range(w * 0.22, w * 0.40)
			_box(root, Vector3(0.08, 0.08, 1.1),
				Vector3(sx, h - 0.7, fz + face * 0.55), _m_pole) # arm
			_box(root, Vector3(1.5, 0.65, 0.08),
				Vector3(sx, h - 1.15, fz + face * 1.0), _m_sign) # board
			_box(root, Vector3(0.05, 0.28, 0.05),
				Vector3(sx - 0.6, h - 0.82, fz + face * 1.0), _m_pole) # chain L
			_box(root, Vector3(0.05, 0.28, 0.05),
				Vector3(sx + 0.6, h - 0.82, fz + face * 1.0), _m_pole) # chain R
		# Storefront awning over the door (retail kinds).
		if _drng.randf() < 0.5 and (kind == "grocery" or kind == "corner"):
			var aw := _box(root, Vector3(3.0, 0.07, 1.3),
				Vector3(0, 2.85, fz + face * 0.75), _m_awning)
			aw.rotation.x = face * -0.30
			_box(root, Vector3(3.0, 0.18, 0.07),
				Vector3(0, 2.60, fz + face * 1.32), _m_awning_stripe)
		# Roof AC unit on the front parapet edge.
		if _drng.randf() < 0.6:
			var ax := _drng.randf_range(-w * 0.35, w * 0.35)
			_box(root, Vector3(0.9, 0.7, 0.9),
				Vector3(ax, h + 0.35, fz - face * 0.8), _m_ac)
			_box(root, Vector3(0.6, 0.12, 0.6),
				Vector3(ax, h + 0.76, fz - face * 0.8), _m_ac_dark)
		# Gutter + downspouts along the facade.
		_box(root, Vector3(w + 0.4, 0.12, 0.16),
			Vector3(0, h + 0.02, fz + face * 0.10), _m_downspout)
		for cx in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
			_box(root, Vector3(0.10, h, 0.10),
				Vector3(cx, h * 0.5, fz + face * 0.16), _m_downspout)


## V3 ground detail: more patch variety on the same patch materials (the
## field QA counts them), plus oil stains, leaf piles, grass tufts
## breaking through pavement, thin sidewalk cracks.
func _build_ground_detail_v2() -> void:
	# Extra patches: the patch materials/counts keep growing (field QA
	# counts _m_patch_dirt/_m_patch_dark/_m_patch_ash >= 30).
	var mats := [_m_patch_dirt, _m_patch_dark, _m_patch_ash]
	var placed := 0
	var tries := 0
	while placed < 18 and tries < 160:
		tries += 1
		var p := Vector3(_drng.randf_range(-88, 88), 0,
			_drng.randf_range(-88, 88))
		if _on_road(p, 1.5) or _point_in_lots(p, 1.0):
			continue
		if p.distance_to(player_start) < 5.0 \
				or p.distance_to(safehouse_porch) < 5.0:
			continue
		var s := _drng.randf_range(1.2, 3.0)
		_box(self, Vector3(s, 0.012, s * _drng.randf_range(0.5, 1.0)),
			Vector3(p.x, 0.018, p.z), mats[_drng.randi() % 3],
			_drng.randf_range(0.0, TAU))
		placed += 1
	# Oil stains on the asphalt.
	for _i in 10:
		var on_ew := _drng.randf() < 0.5
		var px := _drng.randf_range(-70, 70)
		var p2 := Vector3(px, 0, road_ew_z + _drng.randf_range(-3.0, 3.0)) \
			if on_ew else Vector3(road_ns_x + _drng.randf_range(-3.0, 3.0), 0, px)
		var s2 := _drng.randf_range(0.6, 1.3)
		_box(self, Vector3(s2, 0.012, s2 * _drng.randf_range(0.6, 1.0)),
			Vector3(p2.x, 0.006, p2.z), _m_oil, _drng.randf() * TAU)
	# Leaf piles against curbs.
	for _i in 5:
		var lp := _curb_spot(true)
		for _k in 2:
			var r := _drng.randf_range(0.14, 0.26)
			_sphere(self, r, lp + Vector3(_drng.randf_range(-0.4, 0.4),
				r * 0.4, _drng.randf_range(-0.4, 0.4)), _m_leafpile, true)
	# Grass tufts breaking through pavement: small tufts along curb edges.
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.02
	tuft.bottom_radius = 0.07
	tuft.height = 0.35
	tuft.radial_segments = 5
	tuft.material = _m_tuft
	var txf: Array[Transform3D] = []
	var ttries := 0
	while txf.size() < 40 and ttries < 300:
		ttries += 1
		var tp := _curb_spot(true)
		var s3 := _drng.randf_range(0.7, 1.3)
		txf.append(Transform3D(
			Basis(Vector3.UP, _drng.randf() * TAU).scaled(Vector3(s3, s3, s3)),
			tp + Vector3(0, 0.15, 0)))
	_add_dressing_mm(tuft, txf)
	# Thin cracks: dark slivers on the sidewalks.
	for _i in 14:
		var on_ew2 := _drng.randf() < 0.5
		var qx := _drng.randf_range(-60, 60)
		var qp := Vector3(qx, 0, road_ew_z + (5.0 if _drng.randf() < 0.5 else -5.0)) \
			if on_ew2 else Vector3(road_ns_x + (6.0 if _drng.randf() < 0.5 else -6.0), 0, qx)
		_box(self, Vector3(0.08, 0.012, _drng.randf_range(0.8, 2.0)),
			Vector3(qp.x, 0.008, qp.z), _m_asphalt_crack,
			_drng.randf_range(-0.3, 0.3))
