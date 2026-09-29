class_name LootManager
extends Node3D
## Phase 3: spawns curated searchable containers around the neighborhood,
## runs the kneel-and-search flow, grants loot with sparkle + floating
## labels. Emits `loot_granted` so future systems (audio) can hook in.
## Spots were checked against houses, cars (+solids), fences, the gas
## station, streetlights, trees and zombie spawns.

signal loot_granted(items: Array)

const SEARCH_TIME := 1.5
const SEARCH_RADIUS := 2.6

# [position, [[item_id, count], ...]] — curated, deterministic.
const SPOTS := [
	[Vector3(-44, 0, -14.5), [["scrap", 2], ["cloth", 1]]],
	[Vector3(-24, 0, -15.5), [["canned_food", 1], ["water", 1]]],
	[Vector3(-36, 0, 14.5), [["medkit", 1]]],
	[Vector3(-12, 0, 15.5), [["canned_food", 1], ["cloth", 1]]],
	[Vector3(14, 0, 14.5), [["water", 2], ["scrap", 1]]],
	[Vector3(-54, 0, 3.0), [["scrap", 3]]],
	[Vector3(-10, 0, 4.6), [["scrap", 2], ["cloth", 1]]],
	[Vector3(20, 0, 19.4), [["medkit", 1], ["water", 1]]],
	[Vector3(-45, 0, -7.0), [["canned_food", 1], ["scrap", 2]]],
	[Vector3(-46, 0, -25.5), [["cloth", 3]]],
	[Vector3(44, 0, -27.5), [["canned_food", 2], ["water", 1]]],
]

var _player: PlayerController
var _visual: PlayerVisual
var _inventory: Inventory
var _interact: InteractManager
var _hud: Hud

var _containers: Array[LootContainer] = []
var _ids: Dictionary = {} # LootContainer -> interact id
var _searching := false
var _search_t := 0.0
var _search_target: LootContainer


func setup(p: PlayerController, visual: PlayerVisual, inv: Inventory,
		interact: InteractManager, hud: Hud) -> void:
	_player = p
	_visual = visual
	_inventory = inv
	_interact = interact
	_hud = hud
	_spawn_containers()


func _spawn_containers() -> void:
	for s in SPOTS:
		add_container(s[0] as Vector3, s[1] as Array)


## QA pass: public so the bootstrap can add indoor containers (houses).
func add_container(pos: Vector3, items: Array) -> LootContainer:
	var c := LootContainer.new()
	c.position = pos
	add_child(c)
	c.build(items)
	_containers.append(c)
	_ids[c] = _interact.register(c, "SEARCH", SEARCH_RADIUS, _on_search.bind(c))
	return c


func _on_search(c: LootContainer) -> void:
	if _searching or c.searched:
		return
	_searching = true
	_search_target = c
	_search_t = SEARCH_TIME
	Sound.play_3d("search", c.global_position)
	_visual.play_kneel(SEARCH_TIME + 0.4)
	_hud.show_work_bar("SEARCHING", SEARCH_TIME)


func _physics_process(delta: float) -> void:
	if not _searching:
		return
	if not is_instance_valid(_search_target) \
			or _player.global_position.distance_to(_search_target.global_position) > SEARCH_RADIUS + 1.2:
		_cancel_search()
		return
	_search_t -= delta
	if _search_t <= 0.0:
		_finish_search()


func _cancel_search() -> void:
	_searching = false
	_search_target = null
	_hud.hide_work_bar()


func _finish_search() -> void:
	var c := _search_target
	_searching = false
	_search_target = null
	_hud.hide_work_bar()
	if c == null or not is_instance_valid(c) or c.searched:
		return
	c.set_searched()
	_interact.set_enabled(int(_ids[c]), false)
	_visual.play_pickup()
	_spawn_sparkle(c.global_position + Vector3(0, 0.9, 0))
	for it in c.loot:
		var id := String(it[0])
		var n := int(it[1])
		_inventory.add(id, n)
		_spawn_float_label(c.global_position + Vector3(0, 1.1, 0), "+%d %s" % [n, LootDefs.item_name(id).to_upper()])
	loot_granted.emit(c.loot)


func _spawn_sparkle(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	p.color = Color(1.0, 0.85, 0.45)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(p.queue_free)


func _spawn_float_label(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.01
	l.modulate = Color(1.0, 0.92, 0.60)
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.1, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_LINEAR)
	tw.chain().tween_callback(l.queue_free)
