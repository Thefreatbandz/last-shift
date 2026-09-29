class_name Hud
extends CanvasLayer
## Minimal survival-game HUD: day + clock up top, desktop controls hint,
## and touch controls (virtual joystick + sprint button) that appear on the
## first touch event. Player reads move_vector / sprint_held each physics frame.

var move_vector := Vector2.ZERO
var touch_mode := false
var sprint_held := false

var _day_label: Label
var _clock_label: Label
var _hint_label: Label
var _joy: TouchJoystick
var _sprint_btn: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Top-center day/clock panel ---
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -130
	panel.offset_right = 130
	panel.offset_top = 14
	panel.offset_bottom = 100
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	_day_label = Label.new()
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 20)
	_day_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_day_label)

	_clock_label = Label.new()
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 34)
	_clock_label.add_theme_color_override("font_color", Color.WHITE)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_clock_label)
	set_clock(1, 9, 0)

	# --- Desktop controls hint (hidden once touch mode engages) ---
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint_label.offset_left = 18
	_hint_label.offset_top = 14
	_hint_label.offset_right = 520
	_hint_label.offset_bottom = 110
	_hint_label.text = "WASD / ARROWS — move\nSHIFT — sprint\nQ / E — rotate camera"
	_hint_label.add_theme_font_size_override("font_size", 17)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.70))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)

	# --- Touch controls (revealed on first touch) ---
	_joy = TouchJoystick.new()
	_joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joy.offset_left = 40
	_joy.offset_top = -280
	_joy.offset_right = 280
	_joy.offset_bottom = -40
	_joy.visible = false
	root.add_child(_joy)

	_sprint_btn = Button.new()
	_sprint_btn.text = "SPRINT"
	_sprint_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_sprint_btn.offset_left = -190
	_sprint_btn.offset_top = -190
	_sprint_btn.offset_right = -50
	_sprint_btn.offset_bottom = -50
	_sprint_btn.focus_mode = Control.FOCUS_NONE
	_sprint_btn.add_theme_font_size_override("font_size", 20)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.45)
	bs.set_corner_radius_all(70)
	bs.border_width_left = 2
	bs.border_width_right = 2
	bs.border_width_top = 2
	bs.border_width_bottom = 2
	bs.border_color = Color(1, 1, 1, 0.35)
	_sprint_btn.add_theme_stylebox_override("normal", bs)
	var bs2 := bs.duplicate() as StyleBoxFlat
	bs2.bg_color = Color(0.85, 0.65, 0.25, 0.55)
	_sprint_btn.add_theme_stylebox_override("pressed", bs2)
	_sprint_btn.add_theme_stylebox_override("hover", bs)
	_sprint_btn.visible = false
	_sprint_btn.button_down.connect(func() -> void: sprint_held = true)
	_sprint_btn.button_up.connect(func() -> void: sprint_held = false)
	root.add_child(_sprint_btn)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and not touch_mode:
		touch_mode = true
		_joy.visible = true
		_sprint_btn.visible = true
		_hint_label.visible = false


func _process(_delta: float) -> void:
	if touch_mode:
		move_vector = _joy.output


func set_clock(day: int, hour: int, minute: int) -> void:
	_day_label.text = "DAY %d" % day
	_clock_label.text = "%02d:%02d" % [hour, minute]
