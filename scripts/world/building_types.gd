class_name BuildingTypes
extends RefCounted
## Seeded commercial buildings for LAST SHIFT: police station, hospital,
## grocery store, corner store, office tower, small offices.
## Pure layout/geometry logic — every node and material goes through the
## NeighborhoodBuilder bx_* API so the seeded world (and its hash) stays
## deterministic. Interiors (room partitions, shelf/desk spots, loot and
## zombie spawn positions) are drawn from the layout RNG: same seed gives
## the same building, different seeds shuffle the insides.

const POLICE := "police"
const HOSPITAL := "hospital"
const GROCERY := "grocery"
const CORNER := "corner"
const OFFICE_TALL := "office_tall"
const OFFICE_SMALL := "office_small"

const NAMES := {
	"police": "Police Station",
	"hospital": "Hospital",
	"grocery": "Grocery Store",
	"corner": "Corner Store",
	"office_tall": "Office Tower",
	"office_small": "Offices",
}

# kind -> Vector3(width, height, depth)
const DIMS := {
	"police": Vector3(14, 3.6, 10),
	"hospital": Vector3(18, 4.2, 12),
	"grocery": Vector3(16, 3.8, 10),
	"corner": Vector3(8, 3.2, 7),
	"office_tall": Vector3(12, 3.4, 12),
	"office_small": Vector3(10, 3.4, 8),
}

# Cached tinted materials for shelf goods / small props (shared per build).
var _good_mats: Dictionary = {}


static func kind_color(kind: String) -> Color:
	match kind:
		"police":
			return Color(0.25, 0.45, 0.90)
		"hospital":
			return Color(0.93, 0.93, 0.95)
		"grocery":
			return Color(0.30, 0.68, 0.35)
		"corner":
			return Color(0.88, 0.70, 0.25)
		"office_tall", "office_small":
			return Color(0.55, 0.60, 0.72)
	return Color(0.6, 0.6, 0.6)


static func kind_letter(kind: String) -> String:
	match kind:
		"police":
			return "P"
		"hospital":
			return "H"
		"grocery":
			return "G"
		"corner":
			return "C"
		"office_tall", "office_small":
			return "O"
	return "?"


## Which commercial kinds appear this run: police + hospital + grocery are
## fixed anchors, the fourth slot rotates between corner store and offices.
static func pick_kinds(rng: RandomNumberGenerator) -> Array:
	var fourth: String = [CORNER, OFFICE_TALL, OFFICE_SMALL][rng.randi() % 3]
	return [POLICE, HOSPITAL, GROCERY, fourth]


## Rejection-sample a free lot per kind. Returns spec dicts:
## {kind, pos, face, w, d, h}. Lots are registered on the builder so trees,
## props and cars never spawn inside a building.
func layout_lots(hood: NeighborhoodBuilder, kinds: Array) -> Array:
	var specs: Array = []
	var rng := hood.bx_rng()
	for kind in kinds:
		var dim: Vector3 = DIMS[kind]
		var spec := _place_lot(hood, rng, String(kind), dim)
		if not spec.is_empty():
			specs.append(spec)
	return specs


func _place_lot(hood: NeighborhoodBuilder, rng: RandomNumberGenerator,
		kind: String, dim: Vector3) -> Dictionary:
	for _attempt in 90:
		var x := rng.randf_range(-56.0, 56.0)
		var z := rng.randf_range(-56.0, 56.0)
		var p := Vector3(x, 0, z)
		var m := maxf(dim.x, dim.z) * 0.5 + 3.0
		if hood.bx_on_road(p, m + 4.0):
			continue
		var rect := Rect2(x - dim.x * 0.5 - 2.0, z - dim.z * 0.5 - 2.0,
			dim.x + 4.0, dim.z + 4.0)
		if not hood.bx_lot_free(rect):
			continue
		if hood.bx_point_in_lots(p, m + 2.0):
			continue
		hood.bx_add_lot(rect)
		# Face the east-west main road (all building doors sit on local +/-Z).
		var face := -signf(p.z - hood.road_ew_z)
		if face == 0.0:
			face = 1.0
		return {"kind": kind, "pos": p, "face": face,
			"w": dim.x, "d": dim.z, "h": dim.y}
	return {}


## Build every spec; registers entries on the builder:
## {pos, w, d, face, roof, door, kind, name}.
func build(hood: NeighborhoodBuilder, specs: Array) -> void:
	for spec in specs:
		var entry: Dictionary = {}
		match String(spec["kind"]):
			POLICE:
				entry = _build_police(hood, spec)
			HOSPITAL:
				entry = _build_hospital(hood, spec)
			GROCERY:
				entry = _build_grocery(hood, spec)
			CORNER:
				entry = _build_corner(hood, spec)
			OFFICE_TALL:
				entry = _build_office_tall(hood, spec)
			OFFICE_SMALL:
				entry = _build_office_small(hood, spec)
		if not entry.is_empty():
			hood.bx_register(entry)


# ---------------------------------------------------------------- helpers

func _good(hood: NeighborhoodBuilder, c: Color) -> Material:
	var k := c.to_html()
	if not _good_mats.has(k):
		_good_mats[k] = hood.bx_std(c, 0.9)
	return _good_mats[k] as Material


func _base(hood: NeighborhoodBuilder, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "bld_" + String(spec["kind"])
	root.position = spec["pos"]
	hood.add_child(root)
	return root


## Exterior walls with a door gap on the front face (local z = face * d/2).
## fd = front direction (+/-1), bd = back direction.
func _walls(hood: NeighborhoodBuilder, root: Node3D, face: float,
		w: float, d: float, h: float, t: float, wall_mat: Material,
		door_w := 1.7) -> void:
	var fz := face * d * 0.5
	var seg := (w - door_w) * 0.5
	var lintel := h - 2.5
	hood.bx_solid_box(root, Vector3(w, h, t), Vector3(0, h * 0.5, -fz), wall_mat)
	hood.bx_solid_box(root, Vector3(t, h, d), Vector3(-w * 0.5, h * 0.5, 0), wall_mat)
	hood.bx_solid_box(root, Vector3(t, h, d), Vector3(w * 0.5, h * 0.5, 0), wall_mat)
	hood.bx_solid_box(root, Vector3(seg, h, t),
		Vector3(-(door_w * 0.5 + seg * 0.5), h * 0.5, fz), wall_mat)
	hood.bx_solid_box(root, Vector3(seg, h, t),
		Vector3(door_w * 0.5 + seg * 0.5, h * 0.5, fz), wall_mat)
	hood.bx_solid_box(root, Vector3(door_w, lintel, t),
		Vector3(0, 2.5 + lintel * 0.5, fz), wall_mat)
	# Floor slab + foundation skirt.
	hood.bx_box(root, Vector3(w + 0.4, 0.12, d + 0.4), Vector3(0, 0.06, 0),
		hood.bx_mat("floor"))
	hood.bx_box(root, Vector3(w + 0.5, 0.5, d + 0.5), Vector3(0, -0.1, 0),
		hood.bx_mat("foundation"))


## Swinging door like the houses'. Returns the door dict consumed by HouseDoors.
func _door(hood: NeighborhoodBuilder, root: Node3D, face: float,
		d: float, t: float, locked: bool) -> Dictionary:
	var fz := face * d * 0.5
	var dw := 1.6
	var dh := 2.4
	var trim: Material = hood.bx_mat("trim")
	hood.bx_box(root, Vector3(dw + 0.24, 0.14, t + 0.12),
		Vector3(0, dh + 0.07, fz), trim)
	hood.bx_box(root, Vector3(0.14, dh + 0.1, t + 0.12),
		Vector3(-dw * 0.5 - 0.07, dh * 0.5, fz), trim)
	hood.bx_box(root, Vector3(0.14, dh + 0.1, t + 0.12),
		Vector3(dw * 0.5 + 0.07, dh * 0.5, fz), trim)
	var pivot := Node3D.new()
	pivot.position = Vector3(-dw * 0.5, 0, fz)
	root.add_child(pivot)
	var door_mat: Material = hood.bx_mat("door")
	var panel: Material = hood.bx_mat("door_panel")
	hood.bx_box(pivot, Vector3(dw - 0.06, dh, 0.09),
		Vector3(dw * 0.5 - 0.03, dh * 0.5, 0), door_mat)
	hood.bx_box(pivot, Vector3(dw * 0.5, dh * 0.45, 0.03),
		Vector3(dw * 0.5 - 0.03, dh * 0.62, 0.045), panel)
	hood.bx_box(pivot, Vector3(dw * 0.5, dh * 0.3, 0.03),
		Vector3(dw * 0.5 - 0.03, dh * 0.2, 0.045), panel)
	var blocker := hood.bx_solid(root, Vector3(dw, dh, t), Vector3(0, dh * 0.5, fz))
	# Doorway veil: dark quad just inside the doorway. Visible while the
	# player is outside so an open door never reveals the interior;
	# hidden when the player goes inside (see house_doors.gd).
	var veil := hood.bx_box(root, Vector3(dw - 0.08, dh - 0.08, 0.05),
		Vector3(0, dh * 0.5, fz - face * 0.06), hood.bx_mat("veil"))
	hood.bx_box(root, Vector3(dw + 0.8, 0.18, 1.2),
		Vector3(0, 0.09, fz + face * (t * 0.5 + 0.5)), hood.bx_mat("step"))
	return {"pivot": pivot, "blocker": blocker, "veil": veil,
		"pos": (root.position as Vector3) + Vector3(0, 0, fz),
		"open": false, "safehouse": false, "locked": locked}


## Flat commercial roof with parapet. Returned group hides when the player
## is inside (same contract as house roofs).
func _flat_roof(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, mat: Material, parapet := true) -> Node3D:
	var g := Node3D.new()
	root.add_child(g)
	hood.bx_box(g, Vector3(w + 0.5, 0.22, d + 0.5), Vector3(0, h + 0.11, 0), mat)
	if parapet:
		var ph := 0.5
		var pt := 0.25
		var py := h + 0.22 + ph * 0.5
		hood.bx_box(g, Vector3(w + 0.5, ph, pt), Vector3(0, py, -d * 0.5), mat)
		hood.bx_box(g, Vector3(w + 0.5, ph, pt), Vector3(0, py, d * 0.5), mat)
		hood.bx_box(g, Vector3(pt, ph, d + 0.5), Vector3(-w * 0.5, py, 0), mat)
		hood.bx_box(g, Vector3(pt, ph, d + 0.5), Vector3(w * 0.5, py, 0), mat)
	return g


## Sign board + Label3D facing `outward`.
func _sign(hood: NeighborhoodBuilder, root: Node3D, text: String, pos: Vector3,
		outward: Vector3, bw: float, bh: float, board: Color, ink: Color) -> void:
	hood.bx_box(root, Vector3(bw, bh, 0.18), pos, hood.bx_std(board, 0.85))
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.011
	l.modulate = ink
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = pos + outward * 0.12
	if absf(outward.z) > 0.5:
		l.rotation.y = 0.0 if outward.z > 0.0 else PI
	elif absf(outward.x) > 0.5:
		l.rotation.y = PI * 0.5 if outward.x > 0.0 else -PI * 0.5
	root.add_child(l)


## Barred window for the police station (bars sit proud of the glass).
func _barred_window(hood: NeighborhoodBuilder, root: Node3D,
		center: Vector3, outward: Vector3) -> void:
	hood.bx_box(root, Vector3(1.1, 0.9, 0.08), center, hood.bx_mat("window_dark"))
	var bar := hood.bx_std(Color(0.16, 0.16, 0.18), 0.5, 0.6)
	for i in 4:
		var bx := center + Vector3(-0.36 + 0.24 * i, 0, 0) + outward * 0.07
		hood.bx_box(root, Vector3(0.07, 0.9, 0.06), bx, bar)
	hood.bx_box(root, Vector3(1.1, 0.09, 0.06), center + outward * 0.07, bar)


func _desk(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, with_chair := true) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	var wood: Material = hood.bx_mat("wood")
	var dark: Material = hood.bx_mat("table")
	hood.bx_box(g, Vector3(1.6, 0.08, 0.8), Vector3(0, 0.74, 0), wood)
	for sx in [-0.7, 0.7]:
		for sz in [-0.3, 0.3]:
			hood.bx_box(g, Vector3(0.08, 0.74, 0.08), Vector3(sx, 0.37, sz), dark)
	if with_chair:
		hood.bx_box(g, Vector3(0.45, 0.08, 0.45), Vector3(0, 0.45, 0.75), dark)
		hood.bx_box(g, Vector3(0.45, 0.55, 0.08), Vector3(0, 0.75, 0.95), dark)


## Double-sided stocked shelf, 2.6 long (local X) x 1.7 tall x 0.7 deep.
func _shelf_unit(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, stocked: bool, rng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	var sm: Material = hood.bx_mat("shelf")
	hood.bx_solid_box(g, Vector3(2.6, 1.7, 0.7), Vector3(0, 0.85, 0), sm)
	hood.bx_box(g, Vector3(2.6, 1.7, 0.08), Vector3(0, 0.85, 0), sm)
	if not stocked:
		return
	var goods := [Color(0.75, 0.28, 0.20), Color(0.88, 0.72, 0.25),
		Color(0.30, 0.52, 0.80), Color(0.42, 0.70, 0.32), Color(0.80, 0.45, 0.20)]
	for si in 3:
		var y := 0.5 + 0.42 * si
		for gi in 6:
			if rng.randf() < 0.22:
				continue # looted gaps
			var gm := _good(hood, goods[rng.randi() % goods.size()])
			var gz := 0.14 if gi % 2 == 0 else -0.14
			hood.bx_box(g, Vector3(0.34, 0.30, 0.20),
				Vector3(-1.0 + 0.4 * gi, y, gz), gm)


func _bed(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, rng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_solid_box(g, Vector3(1.0, 0.35, 2.1), Vector3(0, 0.35, 0),
		hood.bx_mat("bed"))
	hood.bx_box(g, Vector3(0.9, 0.18, 1.9), Vector3(0, 0.60, 0),
		hood.bx_mat("bedding"))
	hood.bx_box(g, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.72, -0.7),
		hood.bx_std(Color(0.88, 0.87, 0.82), 0.95))
	var bc: Color = [Color(0.50, 0.60, 0.70), Color(0.60, 0.55, 0.50),
		Color(0.45, 0.55, 0.45)][rng.randi() % 3]
	hood.bx_box(g, Vector3(0.92, 0.06, 1.0), Vector3(0, 0.68, 0.4),
		_good(hood, bc))


## Holding cell: side partitions + barred front facing `face_dir` (+/-1 in z).
func _cell(hood: NeighborhoodBuilder, root: Node3D, cx: float, cz: float,
		cw: float, cd: float, face_dir: float) -> void:
	var bar := hood.bx_std(Color(0.18, 0.18, 0.20), 0.5, 0.6)
	var wallm := hood.bx_std(Color(0.45, 0.46, 0.48), 0.9)
	var t := 0.15
	hood.bx_solid_box(root, Vector3(t, 2.4, cd), Vector3(cx - cw * 0.5, 1.2, cz), wallm)
	hood.bx_solid_box(root, Vector3(t, 2.4, cd), Vector3(cx + cw * 0.5, 1.2, cz), wallm)
	var fz := cz + face_dir * cd * 0.5
	var n := 6
	for i in n + 1:
		var bx := cx - cw * 0.5 + cw * i / n
		hood.bx_box(root, Vector3(0.08, 2.4, 0.08), Vector3(bx, 1.2, fz), bar)
	hood.bx_box(root, Vector3(cw, 0.10, 0.10), Vector3(cx, 2.32, fz), bar)
	hood.bx_box(root, Vector3(cw, 0.10, 0.10), Vector3(cx, 0.55, fz), bar)
	hood.bx_box(root, Vector3(cw - 0.4, 0.10, 0.5),
		Vector3(cx, 0.50, cz - face_dir * cd * 0.22), hood.bx_mat("wood"))


func _entry(spec: Dictionary, roof_g: Node3D, door: Dictionary) -> Dictionary:
	return {"pos": spec["pos"], "w": spec["w"], "d": spec["d"],
		"face": spec["face"], "roof": roof_g, "door": door,
		"kind": String(spec["kind"]), "name": String(NAMES[spec["kind"]])}


# ------------------------------------------------------------ police

func _build_police(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"]
	var face: float = spec["face"]
	var fd := face
	var bd := -face
	_walls(hood, root, face, w, d, h, 0.35,
		hood.bx_std(Color(0.38, 0.44, 0.52), 0.9))
	var roof_g := _flat_roof(hood, root, w, d, h,
		hood.bx_std(Color(0.25, 0.26, 0.28), 0.95))
	hood.bx_box(roof_g, Vector3(1.0, 0.7, 0.8), Vector3(3, h + 0.6, -2),
		hood.bx_mat("pole")) # rooftop AC unit
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.35, true) # LOCKED: needs key/lockpick
	_sign(hood, root, "POLICE", Vector3(0, h - 0.65, fz + fd * 0.25),
		Vector3(0, 0, fd), 6.0, 1.1, Color(0.10, 0.16, 0.35), Color(0.95, 0.96, 1.0))
	for wx in [-4.2, 4.2]:
		_barred_window(hood, root, Vector3(wx, 1.9, fz + fd * 0.06), Vector3(0, 0, fd))
	_barred_window(hood, root, Vector3(0, 1.9, -fz - fd * 0.06), Vector3(0, 0, -fd))
	# Holding cells: two cells along the back wall, left or right side.
	var cell_side := -1.0 if rng.randf() < 0.5 else 1.0
	var cw := 2.6
	var cd := 2.4
	var cz := bd * (d * 0.5 - 0.35 - cd * 0.5)
	var cx0 := cell_side * (w * 0.5 - 0.35 - cw * 0.5)
	for ci in 2:
		_cell(hood, root, cx0 - cell_side * ci * cw, cz, cw, cd, fd)
	# Front desk counter + a desk behind it (seeded x offset).
	var dx := rng.randf_range(-2.0, 2.0)
	var dz := fd * (d * 0.5 - 3.0)
	hood.bx_solid_box(root, Vector3(3.0, 1.0, 0.8), Vector3(dx, 0.5, dz),
		hood.bx_mat("counter"))
	_desk(hood, root, Vector3(dx * 0.5, 0, fd * (d * 0.5 - 5.2)),
		rng.randf_range(-0.3, 0.3))
	# Armory: back corner opposite the cells, tall gun locker.
	var arm_side := -cell_side
	var ax := arm_side * (w * 0.5 - 1.6)
	var az := bd * (d * 0.5 - 1.4)
	hood.bx_solid_box(root, Vector3(1.4, 2.2, 0.7), Vector3(ax, 1.1, az),
		hood.bx_std(Color(0.16, 0.18, 0.16), 0.6, 0.3))
	_sign(hood, root, "ARMORY", Vector3(ax, 2.55, az + fd * 0.4),
		Vector3(0, 0, fd), 1.7, 0.42, Color(0.12, 0.12, 0.12), Color(0.90, 0.85, 0.60))
	# Loot: armory (inert Phase-B firearms/ammo) + lobby desk.
	hood.bx_add_loot(root.position + Vector3(ax, 0.6, az + fd * 0.9),
		[["rifle", 1], ["ammo", 2], ["scrap", 2]])
	hood.bx_add_loot(root.position + Vector3(dx, 0.6, dz + fd * 0.9),
		[["cloth", 2], ["water", 1]])
	# Brutes: one pacing the cell block, one guarding the armory.
	hood.bx_brute(root.position + Vector3(cx0 - cell_side * cw * 0.5, 0.3,
		cz + fd * (cd * 0.5 + 0.8)))
	hood.bx_brute(root.position + Vector3(ax, 0.3, az + fd * 1.8))
	hood.bx_track_interior("police|cells=%.0f|desk=%.1f|arm=%.0f"
		% [cell_side, dx, arm_side])
	return _entry(spec, roof_g, door)


# ------------------------------------------------------------ hospital

func _build_hospital(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"]
	var face: float = spec["face"]
	var fd := face
	var bd := -face
	_walls(hood, root, face, w, d, h, 0.35,
		hood.bx_std(Color(0.80, 0.80, 0.78), 0.9))
	var roof_g := _flat_roof(hood, root, w, d, h,
		hood.bx_std(Color(0.55, 0.30, 0.28), 0.95))
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.35, false)
	var crossm := hood.bx_std(Color(0.75, 0.12, 0.12), 0.8)
	# Red cross emblem + HOSPITAL sign on the front.
	var ex := -w * 0.25
	hood.bx_box(root, Vector3(1.6, 0.5, 0.15), Vector3(ex, h - 0.7, fz + fd * 0.2), crossm)
	hood.bx_box(root, Vector3(0.5, 1.6, 0.15), Vector3(ex, h - 0.7, fz + fd * 0.2), crossm)
	_sign(hood, root, "HOSPITAL", Vector3(w * 0.14, h - 0.7, fz + fd * 0.25),
		Vector3(0, 0, fd), 5.2, 1.0, Color(0.92, 0.92, 0.94), Color(0.70, 0.10, 0.10))
	for wx in [-6.0, -3.0, 3.0, 6.0]:
		hood.bx_window(root, Vector3(wx, 2.2, fz + fd * 0.05), Vector3(0, 0, fd), false)
	# Lobby: reception counter + waiting chairs.
	var cz := fd * (d * 0.5 - 2.6)
	hood.bx_solid_box(root, Vector3(4.0, 1.0, 0.9), Vector3(0, 0.5, cz),
		hood.bx_mat("counter"))
	for ci in 4:
		var chx := -3.0 + 1.6 * ci
		hood.bx_box(root, Vector3(0.55, 0.08, 0.55),
			Vector3(chx, 0.45, cz + fd * 2.2), hood.bx_mat("table"))
		hood.bx_box(root, Vector3(0.55, 0.60, 0.08),
			Vector3(chx, 0.75, cz + fd * 2.45), hood.bx_mat("table"))
	# Wards: two seeded partition layouts at the back.
	var preset := rng.randi() % 2
	var ward_z := bd * (d * 0.5 - 3.4)
	if preset == 0:
		hood.bx_solid_box(root, Vector3(0.2, h - 0.4, 5.0),
			Vector3(0, (h - 0.4) * 0.5, ward_z), hood.bx_mat("inner"))
		_bed(hood, root, Vector3(-w * 0.25, 0, ward_z), 0.0, rng)
		_bed(hood, root, Vector3(w * 0.25, 0, ward_z), 0.0, rng)
	else:
		_bed(hood, root, Vector3(-w * 0.25, 0, ward_z - 1.0), 0.2, rng)
		_bed(hood, root, Vector3(w * 0.25, 0, ward_z + 1.0), -0.2, rng)
		_bed(hood, root, Vector3(0.5, 0, ward_z - 1.6), -0.1, rng)
	# Medicine cabinets on the back wall: shelf + red cross, searchable.
	for csi in 2:
		var sx := -2.5 + 5.0 * csi
		var sz := bd * (d * 0.5 - 0.6)
		hood.bx_box(root, Vector3(1.2, 0.9, 0.35), Vector3(sx, 1.7, sz),
			hood.bx_mat("shelf"))
		hood.bx_box(root, Vector3(0.5, 0.16, 0.05),
			Vector3(sx, 1.7, sz + fd * 0.2), crossm)
		hood.bx_box(root, Vector3(0.16, 0.5, 0.05),
			Vector3(sx, 1.7, sz + fd * 0.2), crossm)
		var items := [["medicine", 2], ["bandage", 1]] if csi == 0 \
			else [["medicine", 1], ["bandage", 2]]
		hood.bx_add_loot(root.position + Vector3(sx, 0.6, sz + fd * 0.9), items)
	hood.bx_add_loot(root.position + Vector3(2.8, 0.6, cz + fd * 0.9),
		[["cloth", 2], ["scrap", 1]])
	# The wards are overrun: regular zombies inside.
	for zi in 3:
		hood.bx_zombie(root.position + Vector3(
			rng.randf_range(-w * 0.3, w * 0.3), 0.3,
			ward_z + rng.randf_range(-1.5, 1.5)))
	hood.bx_track_interior("hospital|preset=%d" % preset)
	return _entry(spec, roof_g, door)


# ------------------------------------------------------------ grocery

func _build_grocery(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"]
	var face: float = spec["face"]
	var fd := face
	_walls(hood, root, face, w, d, h, 0.35,
		hood.bx_std(Color(0.72, 0.68, 0.60), 0.9))
	var roof_g := _flat_roof(hood, root, w, d, h,
		hood.bx_std(Color(0.30, 0.30, 0.32), 0.95))
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.35, false)
	_sign(hood, root, "GROCERY", Vector3(0, h - 0.6, fz + fd * 0.25),
		Vector3(0, 0, fd), 5.0, 1.0, Color(0.12, 0.35, 0.16), Color(0.95, 1.0, 0.90))
	# Storefront glass panes flanking the door (proud of the wall).
	var glassm: Material = hood.bx_mat("glass")
	var framem := hood.bx_std(Color(0.20, 0.22, 0.24), 0.7)
	for gx in [-5.4, -3.2, 3.2, 5.4]:
		hood.bx_box(root, Vector3(2.0, 1.7, 0.10),
			Vector3(gx, 1.75, fz + fd * 0.12), glassm)
		hood.bx_box(root, Vector3(2.15, 0.10, 0.12),
			Vector3(gx, 2.65, fz + fd * 0.12), framem)
		hood.bx_box(root, Vector3(2.15, 0.10, 0.12),
			Vector3(gx, 0.85, fz + fd * 0.12), framem)
	# Aisles: 3-4 stocked shelf rows running front-to-back, seeded x spots.
	var n_aisles := 3 + rng.randi() % 2
	var ax0 := -w * 0.5
	for ai in n_aisles:
		var ax := ax0 + (ai + 1) * (w / float(n_aisles + 1)) \
			+ rng.randf_range(-0.4, 0.4)
		_shelf_unit(hood, root, Vector3(ax, 0, -1.2), PI * 0.5, true, rng)
	# Checkout counter near the door.
	hood.bx_solid_box(root, Vector3(2.4, 1.0, 0.8),
		Vector3(2.8, 0.5, fd * (d * 0.5 - 2.2)), hood.bx_mat("counter"))
	# Loot: food-heavy aisle ends.
	hood.bx_add_loot(root.position + Vector3(-w * 0.25, 0.6, -3.4),
		[["canned_food", 2], ["water", 2]])
	hood.bx_add_loot(root.position + Vector3(w * 0.25, 0.6, -3.4),
		[["canned_food", 1], ["water", 1], ["cloth", 1]])
	# One shopper that never left.
	hood.bx_zombie(root.position + Vector3(
		rng.randf_range(-4.0, 4.0), 0.3, rng.randf_range(-3.0, 0.0)))
	hood.bx_track_interior("grocery|aisles=%d" % n_aisles)
	return _entry(spec, roof_g, door)


# ------------------------------------------------------------ corner store

func _build_corner(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"]
	var face: float = spec["face"]
	var fd := face
	var bd := -face
	_walls(hood, root, face, w, d, h, 0.3,
		hood.bx_std(Color(0.66, 0.58, 0.48), 0.9))
	var roof_g := _flat_roof(hood, root, w, d, h,
		hood.bx_std(Color(0.28, 0.27, 0.26), 0.95))
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.3, false)
	_sign(hood, root, "CORNER STORE", Vector3(0, h - 0.55, fz + fd * 0.22),
		Vector3(0, 0, fd), 4.6, 0.9, Color(0.45, 0.20, 0.10), Color(1.0, 0.95, 0.85))
	for wx in [-2.2, 2.2]:
		hood.bx_window(root, Vector3(wx, 1.8, fz + fd * 0.05), Vector3(0, 0, fd), false)
	# Two shelf walls + a cooler at the back.
	_shelf_unit(hood, root, Vector3(-w * 0.5 + 0.7, 0, 0.4), PI * 0.5, true, rng)
	_shelf_unit(hood, root, Vector3(w * 0.5 - 0.7, 0, -0.4), PI * 0.5, true, rng)
	var cooler_z := bd * (d * 0.5 - 0.9)
	hood.bx_solid_box(root, Vector3(2.4, 1.8, 0.8),
		Vector3(0.6, 0.9, cooler_z), hood.bx_std(Color(0.85, 0.86, 0.88), 0.6))
	hood.bx_box(root, Vector3(2.0, 1.2, 0.08),
		Vector3(0.6, 1.1, cooler_z + fd * 0.42), hood.bx_mat("glass"))
	# Counter by the door.
	hood.bx_solid_box(root, Vector3(1.8, 1.0, 0.7),
		Vector3(-1.6, 0.5, fd * (d * 0.5 - 1.8)), hood.bx_mat("counter"))
	# Quick-access mixed loot, including one rare medicine outside hospitals.
	hood.bx_add_loot(root.position + Vector3(0.6, 0.6, cooler_z + fd * 1.1),
		[["canned_food", 1], ["water", 2], ["medicine", 1]])
	hood.bx_add_loot(root.position + Vector3(-1.6, 0.6, fd * (d * 0.5 - 0.9)),
		[["scrap", 1], ["cloth", 1]])
	hood.bx_track_interior("corner|v=1")
	return _entry(spec, roof_g, door)


# ------------------------------------------------------------ office tower

func _build_office_tall(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"] # ground-floor height; tower rises above
	var face: float = spec["face"]
	var fd := face
	var bd := -face
	var wallm := hood.bx_std(Color(0.62, 0.62, 0.64), 0.9)
	_walls(hood, root, face, w, d, h, 0.35, wallm)
	# Ground-floor ceiling stays when the player is inside.
	hood.bx_box(root, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, h + 0.1, 0),
		hood.bx_mat("inner"))
	# Tower mass above (hidden with the roof group when inside).
	var roof_g := Node3D.new()
	root.add_child(roof_g)
	var upper_h := 6.6
	hood.bx_box(roof_g, Vector3(w, upper_h, d),
		Vector3(0, h + 0.2 + upper_h * 0.5, 0), wallm)
	for fi in 3:
		var wy := h + 1.3 + fi * 1.9
		for wx in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			hood.bx_box(roof_g, Vector3(1.3, 1.1, 0.10),
				Vector3(wx, wy, d * 0.5 + 0.06), hood.bx_mat("window_dark"))
			hood.bx_box(roof_g, Vector3(1.3, 1.1, 0.10),
				Vector3(wx, wy, -d * 0.5 - 0.06), hood.bx_mat("window_dark"))
	hood.bx_box(roof_g, Vector3(w + 0.4, 0.25, d + 0.4),
		Vector3(0, h + 0.2 + upper_h + 0.12, 0),
		hood.bx_std(Color(0.35, 0.35, 0.37), 0.95))
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.35, false)
	_sign(hood, root, "OFFICES", Vector3(0, h - 0.5, fz + fd * 0.25),
		Vector3(0, 0, fd), 4.2, 0.9, Color(0.18, 0.22, 0.30), Color(0.90, 0.92, 0.95))
	hood.bx_window(root, Vector3(-3.4, 1.8, fz + fd * 0.05), Vector3(0, 0, fd), false)
	hood.bx_window(root, Vector3(3.4, 1.8, fz + fd * 0.05), Vector3(0, 0, fd), false)
	# Lobby: reception desk, side offices with desks.
	hood.bx_solid_box(root, Vector3(3.2, 1.0, 0.9),
		Vector3(0, 0.5, fd * (d * 0.5 - 2.4)), hood.bx_mat("counter"))
	_desk(hood, root, Vector3(-w * 0.28, 0, bd * 1.5), rng.randf_range(-0.4, 0.4))
	_desk(hood, root, Vector3(w * 0.28, 0, bd * 1.5), rng.randf_range(-0.4, 0.4))
	hood.bx_solid_box(root, Vector3(0.2, h - 0.4, 4.0),
		Vector3(-w * 0.14, (h - 0.4) * 0.5, bd * 2.5), hood.bx_mat("inner"))
	hood.bx_solid_box(root, Vector3(0.2, h - 0.4, 4.0),
		Vector3(w * 0.14, (h - 0.4) * 0.5, bd * 2.5), hood.bx_mat("inner"))
	# Stairwell: blocked by a rubble pile.
	var stx := 0.0
	var stz := bd * (d * 0.5 - 0.8)
	for ri in 5:
		hood.bx_box(root, Vector3(0.7, 0.5, 0.6),
			Vector3(stx + rng.randf_range(-0.8, 0.8), 0.25 + 0.3 * (ri % 2),
				stz + rng.randf_range(-0.5, 0.5)),
			hood.bx_std(Color(0.42, 0.40, 0.38), 0.95),
			rng.randf_range(0.0, 1.2))
	# Crafting supplies / scrap + a little food.
	hood.bx_add_loot(root.position + Vector3(-w * 0.28, 0.6, bd * 0.6),
		[["scrap", 2], ["cloth", 1]])
	hood.bx_add_loot(root.position + Vector3(w * 0.28, 0.6, bd * 0.6),
		[["water", 1], ["canned_food", 1]])
	# One office worker still at their desk.
	hood.bx_zombie(root.position + Vector3(
		rng.randf_range(-3.0, 3.0), 0.3, bd * rng.randf_range(1.0, 3.0)))
	hood.bx_track_interior("office_tall|v=1")
	return _entry(spec, roof_g, door)


# ------------------------------------------------------------ small offices

func _build_office_small(hood: NeighborhoodBuilder, spec: Dictionary) -> Dictionary:
	var rng := hood.bx_rng()
	var root := _base(hood, spec)
	var w: float = spec["w"]
	var d: float = spec["d"]
	var h: float = spec["h"]
	var face: float = spec["face"]
	var fd := face
	var bd := -face
	_walls(hood, root, face, w, d, h, 0.3,
		hood.bx_std(Color(0.68, 0.64, 0.58), 0.9))
	var roof_g := _flat_roof(hood, root, w, d, h,
		hood.bx_std(Color(0.30, 0.30, 0.32), 0.95))
	var fz := face * d * 0.5
	var door := _door(hood, root, face, d, 0.3, false)
	_sign(hood, root, "OFFICES", Vector3(0, h - 0.5, fz + fd * 0.22),
		Vector3(0, 0, fd), 3.6, 0.8, Color(0.20, 0.24, 0.32), Color(0.90, 0.92, 0.95))
	for wx in [-2.6, 2.6]:
		hood.bx_window(root, Vector3(wx, 1.8, fz + fd * 0.05), Vector3(0, 0, fd), false)
	# Cubicle pods: two seeded partition layouts.
	var preset := rng.randi() % 2
	var ph := 1.5
	if preset == 0:
		hood.bx_solid_box(root, Vector3(3.6, ph, 0.15),
			Vector3(-1.4, ph * 0.5, bd * 1.2), hood.bx_mat("inner"))
		hood.bx_solid_box(root, Vector3(0.15, ph, 2.4),
			Vector3(-1.4, ph * 0.5, bd * 2.2), hood.bx_mat("inner"))
		hood.bx_solid_box(root, Vector3(3.6, ph, 0.15),
			Vector3(1.8, ph * 0.5, bd * 2.0), hood.bx_mat("inner"))
	else:
		hood.bx_solid_box(root, Vector3(0.15, ph, 3.2),
			Vector3(0, ph * 0.5, bd * 1.8), hood.bx_mat("inner"))
		hood.bx_solid_box(root, Vector3(3.0, ph, 0.15),
			Vector3(-1.6, ph * 0.5, bd * 1.4), hood.bx_mat("inner"))
		hood.bx_solid_box(root, Vector3(3.0, ph, 0.15),
			Vector3(1.6, ph * 0.5, bd * 2.4), hood.bx_mat("inner"))
	_desk(hood, root, Vector3(-2.0, 0, bd * 1.6), rng.randf_range(-0.5, 0.5))
	_desk(hood, root, Vector3(1.6, 0, bd * 2.4), rng.randf_range(-0.5, 0.5))
	_desk(hood, root, Vector3(0.2, 0, fd * 1.8), rng.randf_range(-0.5, 0.5))
	hood.bx_add_loot(root.position + Vector3(-2.0, 0.6, bd * 0.8),
		[["scrap", 3]])
	hood.bx_add_loot(root.position + Vector3(1.6, 0.6, bd * 1.6),
		[["cloth", 2], ["water", 1]])
	hood.bx_track_interior("office_small|preset=%d" % preset)
	return _entry(spec, roof_g, door)
