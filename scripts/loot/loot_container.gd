class_name LootContainer
extends Node3D
## Phase 3 searchable container: wooden crate with a pop-open lid and a
## subtle glow ring while unsearched. LootManager drives the search flow;
## this node owns its visuals and searched state.

var loot: Array = [] # Array of [id: String, count: int]
var searched := false

var _lid: Node3D
var _glow: MeshInstance3D

static var _m_wood: StandardMaterial3D
static var _m_wood_dark: StandardMaterial3D
static var _m_glow: StandardMaterial3D


static func _mats() -> void:
	if _m_wood != null:
		return
	_m_wood = StandardMaterial3D.new()
	_m_wood.albedo_color = Color(0.36, 0.27, 0.17)
	_m_wood.roughness = 0.9
	_m_wood_dark = StandardMaterial3D.new()
	_m_wood_dark.albedo_color = Color(0.25, 0.18, 0.11)
	_m_wood_dark.roughness = 0.95
	_m_glow = StandardMaterial3D.new()
	_m_glow.albedo_color = Color(1.0, 0.80, 0.45)
	_m_glow.emission_enabled = true
	_m_glow.emission = Color(1.0, 0.72, 0.35)
	_m_glow.emission_energy_multiplier = 0.55
	_m_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func build(loot_items: Array) -> void:
	loot = loot_items
	_mats()
	# Crate body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.95, 0.55, 0.95)
	body.mesh = bm
	body.position = Vector3(0, 0.275, 0)
	body.material_override = _m_wood
	add_child(body)
	# Cross slats on the sides for the scavenged look.
	for sx in [-0.481, 0.481]:
		var slat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.03, 0.62, 0.62)
		slat.mesh = sm
		slat.position = Vector3(sx, 0.28, 0)
		slat.rotation.x = 0.5 if sx > 0.0 else -0.5
		slat.material_override = _m_wood_dark
		add_child(slat)
	# Lid on a back-edge pivot so it pops open.
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, -0.475)
	add_child(_lid)
	var lid_mi := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.95, 0.10, 0.95)
	lid_mi.mesh = lm
	lid_mi.position = Vector3(0, 0.05, 0.475)
	lid_mi.material_override = _m_wood_dark
	_lid.add_child(lid_mi)
	# Subtle glow ring while unsearched.
	_glow = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.78
	gm.bottom_radius = 0.78
	gm.height = 0.05
	gm.radial_segments = 20
	_glow.mesh = gm
	_glow.position = Vector3(0, 0.025, 0)
	_glow.material_override = _m_glow
	add_child(_glow)
	# Solid so the player can't walk through it.
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.6, 0.95)
	cs.shape = shape
	cs.position = Vector3(0, 0.3, 0)
	sb.add_child(cs)
	add_child(sb)


func set_searched() -> void:
	searched = true
	_glow.visible = false
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.85, 0.45)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
