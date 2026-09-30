class_name LootContainer
extends Node3D
## Phase 3 searchable container, Phase 2 variety pass: seven distinct
## searchable types — crate, trash pile, old corpse, fresh corpse (blood
## pool), toolbox, first-aid kit, duffel bag — each with its own visual
## and prompt label. LootManager drives the search flow; this node owns
## its visuals and searched state.

var loot: Array = [] # Array of [id: String, count: int]
var searched := false
var kind := "crate"

var _lid: Node3D
var _glow: MeshInstance3D

static var _m_wood: StandardMaterial3D
static var _m_wood_dark: StandardMaterial3D
static var _m_glow: StandardMaterial3D
static var _m_trash: StandardMaterial3D
static var _m_trash_dark: StandardMaterial3D
static var _m_body: StandardMaterial3D
static var _m_body_dark: StandardMaterial3D
static var _m_skin: StandardMaterial3D
static var _m_blood: StandardMaterial3D
static var _m_tool_red: StandardMaterial3D
static var _m_tool_dark: StandardMaterial3D
static var _m_aid_white: StandardMaterial3D
static var _m_aid_red: StandardMaterial3D
static var _m_duffel: StandardMaterial3D
static var _m_duffel_dark: StandardMaterial3D


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
	_m_trash = StandardMaterial3D.new()
	_m_trash.albedo_color = Color(0.13, 0.14, 0.12)
	_m_trash.roughness = 0.95
	_m_trash_dark = StandardMaterial3D.new()
	_m_trash_dark.albedo_color = Color(0.08, 0.09, 0.08)
	_m_trash_dark.roughness = 0.95
	_m_body = StandardMaterial3D.new()
	_m_body.albedo_color = Color(0.32, 0.30, 0.26) # dusty desaturated clothes
	_m_body.roughness = 1.0
	_m_body_dark = StandardMaterial3D.new()
	_m_body_dark.albedo_color = Color(0.22, 0.20, 0.17)
	_m_body_dark.roughness = 1.0
	_m_skin = StandardMaterial3D.new()
	_m_skin.albedo_color = Color(0.55, 0.48, 0.40)
	_m_skin.roughness = 1.0
	_m_blood = StandardMaterial3D.new()
	_m_blood.albedo_color = Color(0.65, 0.07, 0.07) # fresh blood red
	_m_blood.roughness = 0.9 # matte: a glossy pool mirrors the teal sky
	# at shallow camera angles and reads purple instead of red.
	_m_blood.emission_enabled = true # faint self-light: stays readable red
	_m_blood.emission = Color(0.30, 0.015, 0.015) # in teal-tinted shadow.
	_m_blood.emission_energy_multiplier = 1.0
	_m_tool_red = StandardMaterial3D.new()
	_m_tool_red.albedo_color = Color(0.55, 0.12, 0.10)
	_m_tool_red.roughness = 0.6
	_m_tool_dark = StandardMaterial3D.new()
	_m_tool_dark.albedo_color = Color(0.12, 0.12, 0.13)
	_m_tool_dark.roughness = 0.5
	_m_aid_white = StandardMaterial3D.new()
	_m_aid_white.albedo_color = Color(0.82, 0.80, 0.75)
	_m_aid_white.roughness = 0.7
	_m_aid_red = StandardMaterial3D.new()
	_m_aid_red.albedo_color = Color(0.75, 0.10, 0.10)
	_m_aid_red.roughness = 0.7
	_m_duffel = StandardMaterial3D.new()
	_m_duffel.albedo_color = Color(0.20, 0.22, 0.13) # olive drab canvas
	_m_duffel.roughness = 1.0
	_m_duffel_dark = StandardMaterial3D.new()
	_m_duffel_dark.albedo_color = Color(0.12, 0.13, 0.09)
	_m_duffel_dark.roughness = 1.0


const PROMPTS := {
	"crate": "SEARCH CRATE",
	"trash": "SEARCH TRASH",
	"corpse": "SEARCH CORPSE",
	"fresh_corpse": "SEARCH BODY",
	"toolbox": "SEARCH TOOLBOX",
	"firstaid": "SEARCH FIRST AID",
	"duffel": "SEARCH DUFFEL",
	"drop": "TAKE",
	"lumber": "TAKE LUMBER",
}

var container_id := -1 # build-order index; wave-scarcity rolls key off this


static func prompt_for(k: String) -> String:
	return String(PROMPTS.get(k, "SEARCH"))


func build(loot_items: Array, p_kind := "crate") -> void:
	loot = loot_items
	kind = p_kind
	_mats()
	match kind:
		"trash":
			_build_trash()
		"corpse":
			_build_corpse(false)
		"fresh_corpse":
			_build_corpse(true)
		"toolbox":
			_build_toolbox()
		"firstaid":
			_build_firstaid()
		"duffel":
			_build_duffel()
		"drop":
			_build_drop()
		"lumber":
			_build_lumber()
		_:
			_build_crate()
	_add_glow()
	_add_collision()


func _box(size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.material_override = mat
	add_child(mi)
	return mi


func _ball(r: float, pos: Vector3, mat: Material, squash_y := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	mi.mesh = sm
	mi.position = pos
	mi.scale.y = squash_y
	mi.material_override = mat
	add_child(mi)
	return mi


func _build_crate() -> void:
	# Crate body.
	_box(Vector3(0.95, 0.55, 0.95), Vector3(0, 0.275, 0), _m_wood)
	# Cross slats on the sides for the scavenged look.
	for sx in [-0.481, 0.481]:
		var slat := _box(Vector3(0.03, 0.62, 0.62), Vector3(sx, 0.28, 0), _m_wood_dark)
		slat.rotation.x = 0.5 if sx > 0.0 else -0.5
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


func _build_trash() -> void:
	# Lumpy tied trash bags slumped in a pile.
	_ball(0.42, Vector3(-0.25, 0.30, 0.1), _m_trash, 0.75)
	_ball(0.36, Vector3(0.28, 0.26, -0.12), _m_trash_dark, 0.7)
	_ball(0.30, Vector3(0.02, 0.62, 0.05), _m_trash, 0.8)
	_ball(0.24, Vector3(-0.05, 0.18, 0.42), _m_trash_dark, 0.7)
	# Tied knot on the top bag.
	_box(Vector3(0.10, 0.14, 0.10), Vector3(0.02, 0.92, 0.05), _m_trash_dark, 0.4)


func _build_corpse(fresh: bool) -> void:
	# A body lying on its back: torso, head, arms, legs. Old corpses are
	# desiccated gray; fresh ones get a dark blood pool.
	var cm := _m_body if not fresh else _m_body_dark
	var yaw := 0.0
	_box(Vector3(0.55, 0.28, 1.05), Vector3(0, 0.16, 0), cm, yaw) # torso
	_ball(0.21, Vector3(0, 0.20, 0.78), _m_skin, 0.9) # head
	_box(Vector3(0.16, 0.14, 0.62), Vector3(-0.38, 0.10, 0.05), cm, 0.12) # arm L
	_box(Vector3(0.16, 0.14, 0.62), Vector3(0.38, 0.10, -0.02), cm, -0.10) # arm R
	_box(Vector3(0.20, 0.16, 0.72), Vector3(-0.14, 0.10, -0.85), _m_body_dark, 0.05) # leg L
	_box(Vector3(0.20, 0.16, 0.72), Vector3(0.14, 0.10, -0.88), _m_body_dark, -0.06) # leg R
	if fresh:
		# Dark blood pool spreading from the torso.
		var pool := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.85
		pm.bottom_radius = 0.95
		pm.height = 0.02
		pm.radial_segments = 14
		pool.mesh = pm
		pool.position = Vector3(0.15, 0.012, 0.25)
		pool.scale.x = 1.35
		pool.material_override = _m_blood
		add_child(pool)


func _build_toolbox() -> void:
	# Red metal toolbox with a dark handle and latch strip.
	_box(Vector3(0.62, 0.30, 0.30), Vector3(0, 0.15, 0), _m_tool_red)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.30, -0.15)
	add_child(_lid)
	var lid_mi := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.62, 0.08, 0.30)
	lid_mi.mesh = lm
	lid_mi.position = Vector3(0, 0.04, 0.15)
	lid_mi.material_override = _m_tool_red
	_lid.add_child(lid_mi)
	_box(Vector3(0.30, 0.05, 0.06), Vector3(0, 0.40, 0), _m_tool_dark) # handle
	_box(Vector3(0.62, 0.06, 0.31), Vector3(0, 0.28, 0), _m_tool_dark) # seam


func _build_firstaid() -> void:
	# White first-aid box with a red cross on the lid.
	_box(Vector3(0.55, 0.34, 0.24), Vector3(0, 0.17, 0), _m_aid_white)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.34, -0.12)
	add_child(_lid)
	var lid_mi := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.55, 0.07, 0.24)
	lid_mi.mesh = lm
	lid_mi.position = Vector3(0, 0.035, 0.12)
	lid_mi.material_override = _m_aid_white
	_lid.add_child(lid_mi)
	# Red cross on top.
	_box(Vector3(0.20, 0.015, 0.07), Vector3(0, 0.415, 0), _m_aid_red)
	_box(Vector3(0.07, 0.015, 0.20), Vector3(0, 0.415, 0), _m_aid_red)


func _build_duffel() -> void:
	# Olive duffel bag: elongated squashed body, dark strap rings around
	# the belly, top carry handle.
	var b := _ball(0.42, Vector3(0, 0.30, 0), _m_duffel, 0.66)
	b.scale.x = 1.6
	for sx in [-0.30, 0.30]:
		var strap := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.31
		tm.outer_radius = 0.39
		tm.rings = 16
		tm.ring_segments = 8
		strap.mesh = tm
		strap.rotation.y = PI / 2.0 # ring plane -> YZ, axis along X
		strap.scale = Vector3(1.0, 0.78, 1.0) # hug the squashed belly
		strap.position = Vector3(sx, 0.30, 0)
		strap.material_override = _m_duffel_dark
		add_child(strap)
	_box(Vector3(0.34, 0.06, 0.10), Vector3(0, 0.63, 0), _m_duffel_dark, 0.1)
	_box(Vector3(0.06, 0.12, 0.10), Vector3(-0.14, 0.57, 0), _m_duffel_dark)
	_box(Vector3(0.06, 0.12, 0.10), Vector3(0.14, 0.57, 0), _m_duffel_dark)


func _build_drop() -> void:
	# Zombie drop: a small dark satchel on the ground where the kill
	# happened. Low profile, no collision, glow ring marks it.
	_box(Vector3(0.44, 0.16, 0.30), Vector3(0, 0.08, 0), _m_trash_dark, 0.35)
	_box(Vector3(0.20, 0.10, 0.22), Vector3(0.05, 0.20, -0.02), _m_duffel, -0.2)


func _build_lumber() -> void:
	# Lumber pile: stacked planks with two cross pieces, by the warehouse.
	_box(Vector3(1.7, 0.13, 0.34), Vector3(0, 0.10, 0), _m_wood, 0.06)
	_box(Vector3(1.6, 0.13, 0.34), Vector3(0.05, 0.24, 0.02), _m_wood_dark, -0.05)
	_box(Vector3(1.75, 0.13, 0.34), Vector3(-0.03, 0.38, -0.02), _m_wood, 0.10)
	_box(Vector3(0.30, 0.10, 1.1), Vector3(-0.5, 0.05, 0), _m_wood_dark)
	_box(Vector3(0.30, 0.10, 1.1), Vector3(0.55, 0.05, 0), _m_wood_dark)


func _add_glow() -> void:
	# Subtle glow ring while unsearched. Corpses get a wider ring so it
	# encircles the blood pool instead of hiding under it.
	_glow = MeshInstance3D.new()
	var gm := TorusMesh.new()
	if kind == "corpse" or kind == "fresh_corpse":
		gm.inner_radius = 1.18
		gm.outer_radius = 1.34
	else:
		gm.inner_radius = 0.70
		gm.outer_radius = 0.86
	gm.rings = 24
	gm.ring_segments = 8
	_glow.mesh = gm
	_glow.position = Vector3(0, 0.04, 0)
	_glow.material_override = _m_glow
	add_child(_glow)


func _add_collision() -> void:
	# Solid so the player can't walk through it (corpses and ground drops
	# are low: no block).
	if kind == "corpse" or kind == "fresh_corpse" or kind == "drop":
		return
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	match kind:
		"trash":
			shape.size = Vector3(1.0, 0.9, 1.0)
			cs.position = Vector3(0, 0.45, 0)
		"toolbox", "firstaid":
			shape.size = Vector3(0.65, 0.45, 0.35)
			cs.position = Vector3(0, 0.22, 0)
		"duffel":
			shape.size = Vector3(1.45, 0.6, 0.95)
			cs.position = Vector3(0, 0.3, 0)
		_:
			shape.size = Vector3(0.95, 0.6, 0.95)
			cs.position = Vector3(0, 0.3, 0)
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)


func set_searched() -> void:
	searched = true
	_glow.visible = false
	if _lid != null:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.85, 0.45)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
