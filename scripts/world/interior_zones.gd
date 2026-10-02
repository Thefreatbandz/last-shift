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
## - Lighting: one emissive EXIT sign per zone plus up to 2 warm
##   OmniLight3D lanterns per zone (no shadows, shared materials, ~9m
##   range). Zones only render while occupied, so the real-light cost
##   stays flat. Lantern flames/glass brighten at night via
##   set_night_factor(), called by the TimeManager.
## - Seeded determinism: zone origins + layouts draw from hood.bx_rng()
##   AFTER all existing world-gen streams are done, so nothing existing
##   shifts. Lantern placement uses its own dedicated RNG stream (seeded
##   from world_seed + zone index), so it draws nothing from bx_rng and
##   layout/interior hashes never shift. No randomize() anywhere.
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
var _hud = null # Hud; untyped so bare-runner QA can attach a stub
# Gun-findability (2026-10-02): one-time "POLICE STATION / ARMORY INSIDE"
# banner when the player first walks up to the locked police doors.
var _police_hint_shown := false
var _police_door_pos := Vector3.ZERO # exterior door of the police zone
var _has_police_door := false
const POLICE_HINT_RANGE := 15.0
var _exit_mat: StandardMaterial3D # shared emissive EXIT sign material
var _flame_mat: StandardMaterial3D # shared lantern flame (night-scaled emission)
var _lantern_glass_mat: StandardMaterial3D # shared warm glass (night-scaled)
var _lantern_frame_mat: StandardMaterial3D # shared dark lantern frame
var _lantern_lights: Array[OmniLight3D] = [] # real lights, cap 2 per zone
var _lantern_night := 0.0 # last night factor: 0 = day, 1 = deep night
var _surface_points: Array = [] # reset per zone: {pos, top, rot} from _zdesk/_zshelf
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
	# Lantern materials: one shared flame, one shared glass, one shared
	# frame for every lantern in every zone (iPhone perf). The night hook
	# scales flame/glass emission energy with the night factor.
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_color = Color(1.0, 0.55, 0.18)
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.48, 0.12)
	_flame_mat.emission_energy_multiplier = 0.9
	_lantern_glass_mat = StandardMaterial3D.new()
	_lantern_glass_mat.albedo_color = Color(0.78, 0.66, 0.50)
	_lantern_glass_mat.emission_enabled = true
	_lantern_glass_mat.emission = Color(1.0, 0.70, 0.42)
	_lantern_glass_mat.emission_energy_multiplier = 0.25
	_lantern_frame_mat = StandardMaterial3D.new()
	_lantern_frame_mat.albedo_color = Color(0.11, 0.10, 0.09)
	_lantern_frame_mat.roughness = 0.6
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
		bm: BarricadeManager, noise: NoiseBus, cam: CameraRig, hud) -> void:
	_player = p
	_zombies = zm
	_doors = doors
	_barricades = bm
	_noise = noise
	_camera = cam
	_hud = hud
	if not _noise.noise_emitted.is_connected(_on_noise_bus):
		_noise.noise_emitted.connect(_on_noise_bus)
	for zr in zones:
		var zd := zr as Dictionary
		if String(zd.get("kind", "")) == "police":
			_police_door_pos = zd["door_pos"] as Vector3
			_has_police_door = true
			break


## Night hook (called by the TimeManager every frame via the hood's night
## factor): lantern flames + glass brighten at night, and each zone's real
## lantern lights lift from a faint day ember to a warm night pool.
## No-ops before build().
func set_night_factor(f: float) -> void:
	_lantern_night = clampf(f, 0.0, 1.0)
	if _flame_mat == null:
		return
	_flame_mat.emission_energy_multiplier = lerpf(0.9, 3.2, _lantern_night)
	_lantern_glass_mat.emission_energy_multiplier = lerpf(0.25, 1.5,
		_lantern_night)
	for l in _lantern_lights:
		if is_instance_valid(l):
			# V3: slightly stronger warm pools at night (same 2/zone cap).
			l.light_energy = lerpf(0.4, 2.3, _lantern_night)


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


## Gun-findability hint: fires exactly once when the player first comes
## within POLICE_HINT_RANGE of the police exterior door. Unit-testable:
## takes the player position, needs no scene state beyond the cached door.
func police_hint_tick(player_pos: Vector3) -> void:
	if _police_hint_shown or not _has_police_door:
		return
	if player_pos.distance_to(_police_door_pos) > POLICE_HINT_RANGE:
		return
	_police_hint_shown = true # set before the banner: no double-fire
	if _hud != null:
		_hud.show_banner("POLICE STATION",
			"ARMORY INSIDE — LOCKED: FIND THE KEY OR CRAFT A LOCKPICK", 5.0)


func _physics_process(_delta: float) -> void:
	if _player != null and not _police_hint_shown:
		police_hint_tick(_player.global_position)
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
				# Player inside zone Z, zombie outside: converge THROUGH Z's
				# exterior door — the steer target sits 1.5m inside the door
				# plane so the zombie walks into the entry trigger (which the
				# open-door check then teleports in). Targeting door_pos
				# itself stalls the zombie: the AI gives up within 1.2m.
				var dp := pz["door_pos"] as Vector3
				var bf := float(pz["face"])
				z.steer_override = dp + Vector3(0, 0, -bf * 1.5)
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
	_surface_points = [] # lantern surface tracking starts fresh per zone

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
			_zone_police(hood, root, zw, zdep, h, face, origin, zi)
		"hospital":
			_zone_hospital(hood, root, zw, zdep, h, face, origin, zi)
		"warehouse":
			_zone_warehouse(hood, root, zw, zdep, h, face, origin, zi)
		"office_tall":
			_zone_office(hood, root, zw, zdep, h, face, origin, zi)
		"office_small":
			_zone_office_small(hood, root, zw, zdep, h, face, origin, zi)
	# Lanterns go LAST: placement only reads the recorded surfaces, so the
	# existing layout (and its hash) is already frozen.
	_zone_lanterns(hood, root, kind, face, zi)


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
		h: float, face: float, origin: Vector3, zi: int) -> void:
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
	# GUARANTEED GUNS (field report: "haven't found any guns yet"): the
	# pistol + rifle are scarcity-exempt — wave scarcity can never
	# "pick clean" them. Ammo still thins with the waves.
	hood.bx_add_loot(origin + Vector3(ax, 0.6, az + fd * 0.9),
		[["rifle", 1], ["ammo", 2], ["pistol", 1], ["ammo_9mm", 12],
			["scrap", 2], ["lockpick", 1]], "crate", true)
	hood.bx_add_loot(origin + Vector3(dx, 0.6, fd * 8.9),
		[["cloth", 2], ["water", 1]])
	# Brutes: one pacing the cell block, one guarding the armory.
	hood.bx_brute(origin + Vector3(-8.7, 0.3, -fd * 5.5))
	hood.bx_brute(origin + Vector3(ax, 0.3, az + fd * 1.8))
	# Walkers working the lobby: the station stays the most dangerous
	# compound. Fixed positions (no RNG draws) so the layout stream never
	# shifts; both clear of furniture and the entry lane.
	hood.bx_zombie(origin + Vector3(-3.0, 0.3, -fd * 2.0))
	hood.bx_zombie(origin + Vector3(3.0, 0.3, -fd * 7.0))
	_furnish_zone(hood, root, "police", w, d, h, face, origin, zi)
	hood.bx_track_interior("zone|police|cells=3")


func _zone_hospital(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3, zidx: int) -> void:
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
	_furnish_zone(hood, root, "hospital", w, d, h, face, origin, zidx)
	hood.bx_track_interior("zone|hospital|wards=2")


func _zone_warehouse(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3, zi: int) -> void:
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
	# GUARANTEED (field report): scarcity-exempt, always there.
	hood.bx_add_loot(origin + Vector3(-6.0, 0.6, -fd * 5.5),
		[["scrap", 3], ["wood", 3]], "toolbox")
	hood.bx_add_loot(origin + Vector3(6.0, 0.6, -fd * 6.0),
		[["wood", 2], ["scrap", 2]])
	hood.bx_add_loot(origin + Vector3(0.0, 0.6, -fd * 9.3),
		[["shotgun", 1], ["shells", 6]], "crate", true)
	# One worker that never clocked out.
	hood.bx_zombie(origin + Vector3(2.0, 0.3, -fd * 4.5))
	# A second worker between the pallet rows.
	hood.bx_zombie(origin + Vector3(-2.0, 0.3, -fd * 5.5))
	_furnish_zone(hood, root, "warehouse", w, d, h, face, origin, zi)
	hood.bx_track_interior("zone|warehouse|rows=2")


func _zone_office(hood: NeighborhoodBuilder, root: Node3D, w: float, d: float,
		h: float, face: float, origin: Vector3, zi: int) -> void:
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
	# A second walker near the lobby so the floor feels occupied.
	hood.bx_zombie(origin + Vector3(-2.5, 0.3, fd * 4.0))
	_furnish_zone(hood, root, "office_tall", w, d, h, face, origin, zi)
	hood.bx_track_interior("zone|office_tall|preset=%d" % preset)


func _zone_office_small(hood: NeighborhoodBuilder, root: Node3D, w: float,
		d: float, h: float, face: float, origin: Vector3, zi: int) -> void:
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
	# A second bullpen walker near the lobby.
	hood.bx_zombie(origin + Vector3(2.5, 0.3, fd * 3.5))
	_furnish_zone(hood, root, "office_small", w, d, h, face, origin, zi)
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
	# Record the desktop as a lantern surface (top face of the desk top).
	_surface_points.append({"pos": pos, "top": 0.78, "rot": rot_y})


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
	# Record the shelf top as a lantern surface.
	_surface_points.append({"pos": pos, "top": 1.7, "rot": rot_y})
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


# ------------------------------------------------------- lantern lighting ---
# Night pass: warm light sources inside the hidden compounds. Lantern
# props (shared flame/glass/frame materials) sit on recorded desk/shelf
# surfaces or fixed kind-specific fallback spots, each with ONE real
# OmniLight3D (warm 1.0/0.72/0.45, ~9m range, NO shadows) — cap 2 per
# zone. Only the occupied zone renders, so the cost stays flat. Placement
# uses a dedicated RNG stream (seeded from world_seed + zone index): no
# bx_rng draws, so layout/interior hashes never shift.

const LANTERN_LIGHTS_PER_ZONE := 2
const LANTERN_RANGE := 9.0
const LANTERN_COLOR := Color(1.0, 0.72, 0.45)


func _zone_lanterns(hood: NeighborhoodBuilder, root: Node3D, kind: String,
		face: float, zi: int) -> void:
	var lrng := RandomNumberGenerator.new()
	lrng.seed = absi(hash([hood.world_seed, "lanterns", zi]))
	var spots: Array = []
	for sp in _surface_points:
		var sd := sp as Dictionary
		var p: Vector3 = sd["pos"]
		spots.append({"pos": Vector3(p.x, float(sd["top"]), p.z),
			"rot": float(sd["rot"])})
	for f in _lantern_fallbacks(kind, face):
		spots.append(f)
	if spots.is_empty():
		return
	# Pick up to 2 spots with breathing room (4m) between them: zones are
	# big, two warm pools beat one clump.
	var picked: Array = []
	var tries := 0
	while picked.size() < LANTERN_LIGHTS_PER_ZONE and tries < 12 \
			and not spots.is_empty():
		tries += 1
		var idx := lrng.randi() % spots.size()
		var cand: Dictionary = spots[idx]
		var ok := true
		for p in picked:
			if (p["pos"] as Vector3).distance_to(cand["pos"] as Vector3) < 4.0:
				ok = false
		if ok:
			picked.append(cand)
			spots.remove_at(idx)
	for i in picked.size():
		var pd := picked[i] as Dictionary
		_zlantern(hood, root, pd["pos"] as Vector3, float(pd["rot"]), i)


## Fixed spots for kinds (or seeds) where desks/shelves are scarce.
## Positions are root-space, on top of fixed furniture or the floor.
func _lantern_fallbacks(kind: String, face: float) -> Array:
	var fd := face
	match kind:
		"police":
			# Lobby floor by the entry lane + armory floor corner.
			return [{"pos": Vector3(0.0, 0.0, fd * 6.5), "rot": 0.0},
				{"pos": Vector3(11.0, 0.0, -fd * 7.4), "rot": 0.0}]
		"hospital":
			# Reception counter top + a waiting-chair seat (fixed spots).
			return [{"pos": Vector3(0.0, 1.0, fd * 8.2), "rot": 0.0},
				{"pos": Vector3(-4.5, 0.49, fd * 6.0), "rot": 0.0}]
		"warehouse":
			return [{"pos": Vector3(0.0, 0.0, -fd * 5.0), "rot": 0.0},
				{"pos": Vector3(-6.0, 0.0, -fd * 8.0), "rot": 0.0}]
		"office_tall":
			# Lobby counter top + cubicle floor.
			return [{"pos": Vector3(4.5, 1.0, fd * 7.6), "rot": 0.0},
				{"pos": Vector3(-4.0, 0.0, -fd * 5.0), "rot": 0.0}]
		"office_small":
			return [{"pos": Vector3(4.0, 1.0, fd * 6.6), "rot": 0.0},
				{"pos": Vector3(-3.5, 0.0, -fd * 4.5), "rot": 0.0}]
	return []


func _zlantern(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, idx: int) -> void:
	var g := Node3D.new()
	g.name = "lantern_%d" % idx
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	hood.bx_box(g, Vector3(0.26, 0.05, 0.26), Vector3(0, 0.025, 0),
		_lantern_frame_mat)
	hood.bx_box(g, Vector3(0.20, 0.26, 0.20), Vector3(0, 0.18, 0),
		_lantern_glass_mat)
	hood.bx_box(g, Vector3(0.07, 0.13, 0.07), Vector3(0, 0.18, 0), _flame_mat)
	hood.bx_box(g, Vector3(0.24, 0.05, 0.24), Vector3(0, 0.335, 0),
		_lantern_frame_mat)
	# One REAL warm light per lantern (cap 2 per zone): short range, no
	# shadows. Only the occupied zone renders, so the flat cost is tiny.
	var l := OmniLight3D.new()
	l.light_color = LANTERN_COLOR
	# V3: slightly stronger warm pools at night (same 2/zone cap).
	l.light_energy = lerpf(0.4, 2.3, _lantern_night)
	l.omni_range = LANTERN_RANGE
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.position = Vector3(0, 0.5, 0)
	g.add_child(l)
	_lantern_lights.append(l)


# ------------------------------------------------- furnishing pass (Tbandz) ---
# "Not a bland dead ole place": every compound gets furniture tailored to
# its building type. Runs at the end of each _zone_* layout (BEFORE
# _zone_lanterns, so new desks register as lantern surfaces). Placement
# uses a DEDICATED RNG stream (world_seed + "furnish" + zone index): zero
# draws from hood.bx_rng(), so existing layout/interior hashes never
# shift. The entry lane |x| < 1.5 stays clear (walk lanes + zombie paths);
# every piece is tagged via bx_furn for the furniture QA. Signature
# pieces carry meta "fset" so furnish_qa can assert each kind got its
# tailored set. Shared materials everywhere, no per-frame cost (iPhone).

const FSET_META := "fset"


func _furnish_zone(hood: NeighborhoodBuilder, root: Node3D, kind: String,
		w: float, d: float, h: float, face: float, origin: Vector3,
		zi: int) -> void:
	var frng := RandomNumberGenerator.new()
	frng.seed = absi(hash([hood.world_seed, "furnish", zi]))
	match kind:
		"police":
			_furnish_police(hood, root, face, frng)
		"hospital":
			_furnish_hospital(hood, root, face, frng)
		"warehouse":
			_furnish_warehouse(hood, root, face, frng)
		"office_tall":
			_furnish_office(hood, root, face, frng, true)
		"office_small":
			_furnish_office(hood, root, face, frng, false)
	hood.bx_track_interior("zone|%s|furnished" % kind)


func _tag(n: Node, fset: String) -> void:
	n.set_meta(FSET_META, fset)


# ------------------------------------------------------ furniture builders ---

## Filing cabinet: solid 4-drawer cabinet with drawer fronts + handles.
func _zf_filing(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "filing_cabinet")
	var cab: Material = hood.bx_std(Color(0.42, 0.44, 0.42), 0.6, 0.4)
	var dark: Material = hood.bx_std(Color(0.20, 0.20, 0.20), 0.7)
	hood.bx_furn(hood.bx_solid_box(g, Vector3(0.55, 1.35, 0.50),
		Vector3(0, 0.675, 0), cab))
	for di in 4:
		var y := 0.22 + 0.30 * di
		hood.bx_box(g, Vector3(0.47, 0.24, 0.03), Vector3(0, y, 0.26), dark)
		hood.bx_box(g, Vector3(0.16, 0.03, 0.04), Vector3(0, y + 0.05, 0.28),
			hood.bx_std(Color(0.65, 0.65, 0.62), 0.4, 0.7))


## Evidence locker (police): tall steel cabinet with a mesh door front.
func _zf_evidence(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "evidence_locker")
	var steel: Material = hood.bx_std(Color(0.30, 0.33, 0.34), 0.55, 0.5)
	var mesh: Material = hood.bx_std(Color(0.12, 0.12, 0.13), 0.6, 0.3)
	hood.bx_furn(hood.bx_solid_box(g, Vector3(0.95, 2.15, 0.60),
		Vector3(0, 1.075, 0), steel))
	hood.bx_box(g, Vector3(0.75, 1.85, 0.04), Vector3(0, 1.05, 0.31), mesh)
	hood.bx_box(g, Vector3(0.75, 0.06, 0.05), Vector3(0, 1.95, 0.31), steel)
	hood.bx_box(g, Vector3(0.75, 0.06, 0.05), Vector3(0, 0.15, 0.31), steel)
	# Sealed evidence bags on the top shelf (visible through the mesh).
	var bagm: Material = hood.bx_std(Color(0.80, 0.72, 0.55), 0.9)
	hood.bx_box(g, Vector3(0.20, 0.14, 0.12), Vector3(-0.22, 1.80, 0.10), bagm)
	hood.bx_box(g, Vector3(0.16, 0.12, 0.12), Vector3(0.18, 1.79, 0.12), bagm)


## Wanted board (police): cork board + pinned case papers on the wall.
func _zf_wanted(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		face: float, rot_y: float, frng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "wanted_board")
	var cork: Material = hood.bx_std(Color(0.55, 0.42, 0.28), 0.95)
	hood.bx_box(g, Vector3(1.9, 1.25, 0.08), Vector3(0, 0, 0), cork)
	var papers := [Color(0.88, 0.86, 0.78), Color(0.80, 0.78, 0.70),
		Color(0.85, 0.82, 0.72)]
	for pi in 6:
		var px := -0.70 + 0.56 * (pi % 3)
		var py := 0.28 - 0.55 * (pi / 3)
		hood.bx_box(g, Vector3(0.42, 0.52, 0.02),
			Vector3(px, py, 0.06), hood.bx_std(papers[pi % 3], 0.95),
			frng.randf_range(-0.12, 0.12))
		# Red pin dot.
		hood.bx_box(g, Vector3(0.05, 0.05, 0.03),
			Vector3(px, py + 0.22, 0.07), hood.bx_std(Color(0.75, 0.10, 0.10), 0.6))
	# "WANTED" header strip.
	hood.bx_box(g, Vector3(1.9, 0.22, 0.09), Vector3(0, 0.72, 0),
		hood.bx_std(Color(0.72, 0.14, 0.12), 0.85))


## IV stand (hospital): pole, cross base, hook, fluid bag.
func _zf_iv(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "iv_stand")
	var steel: Material = hood.bx_std(Color(0.60, 0.62, 0.62), 0.35, 0.8)
	var bagm: Material = hood.bx_std(Color(0.82, 0.88, 0.78), 0.4)
	hood.bx_cyl(g, 0.03, 0.03, 1.9, Vector3(0, 0.95, 0), steel)
	hood.bx_box(g, Vector3(0.55, 0.04, 0.06), Vector3(0, 0.03, 0), steel)
	hood.bx_box(g, Vector3(0.06, 0.04, 0.55), Vector3(0, 0.03, 0), steel)
	hood.bx_box(g, Vector3(0.30, 0.03, 0.03), Vector3(0, 1.88, 0), steel)
	hood.bx_box(g, Vector3(0.16, 0.26, 0.06), Vector3(-0.10, 1.70, 0), bagm)


## Privacy curtain (hospital): rail + hanging curtain panel, non-solid.
func _zf_curtain(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, width: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "privacy_curtain")
	var steel: Material = hood.bx_std(Color(0.60, 0.62, 0.62), 0.35, 0.8)
	hood.bx_cyl(g, 0.025, 0.025, width, Vector3(0, 2.0, 0), steel).rotation.z = PI * 0.5
	hood.bx_box(g, Vector3(width * 0.92, 1.55, 0.05),
		Vector3(0, 1.18, 0), hood.bx_mat("curtain"))


## Gurney (hospital): frame, pad, wheels. Non-solid: corridors stay clear.
func _zf_gurney(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "gurney")
	var steel: Material = hood.bx_std(Color(0.60, 0.62, 0.62), 0.35, 0.8)
	hood.bx_box(g, Vector3(1.9, 0.10, 0.65), Vector3(0, 0.85, 0), steel)
	hood.bx_box(g, Vector3(1.8, 0.14, 0.60), Vector3(0, 0.97, 0),
		hood.bx_std(Color(0.72, 0.70, 0.64), 0.9))
	for sx in [-0.75, 0.75]:
		hood.bx_box(g, Vector3(0.06, 0.80, 0.06), Vector3(sx, 0.42, 0.22), steel)
		hood.bx_box(g, Vector3(0.06, 0.80, 0.06), Vector3(sx, 0.42, -0.22), steel)
		hood.bx_cyl(g, 0.09, 0.09, 0.05, Vector3(sx, 0.09, 0.22),
			hood.bx_std(Color(0.15, 0.15, 0.16), 0.8)).rotation.x = PI * 0.5
		hood.bx_cyl(g, 0.09, 0.09, 0.05, Vector3(sx, 0.09, -0.22),
			hood.bx_std(Color(0.15, 0.15, 0.16), 0.8)).rotation.x = PI * 0.5


## Water cooler (offices): body + blue bottle.
func _zf_cooler(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "water_cooler")
	hood.bx_furn(hood.bx_solid_box(g, Vector3(0.42, 1.0, 0.42),
		Vector3(0, 0.5, 0), hood.bx_std(Color(0.78, 0.78, 0.76), 0.6)))
	hood.bx_cyl(g, 0.15, 0.15, 0.42, Vector3(0, 1.21, 0),
		hood.bx_std(Color(0.35, 0.55, 0.80), 0.25))
	hood.bx_box(g, Vector3(0.30, 0.10, 0.30), Vector3(0, 0.95, 0),
		hood.bx_std(Color(0.70, 0.70, 0.68), 0.6))


## Potted plant: pot + two foliage blobs. Non-solid corner dressing.
func _zf_plant(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		frng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "plant")
	hood.bx_cyl(g, 0.20, 0.15, 0.35, Vector3(0, 0.175, 0),
		hood.bx_std(Color(0.45, 0.28, 0.20), 0.9))
	var leaf: Material = hood.bx_std(Color(0.22, 0.42, 0.20), 0.95)
	hood.bx_sphere(g, 0.30, Vector3(0, 0.62, 0), leaf, true)
	hood.bx_sphere(g, 0.22,
		Vector3(frng.randf_range(-0.15, 0.15), 0.88, frng.randf_range(-0.15, 0.15)),
		leaf, true)


## Conference/meeting table + chairs. Solid table body; chairs visual.
func _zf_conftable(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float, chairs: int, fset: String) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, fset)
	var wood: Material = hood.bx_mat("wood")
	var dark: Material = hood.bx_mat("table")
	hood.bx_furn(hood.bx_solid_box(g, Vector3(2.6, 0.10, 1.2),
		Vector3(0, 0.74, 0), wood))
	for sx in [-1.15, 1.15]:
		hood.bx_box(g, Vector3(0.10, 0.74, 1.0), Vector3(sx, 0.37, 0), dark)
	var per := chairs / 2
	for i in chairs:
		var side := 1.0 if i < per else -1.0
		var k := i % per
		var cx := -1.0 + 2.0 * (float(k) / maxf(1.0, float(per - 1))) if per > 1 else 0.0
		var chair_z := side * 1.05
		hood.bx_box(g, Vector3(0.45, 0.08, 0.45), Vector3(cx, 0.45, chair_z), dark)
		hood.bx_box(g, Vector3(0.45, 0.55, 0.08),
			Vector3(cx, 0.75, chair_z + side * 0.20), dark)


## Workbench (warehouse): heavy top + tool boxes on it.
func _zf_workbench(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "workbench")
	var wood: Material = hood.bx_mat("wood")
	var steel: Material = hood.bx_std(Color(0.35, 0.36, 0.36), 0.6, 0.4)
	hood.bx_furn(hood.bx_solid_box(g, Vector3(2.2, 0.14, 0.9),
		Vector3(0, 0.90, 0), wood))
	for sx in [-0.95, 0.95]:
		hood.bx_box(g, Vector3(0.12, 0.90, 0.75), Vector3(sx, 0.45, 0), steel)
	# Red toolbox + parts on the bench.
	hood.bx_box(g, Vector3(0.55, 0.28, 0.28), Vector3(-0.5, 1.11, 0),
		hood.bx_std(Color(0.60, 0.14, 0.12), 0.6))
	hood.bx_box(g, Vector3(0.30, 0.16, 0.22), Vector3(0.35, 1.05, 0.1), steel)
	hood.bx_box(g, Vector3(0.24, 0.12, 0.18), Vector3(0.62, 1.03, -0.12), wood)


## Hand truck / dolly (warehouse): plate + handles + wheels. Non-solid.
func _zf_dolly(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "dolly")
	var steel: Material = hood.bx_std(Color(0.35, 0.36, 0.38), 0.5, 0.6)
	hood.bx_box(g, Vector3(0.50, 0.05, 0.40), Vector3(0, 0.06, 0.18), steel)
	hood.bx_box(g, Vector3(0.05, 1.25, 0.05), Vector3(-0.20, 0.65, -0.05), steel)
	hood.bx_box(g, Vector3(0.05, 1.25, 0.05), Vector3(0.20, 0.65, -0.05), steel)
	hood.bx_box(g, Vector3(0.45, 0.05, 0.05), Vector3(0, 1.28, -0.05), steel)
	hood.bx_cyl(g, 0.11, 0.11, 0.07, Vector3(-0.20, 0.11, -0.02),
		hood.bx_std(Color(0.12, 0.12, 0.13), 0.8)).rotation.z = PI * 0.5
	hood.bx_cyl(g, 0.11, 0.11, 0.07, Vector3(0.20, 0.11, -0.02),
		hood.bx_std(Color(0.12, 0.12, 0.13), 0.8)).rotation.z = PI * 0.5


## Tire stack (warehouse): three stacked tires. Solid, low.
func _zf_tires(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		frng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "tire_stack")
	var rubber: Material = hood.bx_std(Color(0.10, 0.10, 0.11), 0.95)
	hood.bx_furn(hood.bx_solid_box(g, Vector3(0.72, 0.60, 0.72),
		Vector3(0, 0.30, 0), rubber))
	for ti in 3:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.33
		tm.rings = 12
		tm.ring_segments = 6
		t.mesh = tm
		t.rotation.x = PI * 0.5
		t.position = Vector3(frng.randf_range(-0.03, 0.03), 0.13 + 0.24 * ti,
			frng.randf_range(-0.03, 0.03))
		t.material_override = rubber
		g.add_child(t)


## Long bench (police lobby): slatted seat + legs.
func _zf_bench(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "bench")
	var wood: Material = hood.bx_mat("wood")
	var dark: Material = hood.bx_mat("table")
	hood.bx_furn(hood.bx_solid_box(g, Vector3(2.4, 0.09, 0.55),
		Vector3(0, 0.46, 0), wood))
	for sx in [-1.0, 1.0]:
		hood.bx_box(g, Vector3(0.09, 0.46, 0.45), Vector3(sx, 0.23, 0), dark)


## Side table (hospital reception): small round-ish table, non-solid.
func _zf_sidetable(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "side_table")
	var wood: Material = hood.bx_mat("wood")
	hood.bx_box(g, Vector3(0.60, 0.06, 0.60), Vector3(0, 0.55, 0), wood)
	hood.bx_box(g, Vector3(0.08, 0.55, 0.08), Vector3(0, 0.275, 0),
		hood.bx_mat("table"))
	# Clipboard + magazine on top.
	hood.bx_box(g, Vector3(0.28, 0.03, 0.36), Vector3(-0.10, 0.60, 0.05),
		hood.bx_std(Color(0.80, 0.76, 0.66), 0.9))
	hood.bx_box(g, Vector3(0.24, 0.02, 0.30), Vector3(0.12, 0.595, -0.08),
		hood.bx_std(Color(0.55, 0.20, 0.16), 0.9))


## Rolling supply cabinet (hospital): small solid cabinet with drawers.
func _zf_rollcab(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "supply_cabinet")
	var cab: Material = hood.bx_std(Color(0.75, 0.76, 0.74), 0.5)
	hood.bx_furn(hood.bx_solid_box(g, Vector3(0.70, 0.95, 0.45),
		Vector3(0, 0.475, 0), cab))
	hood.bx_box(g, Vector3(0.60, 0.04, 0.03), Vector3(0, 0.70, 0.24),
		hood.bx_std(Color(0.40, 0.40, 0.40), 0.6))
	hood.bx_box(g, Vector3(0.60, 0.04, 0.03), Vector3(0, 0.40, 0.24),
		hood.bx_std(Color(0.40, 0.40, 0.40), 0.6))


## Trash bin: flared cylinder + lid. Non-solid corner dressing.
func _zf_bin(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		col: Color) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "trash_bin")
	hood.bx_cyl(g, 0.22, 0.17, 0.62, Vector3(0, 0.31, 0),
		hood.bx_std(col, 0.6, 0.3))
	hood.bx_cyl(g, 0.24, 0.24, 0.06, Vector3(0, 0.65, 0),
		hood.bx_std(col.darkened(0.25), 0.6, 0.3))


## Duty roster board (police): framed board with pinned roster slips.
func _zf_dutyboard(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		face: float) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "duty_board")
	var fz := face * 0.06
	hood.bx_box(g, Vector3(2.2, 1.4, 0.08), Vector3(0, 0, 0),
		hood.bx_mat("wood"))
	hood.bx_box(g, Vector3(2.0, 1.2, 0.04), Vector3(0, 0, fz),
		hood.bx_std(Color(0.30, 0.32, 0.30), 0.9))
	for ri in 3:
		for ci in 2:
			hood.bx_box(g, Vector3(0.75, 0.28, 0.02),
				Vector3(-0.5 + float(ci) * 1.0, 0.38 - float(ri) * 0.36,
					fz + face * 0.03),
				hood.bx_std(Color(0.82, 0.80, 0.72), 0.95))


## Whiteboard (offices): white board + marker tray + markers.
func _zf_whiteboard(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		face: float) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "whiteboard")
	var fz := face * 0.06
	hood.bx_box(g, Vector3(2.4, 1.3, 0.07), Vector3(0, 0, 0),
		hood.bx_std(Color(0.45, 0.45, 0.46), 0.6, 0.2))
	hood.bx_box(g, Vector3(2.24, 1.14, 0.04), Vector3(0, 0, fz),
		hood.bx_std(Color(0.90, 0.90, 0.88), 0.35))
	hood.bx_box(g, Vector3(2.4, 0.06, 0.14), Vector3(0, -0.70, fz * 1.5),
		hood.bx_mat("table")) # tray
	hood.bx_box(g, Vector3(0.16, 0.04, 0.04), Vector3(-0.6, -0.64, fz * 1.5),
		hood.bx_std(Color(0.75, 0.12, 0.12), 0.6)) # red marker
	hood.bx_box(g, Vector3(0.16, 0.04, 0.04), Vector3(-0.35, -0.64, fz * 1.5),
		hood.bx_std(Color(0.12, 0.12, 0.75), 0.6)) # blue marker


## Wall clock: pale disc + dark hands. Non-solid.
func _zf_clock(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		face: float) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "wall_clock")
	var rim: Material = hood.bx_std(Color(0.15, 0.15, 0.16), 0.5)
	var face_m: Material = hood.bx_std(Color(0.88, 0.87, 0.82), 0.6)
	hood.bx_cyl(g, 0.30, 0.30, 0.06, Vector3.ZERO, rim).rotation.x = PI * 0.5
	hood.bx_cyl(g, 0.26, 0.26, 0.065, Vector3.ZERO, face_m).rotation.x = PI * 0.5
	hood.bx_box(g, Vector3(0.035, 0.20, 0.02), Vector3(0, 0.05, face * 0.045),
		rim) # minute hand
	var hh := hood.bx_box(g, Vector3(0.035, 0.13, 0.02),
		Vector3(0.04, -0.02, face * 0.045), rim) # hour hand
	hh.rotation.z = -0.9


## Pallet jack (warehouse): two forks + handle + grip. Non-solid visual.
func _zf_palletjack(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3,
		rot_y: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = rot_y
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "pallet_jack")
	var paint: Material = hood.bx_std(Color(0.65, 0.16, 0.10), 0.6, 0.3)
	for fx in [-0.22, 0.22]:
		hood.bx_box(g, Vector3(0.14, 0.07, 1.15), Vector3(fx, 0.09, 0), paint)
	hood.bx_box(g, Vector3(0.60, 0.10, 0.22), Vector3(0, 0.10, -0.62), paint)
	var handle := hood.bx_box(g, Vector3(0.07, 1.05, 0.07),
		Vector3(0, 0.55, -0.78), paint)
	handle.rotation.x = -0.35
	hood.bx_box(g, Vector3(0.22, 0.09, 0.07), Vector3(0, 1.02, -0.95),
		hood.bx_std(Color(0.12, 0.12, 0.12), 0.7)) # grip


## Barrel cluster (warehouse): three drums, one tipped. Non-solid.
func _zf_barrels(hood: NeighborhoodBuilder, root: Node3D, pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	root.add_child(g)
	hood.bx_furn(g)
	_tag(g, "barrels")
	var drum: Material = hood.bx_mat("barrel")
	var band: Material = hood.bx_std(Color(0.20, 0.20, 0.21), 0.6, 0.5)
	var offs := [Vector3(0, 0, 0), Vector3(0.75, 0, 0.2), Vector3(0.3, 0, 0.8)]
	for i in offs.size():
		var o: Vector3 = offs[i]
		if i == 2: # one tipped on its side
			var tip := Node3D.new()
			tip.position = o + Vector3(0, 0.32, 0)
			tip.rotation.z = PI * 0.5
			g.add_child(tip)
			hood.bx_furn(tip)
			hood.bx_cyl(tip, 0.30, 0.30, 0.88, Vector3.ZERO, drum)
		else:
			hood.bx_cyl(g, 0.30, 0.30, 0.88, o + Vector3(0, 0.44, 0), drum)
			hood.bx_cyl(g, 0.315, 0.315, 0.08, o + Vector3(0, 0.60, 0), band)


# ------------------------------------------------------ per-kind furnishing ---

func _furnish_police(hood: NeighborhoodBuilder, root: Node3D, face: float,
		frng: RandomNumberGenerator) -> void:
	var fd := face
	# Evidence row along the right wall.
	for ei in 3:
		_zf_evidence(hood, root, Vector3(13.3, 0, -fd * (1.5 + 2.0 * ei)), PI * 0.5)
	# Wanted board on the back wall.
	_zf_wanted(hood, root, Vector3(3.0, 1.7, -fd * 10.55), face, 0.0, frng)
	# Interrogation corner: desk + 2 chairs, left side.
	_zdesk(hood, root, Vector3(-6.5, 0, fd * 1.0), 0.35)
	_zdesk(hood, root, Vector3(6.5, 0, fd * 4.5), -0.5)
	# Filing cabinet + lobby bench.
	_zf_filing(hood, root, Vector3(13.3, 0, fd * 7.0), PI * 0.5)
	_zf_bench(hood, root, Vector3(-6.0, 0, fd * 8.0), 0.0)
	# V3: more lobby life — duty roster on the back wall, extra benches,
	# trash bins in the corners.
	_zf_dutyboard(hood, root, Vector3(-3.0, 1.6, -fd * 10.55), face)
	_zf_bench(hood, root, Vector3(6.0, 0, fd * 8.5), 0.0)
	_zf_bench(hood, root, Vector3(10.0, 0, fd * 8.5), 0.0)
	_zf_bin(hood, root, Vector3(-13.5, 0, fd * 5.5),
		Color(0.30, 0.31, 0.32))
	_zf_bin(hood, root, Vector3(13.5, 0, fd * 4.5),
		Color(0.30, 0.31, 0.32))


func _furnish_hospital(hood: NeighborhoodBuilder, root: Node3D, face: float,
		frng: RandomNumberGenerator) -> void:
	var fd := face
	# IV stands at three beds.
	_zf_iv(hood, root, Vector3(-10.1, 0, -fd * 8.0))
	_zf_iv(hood, root, Vector3(10.1, 0, -fd * 5.5))
	_zf_iv(hood, root, Vector3(-10.1, 0, -fd * 5.5))
	# Privacy curtains between the ward beds.
	_zf_curtain(hood, root, Vector3(-11.0, 0, -fd * 6.75), 0.0, 2.6)
	_zf_curtain(hood, root, Vector3(11.0, 0, -fd * 6.75), 0.0, 2.6)
	# Gurney in the central corridor + supply cabinet in ward B.
	_zf_gurney(hood, root, Vector3(0.0, 0, -fd * 1.5), 0.2)
	_zf_rollcab(hood, root, Vector3(13.5, 0, -fd * 9.0), 0.0)
	# Reception side table.
	_zf_sidetable(hood, root, Vector3(-3.5, 0, fd * 9.8))
	# V3: ward dressing — biohazard bin, glove dispensers on the back
	# wall, a magazine table in the waiting area, a crash cart.
	_zf_bin(hood, root, Vector3(5.5, 0, fd * 9.3), Color(0.62, 0.14, 0.12))
	for gx in [-5.5, 5.5]:
		hood.bx_furn(hood.bx_box(root, Vector3(0.5, 0.3, 0.18),
			Vector3(gx, 1.5, -fd * 11.6),
			hood.bx_std(Color(0.70, 0.78, 0.85), 0.6))) # glove dispenser
	_zf_sidetable(hood, root, Vector3(-7.5, 0, fd * 6.0))
	_zf_rollcab(hood, root, Vector3(-13.5, 0, -fd * 4.0), PI * 0.5) # crash cart


func _furnish_warehouse(hood: NeighborhoodBuilder, root: Node3D, face: float,
		frng: RandomNumberGenerator) -> void:
	var fd := face
	# Fill the shelf gaps: second row along the back wall.
	for si in [-4.0, 4.0]:
		_zshelf(hood, root, Vector3(si, 0, -fd * 8.5), 0.0, true, frng)
	# Workbench against the left wall, dolly + tires staged nearby.
	_zf_workbench(hood, root, Vector3(-11.8, 0, fd * 4.5), PI * 0.5)
	_zf_dolly(hood, root, Vector3(11.8, 0, fd * 1.5), -0.3)
	_zf_tires(hood, root, Vector3(-11.8, 0, -fd * 1.5), frng)
	# Tall double crate stack on the right.
	var wood: Material = hood.bx_mat("wood")
	var cg := Node3D.new()
	cg.position = Vector3(11.8, 0, -fd * 4.5)
	root.add_child(cg)
	hood.bx_furn(cg)
	_tag(cg, "crate_stack")
	hood.bx_furn(hood.bx_solid_box(cg, Vector3(1.3, 0.9, 1.0),
		Vector3(0, 0.45, 0), wood))
	hood.bx_furn(hood.bx_solid_box(cg, Vector3(1.1, 0.8, 0.9),
		Vector3(0.05, 1.3, 0), wood))
	# V3: warehouse life — barrel cluster, shrink-wrapped pallet, pallet jack.
	_zf_barrels(hood, root, Vector3(-11.8, 0, fd * 8.0))
	hood.bx_furn(hood.bx_solid_box(root, Vector3(1.6, 1.2, 1.2),
		Vector3(11.8, 0.6, -fd * 8.0),
		hood.bx_std(Color(0.80, 0.80, 0.78), 0.4))) # shrink-wrapped pallet
	_zf_palletjack(hood, root, Vector3(-6.0, 0, fd * 7.0), 0.4)


func _furnish_office(hood: NeighborhoodBuilder, root: Node3D, face: float,
		frng: RandomNumberGenerator, tall: bool) -> void:
	var fd := face
	if tall:
		_zf_filing(hood, root, Vector3(-11.5, 0, fd * 6.5), 0.0)
		_zf_filing(hood, root, Vector3(-11.5, 0, fd * 5.0), 0.0)
		_zf_conftable(hood, root, Vector3(7.5, 0, -fd * 6.0), 0.0, 6, "conf_table")
		_zf_cooler(hood, root, Vector3(-11.8, 0, -fd * 1.5))
		_zf_plant(hood, root, Vector3(11.8, 0, fd * 8.0), frng)
		_zf_plant(hood, root, Vector3(-11.8, 0, fd * 8.0), frng)
		_zdesk(hood, root, Vector3(-8.0, 0, -fd * 1.5),
			frng.randf_range(-0.5, 0.5))
		_zdesk(hood, root, Vector3(8.0, 0, fd * 2.5),
			frng.randf_range(-0.5, 0.5))
	else:
		_zf_filing(hood, root, Vector3(-10.2, 0, fd * 5.0), 0.0)
		_zf_cooler(hood, root, Vector3(10.4, 0, fd * 5.5))
		_zf_plant(hood, root, Vector3(-10.4, 0, -fd * 2.0), frng)
		_zf_conftable(hood, root, Vector3(6.0, 0, -fd * 5.0), 0.0, 4,
			"meeting_table")
		_zdesk(hood, root, Vector3(-7.0, 0, -fd * 3.0),
			frng.randf_range(-0.5, 0.5))
	# V3: office dressing — whiteboard + wall clock on the back wall,
	# trash bins up front, a bottle crate by the water cooler.
	var zdim: Vector2 = ZONE_DIMS["office_tall" if tall else "office_small"]
	var zhw := zdim.x * 0.5
	var zhh := zdim.y * 0.5
	_zf_whiteboard(hood, root, Vector3(0.0, 1.5, -fd * (zhh - 0.35)), face)
	_zf_clock(hood, root, Vector3(6.0, 2.2, -fd * (zhh - 0.32)), face)
	_zf_bin(hood, root, Vector3(-zhw + 1.0, 0, fd * (zhh - 3.0)),
		Color(0.30, 0.31, 0.32))
	_zf_bin(hood, root, Vector3(zhw - 1.0, 0, fd * (zhh - 3.0)),
		Color(0.30, 0.31, 0.32))
	var crate_x := -10.9 if tall else 9.5
	var crate_z := -fd * 1.5 if tall else fd * 5.5
	var cg2 := Node3D.new()
	cg2.position = Vector3(crate_x, 0, crate_z)
	root.add_child(cg2)
	hood.bx_furn(cg2)
	_tag(cg2, "bottle_crate")
	hood.bx_box(cg2, Vector3(0.5, 0.3, 0.4), Vector3(0, 0.15, 0),
		hood.bx_mat("wood"))
	for bxi in 2:
		for bzi in 2:
			hood.bx_cyl(cg2, 0.07, 0.07, 0.35,
				Vector3(-0.12 + 0.24 * bxi, 0.45, -0.09 + 0.18 * bzi),
				hood.bx_std(Color(0.35, 0.55, 0.80), 0.25))
