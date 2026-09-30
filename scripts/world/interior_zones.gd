class_name InteriorZones
extends Node3D
## Hidden interior zones: "a compound on the inside, a house on the
## outside" (Tbandz's direction). Police, hospital, warehouse, office_tall
## and office_small exteriors are hollow shells; the real interiors live in
## these zones at a deterministic far offset (1200 + zi*500, 0, 1200),
## connected to the real doors by teleport trigger pairs.
##
## Design contract:
## - Exterior footprint, door position and look are UNCHANGED. The shell
##   keeps walls, roof, door + blocker, sign, windows, veil. The player is
##   never inside the footprint, so the roof just stays on (correct).
## - Zone root starts visible=false; shown while the player or any living
##   zombie is inside (perf: zones are never rendered from the map).
## - No roof on zones (open top, like current interiors when the roof
##   lifts); walls at normal height so the angled camera sees in.
## - NO extra lights per room (iPhone perf): one emissive EXIT sign per
##   zone for night readability, shared materials otherwise.
## - Seeded determinism: zone origins + layouts draw from hood.bx_rng()
##   AFTER all existing world-gen streams are done, so nothing existing
##   shifts. No randomize() anywhere.
## - Multi-floor seam (NOT this phase): zone records are
##   {building_index, kind, zone_root, entry/exit triggers + spawn
##   transforms, bounds}. A later pass can add more zones per building
##   keyed by floor (add a "floor" field; triggers/director already key
##   off records, not globals).

const ZONE_BASE := Vector3(1200.0, 0.0, 1200.0)
const ZONE_STEP := 500.0
const ZONED_KINDS: Array[String] = ["police", "hospital", "warehouse",
	"office_tall", "office_small"]

# Zone footprint per kind (clearly bigger than the exterior footprint).
const ZONE_DIMS := {
	"police": Vector2(30.0, 22.0),
	"hospital": Vector2(34.0, 24.0),
	"warehouse": Vector2(28.0, 20.0),
	"office_tall": Vector2(26.0, 20.0),
	"office_small": Vector2(24.0, 18.0),
}

var zones: Array = [] # zone records (see _build_zone)

var _hood: NeighborhoodBuilder
var _player: PlayerController
var _zombies: ZombieManager
var _doors: HouseDoors
var _barricades: BarricadeManager
var _noise: NoiseBus
var _camera: CameraRig
var _exit_mat: StandardMaterial3D # shared emissive EXIT sign material
var _remit_guard := false # noise re-emit recursion guard
var _teleport_cd := {} # instance_id -> unix time: per-body trigger cooldown
const TELEPORT_COOLDOWN := 0.25 # seconds between teleports for one body


static func is_zoned_kind(kind: String) -> bool:
	return kind in ZONED_KINDS


## Build phase (called at the end of NeighborhoodBuilder.build_world, after
## every existing stream is done). Registers zone loot / brutes / walkers
## through the normal hood channels so container ids and spawn counts keep
## their existing meaning.
func build(hood: NeighborhoodBuilder) -> void:
	_hood = hood
	_exit_mat = StandardMaterial3D.new()
	_exit_mat.albedo_color = Color(0.05, 0.35, 0.12)
	_exit_mat.emission_enabled = true
	_exit_mat.emission = Color(0.15, 1.0, 0.35)
	_exit_mat.emission_energy_multiplier = 2.0
	var zi := 0
	for bi in hood.buildings.size():
		var bd := hood.buildings[bi] as Dictionary
		if not is_zoned_kind(String(bd["kind"])):
			continue
		_build_zone(hood, bi, bd, zi)
		zi += 1


## Runtime wiring (called from the main bootstrap after doors/barricades/
## zombies exist). Builder-only contexts (seed QA) skip this: triggers stay
## inert because _player is null.
func setup_runtime(p: PlayerController, zm: ZombieManager, doors: HouseDoors,
		bm: BarricadeManager, noise: NoiseBus, cam: CameraRig) -> void:
	_player = p
	_zombies = zm
	_doors = doors
	_barricades = bm
	_noise = noise
	_camera = cam
	if not _noise.noise_emitted.is_connected(_on_noise_bus):
		_noise.noise_emitted.connect(_on_noise_bus)


# ------------------------------------------------------------ mapping API ---

## Zone record containing pos (with a small margin), or {}.
func zone_at(pos: Vector3) -> Dictionary:
	for z in zones:
		var zd := z as Dictionary
		if (zd["bounds"] as Rect2).grow(0.6).has_point(Vector2(pos.x, pos.z)):
			return zd
	return {}


func kind_at(pos: Vector3) -> String:
	var z := zone_at(pos)
	return String(z.get("kind", "")) if not z.is_empty() else ""


## Minimap: zone coordinates map back to the building's exterior position.
func map_to_exterior(pos: Vector3) -> Vector3:
	var z := zone_at(pos)
	if z.is_empty():
		return pos
	var b := _hood.buildings[int(z["building"])] as Dictionary
	return b["pos"] as Vector3


## Wave loop: when the player is holed up in a zone, the wave spawns around
## the zone's exterior door (on the real map) and converges on it — never
## in the void around the zone offset.
func wave_anchor(pp: Vector3) -> Vector3:
	var z := zone_at(pp)
	if z.is_empty():
		return pp
	return z["door_pos"] as Vector3


# ------------------------------------------------------ trigger plumbing ---

func _make_trigger(parent: Node3D, local_pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.position = local_pos
	a.monitoring = true
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	parent.add_child(a)
	return a


## Exterior door -> zone. Gated: the real door must be OPEN (the closed
## blocker physically stops bodies first; this is belt and suspenders).
## Zombies also refuse a barricaded threshold.
func _on_enter_body(body: Node3D, zi: int) -> void:
	if _player == null:
		return
	var is_player := body.is_in_group("player")
	var is_zombie := body.is_in_group("zombie")
	if not (is_player or is_zombie):
		return
	# Per-body teleport cooldown: prevents trigger bounce.
	var now := Time.get_ticks_msec() / 1000.0
	if _teleport_cd.get(body.get_instance_id(), 0.0) > now:
		return
	_teleport_cd[body.get_instance_id()] = now + TELEPORT_COOLDOWN
	var zone := zones[zi] as Dictionary
	var b := _hood.buildings[int(zone["building"])] as Dictionary
	var door := b["door"] as Dictionary
	if not bool(door.get("open", false)):
		return
	if is_zombie and _barricades != null and _barricades.has_boards(
			BarricadeManager.key_for_building(int(zone["building"]))):
		return
	body.global_position = zone["spawn_in"] as Vector3
	if is_player:
		Sound.play_3d("door", zone["spawn_in"] as Vector3)
		if _camera != null:
			_camera.snap()
	(zone["root"] as Node3D).visible = true


## Zone door -> exterior. No door gate: walking out of the zone always
## lands you just outside the real door (facing outward, velocity kept).
func _on_exit_body(body: Node3D, zi: int) -> void:
	if _player == null:
		return
	var is_player := body.is_in_group("player")
	var is_zombie := body.is_in_group("zombie")
	if not (is_player or is_zombie):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _teleport_cd.get(body.get_instance_id(), 0.0) > now:
		return
	_teleport_cd[body.get_instance_id()] = now + TELEPORT_COOLDOWN
	var zone := zones[zi] as Dictionary
	body.global_position = zone["spawn_out"] as Vector3
	if is_player:
		Sound.play_3d("door", zone["spawn_out"] as Vector3)
		if _camera != null:
			_camera.snap()


# ---------------------------------------------------------- zombie director ---

func _physics_process(_delta: float) -> void:
	if _player == null or _zombies == null or zones.is_empty():
		return
	var pz := zone_at(_player.global_position)
	for z in _zombies.living_zombies():
		# Only pursuit states get steered; wanderers keep wandering.
		# Pounding zombies are left alone — the pound system owns them.
		if z.state != ZombieAI.State.CHASE and z.state != ZombieAI.State.SUSPICIOUS:
			z.has_steer_override = false
			continue
		var zp := z.global_position
		if _barricades != null and not _barricades.nearest_closed_door(
				zp, ZombieAI.POUND_RANGE).is_empty():
			z.has_steer_override = false
			continue
		var zz := zone_at(zp)
		if pz.is_empty():
			if zz.is_empty():
				z.has_steer_override = false
			else:
				# Player outside, zombie inside a zone: walk it to the
				# zone's exit door; the trigger carries it out.
				z.steer_override = zz["zone_door"] as Vector3
				z.has_steer_override = true
		else:
			if zz == pz:
				z.has_steer_override = false # already inside: chase normally
			elif zz.is_empty():
				# Player inside zone Z, zombie outside: converge on Z's
				# exterior door; the open-door trigger carries it in.
				z.steer_override = pz["door_pos"] as Vector3
				z.has_steer_override = true
			else:
				z.steer_override = zz["zone_door"] as Vector3
				z.has_steer_override = true
	# Zone visibility: a zone renders only while the player is inside it.
	# (Zones sit ~1.7km from the map, so nothing else can ever see one;
	# skipping the render when unoccupied is pure iPhone perf win.)
	for zr in zones:
		var zd := zr as Dictionary
		(zd["root"] as Node3D).visible = not pz.is_empty() and pz == zd


## Gunfire inside a zone should still pull the outside world in (the
## "gunshot noise attracts zombies" rule). Re-emit zone-internal noise at
## the zone's exterior door; zombies inside heard the original emission.
func _on_noise_bus(pos: Vector3, radius: float) -> void:
	if _remit_guard:
		return
	var z := zone_at(pos)
	if z.is_empty():
		return
	_remit_guard = true
	_noise.emit_noise(z["door_pos"] as Vector3, radius)
	_remit_guard = false

# ---------------------------------------------------------- zone building ---

func _build_zone(hood: NeighborhoodBuilder, bi: int, bd: Dictionary, zi: int) -> void:
	var kind := String(bd["kind"])
	var zdim: Vector2 = ZONE_DIMS[kind]
	var zw := zdim.x
	var zdep := zdim.y
	var h: float = (BuildingTypes.DIMS[kind] as Vector3).y
	var face := float(bd["face"])
	var origin := ZONE_BASE + Vector3(zi * ZONE_STEP, 0, 0)
	var root := Node3D.new()
	root.name = "zone_" + kind
	root.position = origin
	root.visible = false
	add_child(root)

	var wall_mat := hood.bx_std(_zone_wall_color(kind), 0.9)
	# Floor slab (solid: bodies stand on it) + a big dark apron so looking
	# out the zone door shows ground, not sky-void.
	hood.bx_solid_box(root, Vector3(zw + 0.6, 0.3, zdep + 0.6),
		Vector3(0, -0.1, 0), hood.bx_mat("floor"))
	hood.bx_box(root, Vector3(150.0, 0.1, 150.0), Vector3(0, -0.2, 0),
		hood.bx_std(Color(0.10, 0.12, 0.09), 1.0))
	_perimeter(hood, root, zw, zdep, h, 0.35, wall_mat, face)
	_entry_facade(hood, root, zdep, face)

	var door := bd["door"] as Dictionary
	var door_pos := door["pos"] as Vector3
	# Teleport destinations. spawn_in sits 2.2m inside the zone door —
	# clear of the exit trigger's volume (1.35m) plus a body radius, so
	# arrival never bounce-backs out. spawn_out lands 1.35m outside the
	# real door, clear of the entry trigger's outer edge.
	var spawn_in := origin + Vector3(0, 0.05, face * (zdep * 0.5 - 2.2))
	var spawn_out := door_pos + Vector3(0, 0.05, face * 1.35)
	var zone_door := origin + Vector3(0, 0, face * zdep * 0.5)

	# Exterior entry trigger: just INSIDE the real door plane, reachable
	# only through the open doorway.
	var broot := hood.get_node("bld_" + kind) as Node3D
	var d := float(bd["d"])
	var fz := face * d * 0.5
	var entry_trig := _make_trigger(broot, Vector3(0, 1.1, fz - face * 0.75),
		Vector3(1.6, 2.2, 1.2))
	entry_trig.body_entered.connect(_on_enter_body.bind(zi))
	# Zone exit trigger: just inside the zone door.
	var exit_trig := _make_trigger(root,
		Vector3(0, 1.1, face * (zdep * 0.5 - 0.75)), Vector3(1.6, 2.2, 1.2))
	exit_trig.body_entered.connect(_on_exit_body.bind(zi))

	zones.append({
		"index": zi, "kind": kind, "building": bi,
		"building_index": bi, "floor": 0, # multi-floor seams (single floor now)
		"origin": origin,
		"w": zw, "d": zdep, "h": h, "face": face, "root": root,
		"door_pos": door_pos, "spawn_in": spawn_in, "spawn_out": spawn_out,
		"zone_door": zone_door, "entry_trigger": entry_trig,
		"exit_trigger": exit_trig,
		"bounds": Rect2(origin.x - zw * 0.5, origin.z - zdep * 0.5, zw, zdep),
	})

	match kind:
		"police":
			_zone_police(hood, root, zw, zdep, h, face, origin)
		"hospital":
			_zone_hospital(hood, root, zw, zdep, h, face, origin)
		"warehouse":
			_zone_warehouse(hood, root, zw, zdep, h, face, origin)
		"office_tall":
			_zone_office(hood, root, zw, zdep, h, face, origin)
		"office_small":
			_zone_office_small(hood, root, zw, zdep, h, face, origin)


func _zone_wall_color(kind: String) -> Color:
	# Match the exterior shell so the compound reads as the same building.
	match kind:
		"police":
			return Color(0.38, 0.44, 0.52)
		"hospital":
			return Color(0.80, 0.80, 0.78)
		"warehouse":
			return Color(0.46, 0.48, 0.43)
		"office_tall":
			return Color(0.62, 0.62, 0.64)
		"office_small":
			return Color(0.68, 0.64, 0.58)
	return Color(0.6, 0.6, 0.6)


## Perimeter walls with a door gap on the entry face (local z = face*d/2),
## mirroring the exterior shell's doorway. No roof: open top like a
## roof-lifted interior.
func _perimeter(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, t: float, wall_mat: Material, face: float, door_w := 1.7) -> void:
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
	# Grime ring at the wall bases (same read as the exterior shells).
	var gout := 0.16
	hood.bx_box(root, Vector3(w + 0.08, 0.6, 0.06),
		Vector3(0, 0.45, -fz - face * gout), hood.bx_mat("grime"))
	hood.bx_box(root, Vector3(seg + 0.04, 0.6, 0.06),
		Vector3(-(door_w * 0.5 + seg * 0.5), 0.45, fz + face * gout),
		hood.bx_mat("grime"))
	hood.bx_box(root, Vector3(seg + 0.04, 0.6, 0.06),
		Vector3(door_w * 0.5 + seg * 0.5, 0.45, fz + face * gout),
		hood.bx_mat("grime"))


## Entry facade mirroring the exterior door's facing: trim frame, step, and
## an emissive EXIT sign (night wayfinding, no extra lights).
func _entry_facade(hood: NeighborhoodBuilder, root: Node3D, d: float,
		face: float) -> void:
	var fz := face * d * 0.5
	var dw := 1.6
	var dh := 2.4
	var trim: Material = hood.bx_mat("trim")
	hood.bx_box(root, Vector3(dw + 0.24, 0.14, 0.47),
		Vector3(0, dh + 0.07, fz), trim)
	hood.bx_box(root, Vector3(0.14, dh + 0.1, 0.47),
		Vector3(-dw * 0.5 - 0.07, dh * 0.5, fz), trim)
	hood.bx_box(root, Vector3(0.14, dh + 0.1, 0.47),
		Vector3(dw * 0.5 + 0.07, dh * 0.5, fz), trim)
	hood.bx_box(root, Vector3(dw + 0.8, 0.18, 1.2),
		Vector3(0, 0.09, fz + face * 0.68), hood.bx_mat("step"))
	# EXIT sign: emissive board + unshaded label, readable at night.
	var spos := Vector3(0, dh + 0.55, fz + face * 0.28)
	hood.bx_box(root, Vector3(1.7, 0.5, 0.12), spos, _exit_mat)
	var l := Label3D.new()
	l.text = "EXIT"
	l.font_size = 96
	l.pixel_size = 0.011
	l.modulate = Color(0.55, 1.0, 0.60)
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.shaded = false
	l.position = spos + Vector3(0, 0, face * 0.09)
	if face < 0.0:
		l.rotation.y = PI
	root.add_child(l)

# ------------------------------------------------------------ zone layouts ---

func _zone_police(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3) -> void:
	# Lobby -> cell block -> armory DEEP inside. ~2.5x the old footprint.
	var rng := hood.bx_rng()
	var fd := face
	# Lobby: reception counter + a desk behind it (entry lane |x|<1.5 kept
	# clear: the counter sits at |dx|=2).
	var dx := -2.0 if rng.randf() < 0.5 else 2.0
	hood.bx_furn(hood.bx_solid_box(root, Vector3(3.0, 1.0, 0.8),
		Vector3(dx, 0.5, fd * 8.0), hood.bx_mat("counter")))
	_zdesk(hood, root, Vector3(-dx * 0.5, 0, fd * 5.0), rng.randf_range(-0.3, 0.3))
	# Cell block: three holding cells along the left wall, barred fronts
	# facing the corridor.
	for ci in 3:
		_zcell(hood, root, -11.5 + ci * 2.8, -fd * 8.5, 2.6, 2.4, fd)
	# Armory: back-right corner, deep inside. Tall gun locker + sign.
	var ax := 11.0
	var az := -fd * 9.0
	hood.bx_furn(hood.bx_solid_box(root, Vector3(1.4, 2.2, 0.7),
		Vector3(ax, 1.1, az), hood.bx_std(Color(0.16, 0.18, 0.16), 0.6, 0.3)))
	hood.bx_box(root, Vector3(1.7, 0.42, 0.12), Vector3(ax, 2.55, az + fd * 0.4),
		hood.bx_std(Color(0.12, 0.12, 0.12), 0.85))
	var al := Label3D.new()
	al.text = "ARMORY"
	al.font_size = 96
	al.pixel_size = 0.011
	al.modulate = Color(0.90, 0.85, 0.60)
	al.outline_size = 10
	al.outline_modulate = Color(0, 0, 0, 0.9)
	al.position = Vector3(ax, 2.55, az + fd * 0.49)
	if fd < 0.0:
		al.rotation.y = PI
	root.add_child(al)
	# Loot: armory deep inside (working pistol + live 9mm), lobby desk.
	hood.bx_add_loot(origin + Vector3(ax, 0.6, az + fd * 0.9),
		[["rifle", 1], ["ammo", 2], ["pistol", 1], ["ammo_9mm", 12],
			["scrap", 2], ["lockpick", 1]])
	hood.bx_add_loot(origin + Vector3(dx, 0.6, fd * 8.9),
		[["cloth", 2], ["water", 1]])
	# Brutes: one pacing the cell block, one guarding the armory.
	hood.bx_brute(origin + Vector3(-8.7, 0.3, -fd * 5.5))
	hood.bx_brute(origin + Vector3(ax, 0.3, az + fd * 1.8))
	hood.bx_track_interior("zone|police|cells=3")


func _zone_hospital(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3) -> void:
	# Reception -> two ward bays at the back with beds + medicine cabinets.
	var rng := hood.bx_rng()
	var fd := face
	var crossm := hood.bx_std(Color(0.75, 0.12, 0.12), 0.8)
	# Reception counter + waiting chairs (chairs are non-solid visuals).
	hood.bx_furn(hood.bx_solid_box(root, Vector3(4.0, 1.0, 0.9),
		Vector3(0, 0.5, fd * 8.2), hood.bx_mat("counter")))
	for ci in 4:
		var chx := -4.5 + 3.0 * ci
		hood.bx_furn(hood.bx_box(root, Vector3(0.55, 0.08, 0.55),
			Vector3(chx, 0.45, fd * 6.0), hood.bx_mat("table")))
		hood.bx_furn(hood.bx_box(root, Vector3(0.55, 0.60, 0.08),
			Vector3(chx, 0.75, fd * 6.25), hood.bx_mat("table")))
	# Ward bays: two dividing walls make left/center/right bays at the back.
	for wx in [-5.5, 5.5]:
		hood.bx_furn(hood.bx_solid_box(root, Vector3(0.2, h - 0.4, 10.0),
			Vector3(wx, (h - 0.4) * 0.5, -fd * 6.0), hood.bx_mat("inner")))
	# Beds: 2 in ward A, 3 in ward B.
	_zbed(hood, root, Vector3(-11.0, 0, -fd * 8.0), 0.0)
	_zbed(hood, root, Vector3(-11.0, 0, -fd * 5.5), 0.0)
	_zbed(hood, root, Vector3(11.0, 0, -fd * 8.0), 0.0)
	_zbed(hood, root, Vector3(11.0, 0, -fd * 5.5), 0.0)
	_zbed(hood, root, Vector3(8.2, 0, -fd * 6.8), -0.2)
	# Medicine cabinets on the back wall, red cross, searchable.
	for csi in 2:
		var sx := -11.0 + 22.0 * csi
		var sz := -fd * 11.4
		hood.bx_box(root, Vector3(1.2, 0.9, 0.35), Vector3(sx, 1.7, sz),
			hood.bx_mat("shelf"))
		hood.bx_box(root, Vector3(0.5, 0.16, 0.05),
			Vector3(sx, 1.7, sz + fd * 0.2), crossm)
		hood.bx_box(root, Vector3(0.16, 0.5, 0.05),
			Vector3(sx, 1.7, sz + fd * 0.2), crossm)
		var items := [["medicine", 2], ["bandage", 1], ["health_kit", 1]] if csi == 0 \
			else [["medicine", 1], ["bandage", 2], ["painkillers", 1]]
		hood.bx_add_loot(origin + Vector3(sx, 0.6, sz + fd * 1.2), items, "firstaid")
	hood.bx_add_loot(origin + Vector3(2.8, 0.6, fd * 9.1),
		[["cloth", 2], ["scrap", 1]])
	# The wards are overrun: regular zombies inside.
	for zi in 3:
		hood.bx_zombie(origin + Vector3(
			[-9.0, 9.0, -12.0][zi], 0.3, -fd * [7.5, 6.5, 9.5][zi]))
	hood.bx_track_interior("zone|hospital|wards=2")


func _zone_warehouse(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3) -> void:
	# Big open storage: pallet + crate rows, shelf row along the back.
	var rng := hood.bx_rng()
	var fd := face
	var wood: Material = hood.bx_mat("wood")
	for ri in 2:
		for ci in 4:
			var cx := -9.0 + float(ci) * 6.0 + rng.randf_range(-0.2, 0.2)
			var cz := -fd * (3.5 + float(ri) * 4.0)
			hood.bx_furn(hood.bx_solid_box(root, Vector3(1.6, 0.14, 1.2),
				Vector3(cx, 0.07, cz), wood)) # pallet
			hood.bx_furn(hood.bx_solid_box(root, Vector3(1.3, 0.9, 1.0),
				Vector3(cx, 0.6, cz), wood)) # crate
			if rng.randf() < 0.5:
				hood.bx_furn(hood.bx_solid_box(root, Vector3(1.0, 0.7, 0.8),
					Vector3(cx + 0.1, 1.4, cz), wood)) # second crate
	# Shelf row along the back wall.
	for si in 3:
		_zshelf(hood, root, Vector3(-8.0 + 8.0 * si, 0, -fd * 8.5), 0.0, true, rng)
	# Loot: scrap-heavy; the guard's shotgun leans by the far shelves.
	hood.bx_add_loot(origin + Vector3(-6.0, 0.6, -fd * 5.5),
		[["scrap", 3], ["wood", 3]], "toolbox")
	hood.bx_add_loot(origin + Vector3(6.0, 0.6, -fd * 6.0),
		[["wood", 2], ["scrap", 2]])
	hood.bx_add_loot(origin + Vector3(0.0, 0.6, -fd * 9.3),
		[["shotgun", 1], ["shells", 6]])
	# One worker that never clocked out.
	hood.bx_zombie(origin + Vector3(2.0, 0.3, -fd * 4.5))
	hood.bx_track_interior("zone|warehouse|rows=2")


func _zone_office(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3) -> void:
	# Lobby -> cubicle floor. Stairwell rubble nods at the blocked stairs.
	var rng := hood.bx_rng()
	var fd := face
	hood.bx_furn(hood.bx_solid_box(root, Vector3(3.2, 1.0, 0.9),
		Vector3(4.5, 0.5, fd * 7.6), hood.bx_mat("counter")))
	var preset := rng.randi() % 2
	var ph := 1.5
	if preset == 0:
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.6, ph, 0.15),
			Vector3(-4.0, ph * 0.5, -fd * 5.0), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(0.15, ph, 2.4),
			Vector3(-4.0, ph * 0.5, -fd * 6.0), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.6, ph, 0.15),
			Vector3(4.5, ph * 0.5, -fd * 6.0), hood.bx_mat("inner")))
		_zdesk(hood, root, Vector3(-5.5, 0, -fd * 6.5), rng.randf_range(-0.5, 0.5))
		_zdesk(hood, root, Vector3(3.5, 0, -fd * 7.0), rng.randf_range(-0.5, 0.5))
		_zdesk(hood, root, Vector3(1.0, 0, -fd * 4.5), rng.randf_range(-0.5, 0.5))
	else:
		hood.bx_furn(hood.bx_solid_box(root, Vector3(0.15, ph, 3.2),
			Vector3(0.0, ph * 0.5, -fd * 6.0), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.0, ph, 0.15),
			Vector3(-4.5, ph * 0.5, -fd * 5.0), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.0, ph, 0.15),
			Vector3(4.5, ph * 0.5, -fd * 7.0), hood.bx_mat("inner")))
		_zdesk(hood, root, Vector3(-5.0, 0, -fd * 5.5), rng.randf_range(-0.5, 0.5))
		_zdesk(hood, root, Vector3(4.0, 0, -fd * 7.5), rng.randf_range(-0.5, 0.5))
		_zdesk(hood, root, Vector3(-1.0, 0, -fd * 3.5), rng.randf_range(-0.5, 0.5))
	# Stairwell: blocked by a rubble pile (visual, kept off the back wall).
	var rubble := hood.bx_std(Color(0.42, 0.40, 0.38), 0.95)
	for ri in 5:
		hood.bx_furn(hood.bx_box(root, Vector3(0.7, 0.5, 0.6),
			Vector3(rng.randf_range(-0.8, 0.8), 0.25 + 0.3 * (ri % 2),
				-fd * 8.8 + rng.randf_range(-0.6, 0.1)), rubble,
			rng.randf_range(0.0, 1.2)))
	hood.bx_add_loot(origin + Vector3(-6.0, 0.6, -fd * 4.5),
		[["scrap", 2], ["cloth", 1]], "duffel")
	hood.bx_add_loot(origin + Vector3(6.0, 0.6, -fd * 4.5),
		[["water", 1], ["canned_food", 1]])
	hood.bx_zombie(origin + Vector3(rng.randf_range(-4.0, 4.0), 0.3, -fd * 6.0))
	hood.bx_track_interior("zone|office_tall|preset=%d" % preset)


func _zone_office_small(hood: NeighborhoodBuilder, root: Node3D, w: float,
		d: float, h: float, face: float, origin: Vector3) -> void:
	# Lobby -> open bullpen with cubicle pods. Smaller compound than the
	# tower, but still ~5x the old 10x8 footprint.
	var rng := hood.bx_rng()
	var fd := face
	hood.bx_furn(hood.bx_solid_box(root, Vector3(2.6, 1.0, 0.9),
		Vector3(4.0, 0.5, fd * 6.6), hood.bx_mat("counter")))
	var preset := rng.randi() % 2
	var ph := 1.5
	if preset == 0:
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.2, ph, 0.15),
			Vector3(-3.5, ph * 0.5, -fd * 4.5), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(0.15, ph, 2.6),
			Vector3(-3.5, ph * 0.5, -fd * 5.5), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(3.2, ph, 0.15),
			Vector3(3.5, ph * 0.5, -fd * 5.5), hood.bx_mat("inner")))
	else:
		hood.bx_furn(hood.bx_solid_box(root, Vector3(0.15, ph, 3.0),
			Vector3(0.5, ph * 0.5, -fd * 5.0), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(2.8, ph, 0.15),
			Vector3(-4.0, ph * 0.5, -fd * 4.2), hood.bx_mat("inner")))
		hood.bx_furn(hood.bx_solid_box(root, Vector3(2.8, ph, 0.15),
			Vector3(4.5, ph * 0.5, -fd * 6.2), hood.bx_mat("inner")))
	_zdesk(hood, root, Vector3(-4.5, 0, -fd * 5.5), rng.randf_range(-0.5, 0.5))
	_zdesk(hood, root, Vector3(2.5, 0, -fd * 6.5), rng.randf_range(-0.5, 0.5))
	_zdesk(hood, root, Vector3(0.0, 0, -fd * 3.0), rng.randf_range(-0.5, 0.5))
	hood.bx_add_loot(origin + Vector3(-5.5, 0.6, -fd * 4.0),
		[["scrap", 2], ["cloth", 2]], "duffel")
	hood.bx_add_loot(origin + Vector3(5.5, 0.6, -fd * 4.0),
		[["water", 1], ["canned_food", 1]])
	hood.bx_zombie(origin + Vector3(rng.randf_range(-3.0, 3.0), 0.3, -fd * 6.0))
	hood.bx_track_interior("zone|office_small|preset=%d" % preset)


# ------------------------------------------------------- furniture helpers ---
# Compact local versions of the BuildingTypes furniture builders (kept
# private there on purpose). All tagged via bx_furn for the furniture QA.

var _zgood_mats: Dictionary = {}


func _zgood(hood: NeighborhoodBuilder, c: Color) -> Material:
	var k := c.to_html()
	if not _zgood_mats.has(k):
		_zgood_mats[k] = hood.bx_std(c, 0.9)
	return _zgood_mats[k] as Material


func _zdesk(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, with_chair := true) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	var wood: Material = hood.bx_mat("wood")
	var dark: Material = hood.bx_mat("table")
	hood.bx_box(g, Vector3(1.6, 0.08, 0.8), Vector3(0, 0.74, 0), wood)
	for sx in [-0.7, 0.7]:
		for sz in [-0.3, 0.3]:
			hood.bx_box(g, Vector3(0.08, 0.74, 0.08), Vector3(sx, 0.37, sz), dark)
	if with_chair:
		hood.bx_box(g, Vector3(0.45, 0.08, 0.45), Vector3(0, 0.45, 0.75), dark)
		hood.bx_box(g, Vector3(0.45, 0.55, 0.08), Vector3(0, 0.75, 0.95), dark)


func _zbed(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	hood.bx_solid_box(g, Vector3(1.0, 0.35, 2.1), Vector3(0, 0.35, 0),
		hood.bx_mat("bed"))
	hood.bx_box(g, Vector3(0.9, 0.18, 1.9), Vector3(0, 0.60, 0),
		hood.bx_mat("bedding"))
	hood.bx_box(g, Vector3(0.6, 0.12, 0.35), Vector3(0, 0.72, -0.7),
		hood.bx_std(Color(0.88, 0.87, 0.82), 0.95))
	hood.bx_box(g, Vector3(0.92, 0.06, 1.0), Vector3(0, 0.68, 0.4),
		_zgood(hood, Color(0.50, 0.60, 0.70)))


## Double-sided stocked shelf, 2.6 long (local X) x 1.7 tall x 0.7 deep.
func _zshelf(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, stocked: bool, rng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
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
			var gm := _zgood(hood, goods[rng.randi() % goods.size()])
			var gz := 0.14 if gi % 2 == 0 else -0.14
			hood.bx_box(g, Vector3(0.34, 0.30, 0.20),
				Vector3(-1.0 + 0.4 * gi, y, gz), gm)


## Holding cell: side partitions + barred front facing `face_dir` (+/-1 in z).
func _zcell(hood: NeighborhoodBuilder, root: Node3D, cx: float, cz: float,
		cw: float, cd: float, face_dir: float) -> void:
	var bar := hood.bx_std(Color(0.18, 0.18, 0.20), 0.5, 0.6)
	var wallm := hood.bx_std(Color(0.45, 0.46, 0.48), 0.9)
	var t := 0.15
	hood.bx_furn(hood.bx_solid_box(root, Vector3(t, 2.4, cd),
		Vector3(cx - cw * 0.5, 1.2, cz), wallm))
	hood.bx_furn(hood.bx_solid_box(root, Vector3(t, 2.4, cd),
		Vector3(cx + cw * 0.5, 1.2, cz), wallm))
	var fz := cz + face_dir * cd * 0.5
	var n := 6
	for i in n + 1:
		var bx := cx - cw * 0.5 + cw * i / n
		hood.bx_box(root, Vector3(0.08, 2.4, 0.08), Vector3(bx, 1.2, fz), bar)
	hood.bx_box(root, Vector3(cw, 0.10, 0.10), Vector3(cx, 2.32, fz), bar)
	hood.bx_box(root, Vector3(cw, 0.10, 0.10), Vector3(cx, 0.55, fz), bar)
	hood.bx_box(root, Vector3(cw - 0.4, 0.10, 0.5),
		Vector3(cx, 0.50, cz - face_dir * cd * 0.22), hood.bx_mat("wood"))
