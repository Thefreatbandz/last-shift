class_name CraftingPanel
extends CanvasLayer
## Phase 3: workbench menu. One row per recipe: name, effect, cost, and a
## CRAFT button that greys out when unaffordable or done.

signal toggled(open: bool)

var _crafting: Crafting
var _rows: VBoxContainer
var _open := false


func setup(crafting: Crafting) -> void:
	_crafting = crafting
	_crafting.crafted.connect(_on_crafted)
	_crafting.inventory.changed.connect(_on_changed)


func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -440
	panel.offset_bottom = -90
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.09, 0.97)
	sb.set_corner_radius_all(12)
	sb.border_width_top = 2
	sb.border_color = Color(0.45, 0.38, 0.28)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "WORKBENCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	vbox.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	vbox.add_child(_rows)

	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	vbox.add_child(close)
	_refresh()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_refresh()
	toggled.emit(true)


func close_panel() -> void:
	_open = false
	visible = false
	toggled.emit(false)


func _on_crafted(_id: String) -> void:
	_refresh()


func _on_changed() -> void:
	if _open:
		_refresh()


func _refresh() -> void:
	if _crafting == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	for r in Crafting.RECIPES:
		_rows.add_child(_make_row(r as Dictionary))


func _make_row(r: Dictionary) -> HBoxContainer:
	var id := String(r["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	row.add_child(vb)

	var nm := Label.new()
	nm.text = String(r["name"])
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vb.add_child(nm)

	var desc := Label.new()
	desc.text = String(r["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	vb.add_child(desc)

	var cost := Label.new()
	cost.text = "Cost: " + _crafting.cost_text(id)
	cost.add_theme_font_size_override("font_size", 13)
	var afford := _crafting.can_craft(id)
	cost.add_theme_color_override("font_color",
		Color(0.60, 0.85, 0.60) if afford else Color(0.85, 0.45, 0.40))
	vb.add_child(cost)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(110, 64)
	var done := _crafting.is_done(id)
	btn.text = "BUILT" if done else "CRAFT"
	btn.disabled = done or not afford
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_craft.bind(id))
	row.add_child(btn)
	return row


func _on_craft(id: String) -> void:
	_crafting.craft(id)
