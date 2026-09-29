class_name MinimapView
extends Control
## Corner minimap (top-right, below PACK/MENU) + tap/M expanded overlay.
## North-up, fog of war, 10Hz redraw via the model. Emits `tapped` so the
## bootstrap can suppress the bat swing a map-tap would otherwise trigger.

signal tapped

var _model: MinimapModel
var expanded := false


func setup(m: MinimapModel) -> void:
	_model = m
	_model.updated.connect(_on_model_updated)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_layout()


func toggle_expanded() -> void:
	set_expanded(not expanded)


func set_expanded(on: bool) -> void:
	expanded = on
	_apply_layout()
	queue_redraw()


func _apply_layout() -> void:
	if expanded:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0
	else:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -160.0
		offset_top = 76.0
		offset_right = -16.0
		offset_bottom = 220.0


func _on_model_updated() -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var tap := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tap = mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	elif event is InputEventScreenTouch:
		tap = (event as InputEventScreenTouch).pressed
	if tap:
		tapped.emit()
		toggle_expanded()
		accept_event()


func _draw() -> void:
	if _model == null or size.x < 10.0:
		return
	if expanded:
		MapDraw.draw_expanded(self, _model)
		return
	var rect := Rect2(Vector2.ZERO, size)
	MapDraw.draw_panel(self, rect)
	var c := rect.get_center()
	var px := (minf(size.x, size.y) * 0.5 - 14.0) / 74.0
	MapDraw.draw_world(self, _model, c, px)
	MapDraw.draw_north(self, Vector2(c.x, 4.0))
