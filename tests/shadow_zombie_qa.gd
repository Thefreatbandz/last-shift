extends SceneTree
## QA for the Tbandz iPhone field reports:
##  1. Giant shadow blob: tree canopies must not cast shadows (trunks do).
##  2. Compound interiors: every zone kind has interior zombie spawns at the
##     tuned counts; a wave zombie crosses an open exterior door into a zone.
##  3. Barricades still poundable (no regression from the spawn changes).

var _booted := false
var _frames := 0
var _main: Node
var _nb: Node
var _iz: Node
var _zm: Node
var _failed := 0
var _passed := 0
var _wave_z: Node = null
var _wave_zone: Dictionary = {}
var _crossed := false

func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("SHADOWZOMBIE_QA FAIL: ", name)

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_nb = _main.get_node("Neighborhood")
		_iz = _nb.get("interior_zones")
		_zm = _main.get_node("Zombies")
		return false
	_frames += 1
	if _frames == 30:
		_run_static_checks()
		_setup_wave_crossing()
	elif _frames > 30 and _frames < 700:
		_poll_wave_crossing()
	elif _frames == 700:
		_check("wave_zombie_crossed_open_door", _crossed)
		print("SHADOWZOMBIE_QA done passed=", _passed, " failed=", _failed)
		quit(1 if _failed > 0 else 0)
		return true
	return false

func _run_static_checks() -> void:
	# 1. Canopy shadow fix: every canopy sphere in yard trees must have
	#    shadows off; trunks must still cast.
	var canopy_off := 0
	var canopy_on := 0
	var cr := _walk_canopy(_nb, canopy_off, canopy_on)
	canopy_off = cr[0]
	canopy_on = cr[1]
	print("SHADOWZOMBIE_QA canopy off=", canopy_off, " on=", canopy_on)
	_check("canopy_shadows_off", canopy_on == 0 and canopy_off > 0)
	# 2. Interior spawn counts per kind.
	var counts := {}
	var zones: Array = _iz.get("zones")
	for z in zones:
		var zd: Dictionary = z
		var kind: String = String(zd["kind"])
		counts[kind] = counts.get(kind, 0) + 1
	# building_zombie_spawns / brute_spawns are Array[Vector3]; interior ones
	# sit far from the map (zone offsets ~1.2km+). Count per zone kind.
	var walkers: Array = _nb.get("building_zombie_spawns")
	var brutes: Array = _nb.get("brute_spawns")
	var per_kind := {}
	for p in walkers:
		var pos: Vector3 = p
		if pos.length() > 500.0:
			var k2: String = _iz.kind_at(pos)
			if k2 != "":
				if not per_kind.has(k2):
					per_kind[k2] = {"walkers": 0, "brutes": 0}
				per_kind[k2]["walkers"] += 1
	for p in brutes:
		var pos: Vector3 = p
		if pos.length() > 500.0:
			var k2: String = _iz.kind_at(pos)
			if k2 != "":
				if not per_kind.has(k2):
					per_kind[k2] = {"walkers": 0, "brutes": 0}
				per_kind[k2]["brutes"] += 1
	print("SHADOWZOMBIE_QA interior spawns: ", per_kind)
	# Expected counts per kind (only assert for kinds present in this seed).
	var expected := {
		"police": [2, 2], "hospital": [3, 0], "warehouse": [2, 0],
		"office_tall": [2, 0], "office_small": [2, 0],
	}
	for kind in expected.keys():
		var exp: Array = expected[kind]
		if per_kind.has(kind):
			var got: Dictionary = per_kind[kind]
			_check(kind + "_walkers",
				int(got["walkers"]) == int(exp[0]))
			_check(kind + "_brutes",
				int(got["brutes"]) == int(exp[1]))
		else:
			print("SHADOWZOMBIE_QA note: kind '", kind, "' not present in seed")
	# 3. Barricade pounding intact: BarricadeManager exists and exposes the
	#    pound API the zombie AI uses.
	var bm: Node = _main.get_node("Barricades")
	_check("barricade_manager_present", bm != null)
	_check("barricade_pound_api", bm != null and bm.has_method("nearest_closed_door")
		and bm.has_method("has_boards") and bm.has_method("key_for_building"))

func _walk_canopy(n: Node, off: int, on: int) -> Array:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			# Yard-tree canopies: faceted spheres at 2-6m height. Exclude the
			# map-edge brush wall (spheres at |x|~98 or |z|~98, far from any
			# house — those keep their shadows).
			if mi.mesh is SphereMesh and mi.global_position.y > 2.0 and mi.global_position.y < 6.0:
				var gp: Vector3 = mi.global_position
				if absf(gp.x) < 95.0 and absf(gp.z) < 95.0:
					var sm := mi.mesh as SphereMesh
					var wr: float = sm.radius * mi.global_transform.basis.get_scale().x
					if wr > 1.0:
						if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							off += 1
						else:
							on += 1
		var r := _walk_canopy(c, off, on)
		off = r[0]
		on = r[1]
	return [off, on]

func _setup_wave_crossing() -> void:
	# Pick the office_small zone; open its exterior door; put the player
	# inside; spawn a zombie outside the door and aggro it.
	var zones: Array = _iz.get("zones")
	for z in zones:
		var zd: Dictionary = z
		if String(zd["kind"]) == "office_small":
			_wave_zone = zd
			break
	_check("found_office_small_zone", not _wave_zone.is_empty())
	if _wave_zone.is_empty():
		return
	var bi := int(_wave_zone["building"])
	# Open the door PROPERLY (dictionary flag + collision blocker + pivot).
	var doors: Node = _main.get_node("HouseDoors")
	doors.set_building_door_open(bi, true, false)
	_main.player.global_position = _wave_zone["spawn_in"] as Vector3
	var door_pos: Vector3 = _wave_zone["door_pos"]
	_wave_z = _zm._spawn_at(door_pos + Vector3(2.0, 0.3, 3.0))
	_wave_z.on_noise(door_pos, 120.0) # SUSPICIOUS: the director steers it in

func _poll_wave_crossing() -> void:
	if _crossed or _wave_z == null or not is_instance_valid(_wave_z):
		return
	# Inside the zone = zone_at matches the office_small zone.
	var z: Dictionary = _iz.zone_at(_wave_z.global_position)
	if not z.is_empty() and String(z.get("kind", "")) == "office_small":
		_crossed = true
