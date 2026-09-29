class_name Safehouse
extends Node3D
## Phase 3: the boarded-up house becomes claimable. Claim it at the door:
## boards fall, your mark goes up, the door swings open, and the porch
## comes alive (workbench, stash chest, bedroll). Bedroll sleeps until
## morning ("While You Slept" teaser — full world-sim arrives later).
## Claiming also moves the respawn point here.

signal claimed_house
signal slept

const DOOR_POS := Vector3(-6, 0, -16.46) # boarded house front door, world space
const PORCH := Vector3(-6, 0, -13.0)

var claimed := false

var _player: PlayerController
var _visual: PlayerVisual
var _inventory: Inventory
var _health: PlayerHealth
var _hud: Hud
var _tm: TimeManager
var _zombies: ZombieManager
var _hood: NeighborhoodBuilder
var _interact: InteractManager
var _craft_panel: CraftingPanel
var _stash_panel: StashPanel

var _claim_id := -1
var _sleeping := false
var _props: Node3D
var _bench: Node3D
var _chest: Node3D
var _bedroll: Node3D

static var _m_trim: StandardMaterial3D
static var _m_tag: StandardMaterial3D
static var _m_fabric: StandardMaterial3D
static var _m_iron: StandardMaterial3D


func setup(p: PlayerController, visual: PlayerVisual, inv: Inventory,
		health: PlayerHealth, hud: Hud, tm: TimeManager,
		zombies: ZombieManager, hood: NeighborhoodBuilder,
		interact: InteractManager) -> void:
	_player = p
	_visual = visual
	_inventory = inv
	_health = health
	_hud = hud
	_tm = tm
	_zombies = zombies
	_hood = hood
	_interact = interact
	_mats()
	global_position = DOOR_POS
	_claim_id = _interact.register(self, "CLAIM SAFEHOUSE", 3.2, claim)
	_build_props()
	_props.visible = false


static func _mats() -> void:
	if _m_trim != null:
		return
	_m_trim = StandardMaterial3D.new()
	_m_trim.albedo_color = Color(0.30, 0.24, 0.16)
	_m_trim.roughness = 0.9
	_m_tag = StandardMaterial3D.new()
	_m_tag.albedo_color = Color(0.95, 0.35, 0.10)
	_m_tag.emission_enabled = true
	_m_tag.emission = Color(0.95, 0.35, 0.10)
	_m_tag.emission_energy_multiplier = 0.35
	_m_fabric = StandardMaterial3D.new()
	_m_fabric.albedo_color = Color(0.35, 0.33, 0.28)
	_m_fabric.roughness = 1.0
	_m_iron = StandardMaterial3D.new()
	_m_iron.albedo_color = Color(0.25, 0.25, 0.27)
	_m_iron.metallic = 0.6
	_m_iron.roughness = 0.5


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_props() -> void:
	_props = Node3D.new()
	add_child(_props)
	# --- Workbench (left of the door). ---
	_bench = Node3D.new()
	_bench.position = Vector3(-2.4, 0, 1.4)
	_props.add_child(_bench)
	_box(_bench, Vector3(1.5, 0.12, 0.75), Vector3(0, 0.92, 0), _m_trim)
	for sx in [-0.65, 0.65]:
		for sz in [-0.3, 0.3]:
			_box(_bench, Vector3(0.1, 0.92, 0.1), Vector3(sx, 0.46, sz), _m_trim)
	_box(_bench, Vector3(0.5, 0.12, 0.3), Vector3(-0.3, 1.04, 0), _m_iron) # tools
	_box(_bench, Vector3(0.3, 0.2, 0.25), Vector3(0.35, 1.08, 0.05), _m_fabric)
	# --- Stash chest (right of the door). ---
	_chest = Node3D.new()
	_chest.position = Vector3(2.4, 0, 1.4)
	_props.add_child(_chest)
	_box(_chest, Vector3(0.95, 0.5, 0.6), Vector3(0, 0.25, 0), _m_trim)
	_box(_chest, Vector3(0.95, 0.12, 0.6), Vector3(0, 0.56, 0), _m_iron)
	# --- Bedroll (porch center, out of the walkway). ---
	_bedroll = Node3D.new()
	_bedroll.position = Vector3(0.4, 0, 3.6)
	_props.add_child(_bedroll)
	var roll := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.28
	cm.height = 1.7
	cm.radial_segments = 10
	roll.mesh = cm
	roll.rotation.z = PI * 0.5
	roll.position = Vector3(0, 0.28, 0)
	roll.material_override = _m_fabric
	_bedroll.add_child(roll)
	_box(_bedroll, Vector3(0.35, 0.14, 0.4), Vector3(-0.75, 0.14, 0), _m_trim) # pillow


func claim() -> void:
	if claimed:
		return
	claimed = true
	_visual.play_door_push()
	_interact.set_enabled(_claim_id, false)
	# Boards clatter to the ground, staggered.
	var boards: Array = _hood.safehouse_boards
	for i in boards.size():
		var b := boards[i] as MeshInstance3D
		if not is_instance_valid(b):
			continue
		var tw := create_tween()
		tw.tween_interval(0.25 + 0.14 * i)
		tw.tween_property(b, "rotation:z", b.rotation.z + randf_range(-0.7, 0.7), 0.3)
		tw.parallel().tween_property(b, "position:y", 0.12, 0.4)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Your mark: burnt-orange X above the door.
	var tag := Node3D.new()
	tag.position = Vector3(0, 3.1, 0.1)
	add_child(tag)
	var t1 := _box(tag, Vector3(0.85, 0.14, 0.06), Vector3.ZERO, _m_tag)
	t1.rotation.z = 0.6
	var t2 := _box(tag, Vector3(0.85, 0.14, 0.06), Vector3.ZERO, _m_tag)
	t2.rotation.z = -0.6
	tag.scale = Vector3.ZERO
	var tag_tw := create_tween()
	tag_tw.tween_interval(1.0)
	tag_tw.tween_property(tag, "scale", Vector3.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Door swings open on its hinge pivot.
	var pivot := _hood.safehouse_door_pivot
	if is_instance_valid(pivot):
		var dtw := create_tween()
		dtw.tween_interval(0.9)
		dtw.tween_property(pivot, "rotation:y", -1.85, 1.0)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Porch props pop in, then their prompts go live.
	var ptw := create_tween()
	ptw.tween_interval(1.2)
	ptw.tween_callback(_reveal_props)
	_health.set_respawn(PORCH + Vector3(0, 0.3, 0))
	claimed_house.emit()


func _reveal_props() -> void:
	_props.visible = true
	_props.scale = Vector3(0.01, 0.01, 0.01)
	var tw := create_tween()
	tw.tween_property(_props, "scale", Vector3.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_interact.register(_bench, "USE WORKBENCH", 2.8, open_crafting)
	_interact.register(_chest, "OPEN STASH", 2.8, open_stash)
	_interact.register(_bedroll, "SLEEP UNTIL MORNING", 2.8, sleep)


func set_panels(craft_panel: CraftingPanel, stash_panel: StashPanel) -> void:
	_craft_panel = craft_panel
	_stash_panel = stash_panel


func open_crafting() -> void:
	if _craft_panel != null:
		_craft_panel.open()


func open_stash() -> void:
	if _stash_panel != null:
		_stash_panel.open()


func sleep() -> void:
	if _sleeping or _health.is_dead():
		return
	_sleeping = true
	_hud.fade_to_black(true)
	await get_tree().create_timer(0.75).timeout
	if _health.is_dead():
		# Killed mid-fade: abort the sleep, leave death flow alone.
		_hud.fade_to_black(false)
		_sleeping = false
		return
	if _tm.time_hours >= 7.0:
		_tm.day += 1
	_tm.time_hours = 7.0
	_health.heal(999.0)
	_zombies.reset_all()
	_player.global_position = PORCH + Vector3(0, 0.3, 0)
	_hud.fade_to_black(false)
	_hud.show_slept_teaser()
	_sleeping = false
	slept.emit()


func build_barricade() -> void:
	# Plank walls around the porch (visual) + the zombie ward (behavior).
	var wall_mat := _m_trim
	var segs := [
		[Vector3(-2.6, 0.55, 5.2), Vector3(2.6, 1.1, 0.14), 0.1],
		[Vector3(2.6, 0.55, 5.2), Vector3(2.6, 1.1, 0.14), -0.08],
		[Vector3(-4.1, 0.55, 3.4), Vector3(0.14, 1.1, 3.6), 0.0],
		[Vector3(4.1, 0.55, 3.4), Vector3(0.14, 1.1, 3.6), 0.0],
	]
	for s in segs:
		var m := _box(_props, s[1] as Vector3, s[0] as Vector3, wall_mat)
		m.rotation.y = float(s[2])
	_zombies.set_ward(PORCH, 13.0)
