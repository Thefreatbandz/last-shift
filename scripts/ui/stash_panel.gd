class_name StashPanel
extends CanvasLayer
## Phase 3: safehouse stash. Two grids — tap YOUR PACK to deposit, tap
## STASH to withdraw.

signal toggled(open: bool)

var _inventory: Inventory
var _you_grid: GridContainer
var _stash_grid: GridContainer
var _open := false


func setup(inv: Inventory) -> void:
	_inventory = inv
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
	panel.offset_top = -460
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

	vbox.add_child(_mk_title("STASH  —  tap pack to store, tap stash to take"))
	vbox.add_child(_mk_sub("YOUR PACK"))
	_you_grid = _mk_grid()
	vbox.add_child(_you_grid)
	vbox.add_child(_mk_sub("STASH"))
	_stash_grid = _mk_grid()
	vbox.add_child(_stash_grid)

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


func _mk_title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	return l


func _mk_sub(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	return l


func _mk_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g


func _refresh() -> void:
	if _inventory == null:
		return
	for c in _you_grid.get_children():
		c.queue_free()
	for c in _stash_grid.get_children():
		c.queue_free()
	for id in LootDefs.ORDER:
		var n := _inventory.count(id)
		if n > 0:
			_you_grid.add_child(_make_card(id, n, true))
	for id in LootDefs.ORDER:
		var n := _inventory.stash_count(id)
		if n > 0:
			_stash_grid.add_child(_make_card(id, n, false))


func _make_card(id: String, n: int, in_pack: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(128, 84)
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
	sw.custom_minimum_size = Vector2(36, 20)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swc := CenterContainer.new()
	swc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swc.add_child(sw)
	vb.add_child(swc)

	var nm := Label.new()
	nm.text = "%s x%d" % [LootDefs.item_name(id), n]
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	if in_pack:
		b.pressed.connect(_on_deposit.bind(id))
	else:
		b.pressed.connect(_on_withdraw.bind(id))
	return b


func _on_deposit(id: String) -> void:
	_inventory.deposit(id)


func _on_withdraw(id: String) -> void:
	_inventory.withdraw(id)
