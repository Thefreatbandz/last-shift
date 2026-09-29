class_name InventoryPanel
extends CanvasLayer
## Phase 3: phone-friendly backpack panel. Item cards with counts; tap a
## usable card to consume it. World stays live while open.

signal toggled(open: bool)

var _inventory: Inventory
var _visual: PlayerVisual
var _grid: GridContainer
var _open := false


func setup(inv: Inventory, visual: PlayerVisual) -> void:
	_inventory = inv
	_visual = visual
	_inventory.changed.connect(_on_changed)


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
	panel.offset_top = -420
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
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "BACKPACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	vbox.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(_grid)

	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	vbox.add_child(close)
	_refresh()


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close_panel()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	_refresh()
	Sound.play("inv_open")
	toggled.emit(true)


func close_panel() -> void:
	_open = false
	visible = false
	Sound.play("inv_close")
	toggled.emit(false)


func _on_changed() -> void:
	if _open:
		_refresh()


func _refresh() -> void:
	if _inventory == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var any := false
	for id in LootDefs.ORDER:
		var n := _inventory.count(id)
		if n <= 0:
			continue
		any = true
		_grid.add_child(_make_card(id, n))
	if not any:
		var l := Label.new()
		l.text = "Empty. Go search some houses."
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		_grid.add_child(l)


func _make_card(id: String, n: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(168, 108)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.16)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.45, 0.38, 0.28)
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate() as StyleBoxFlat
	sb2.bg_color = Color(0.20, 0.21, 0.23)
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)

	var sw := ColorRect.new()
	sw.color = LootDefs.item_color(id)
	sw.custom_minimum_size = Vector2(44, 26)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swc := CenterContainer.new()
	swc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swc.add_child(sw)
	vb.add_child(swc)

	var nm := Label.new()
	nm.text = LootDefs.item_name(id)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	var ct := Label.new()
	ct.text = "x%d" % n
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.add_theme_font_size_override("font_size", 14)
	ct.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ct)

	if LootDefs.is_usable(id):
		var use := Label.new()
		use.text = "TAP TO USE"
		use.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		use.add_theme_font_size_override("font_size", 11)
		use.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		use.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(use)
		b.pressed.connect(_on_use.bind(id))
	return b


func _on_use(id: String) -> void:
	if _inventory.use(id) and _visual != null:
		_visual.play_eat()
	_refresh()
