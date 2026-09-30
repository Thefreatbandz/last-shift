class_name Hud
extends CanvasLayer
## Phase 2 survival HUD. Desktop: slim health bar top-left, compact
## day/clock top-center, controls hint. Touch (revealed on first touch):
## left virtual joystick (full tilt = sprint, NO sprint button), one big
## ATTACK button bottom-right for the right thumb, minimal hints.
## Also: red damage vignette (flashes on hit, heartbeat pulse at low HP)
## and the YOU DIED respawn overlay.

signal respawn_requested
signal interact_pressed # touch USE button
signal backpack_pressed # touch backpack button
signal menu_pressed # top-right MENU button (pause)
signal new_game_pressed # menu: start a fresh seeded neighborhood
signal continue_pressed # menu: resume the current run
signal weapon_pressed # touch weapon-swap button

var move_vector := Vector2.ZERO
var touch_mode := false
var sprint_held := false

var _day_label: Label
var _clock_label: Label
var _hint_label: Label
var _touch_hint: Label
var _touch_hint_t := 0.0
var _joy: TouchJoystick
var _attack_btn: Button
var _attack_queued := false

var _hp_fill: ColorRect
var _hp_frac := 1.0
var _vignette: ColorRect
var _flash := 0.0
var _pulse_t := 0.0
var _death_overlay: Button

# Phase 3: interact prompt + touch USE, backpack button, search progress bar,
# sleep fade, "While You Slept" teaser.
# Survival stats: slim stamina/hunger/thirst bars under the health bar.
var _stam_fill: ColorRect
var _hunger_fill: ColorRect
var _thirst_fill: ColorRect
var _stam_frac := 1.0
var _hunger_frac := 1.0
var _thirst_frac := 1.0
var _stam_pulse := 0.0 # attack-denied feedback flash
var _dehydrated := false
var _dehy_vignette: ColorRect
var _prompt_label: Label
var _use_btn: Button
var _pack_btn: Button
var _work_label: Label
var _work_bg: ColorRect
var _work_fill: ColorRect
var _work_t := 0.0
var _work_dur := 1.0
var _fade: ColorRect
var _toast: Label
var _toast_sub: Label
var _toast_t := 0.0

# Title / pause menu: seed display, NEW GAME (new neighborhood), CONTINUE.
var _hud_root: Control
var _menu_root: Control
var _menu_dim: ColorRect
var _menu_title: Label
var _menu_sub: Label
var _menu_seed: Label
var _menu_new: Button
var _menu_continue: Button
var _hud_menu_btn: Button
var _menu_open := false

# Wave-survival loop: wave status under the clock, big event banners,
# weapon display + touch weapon-swap button, transient messages.
var _wave_label: Label
var _weapon_label: Label
var _weapon_btn: Button
var _msg_t := 0.0
var _interact_prompt_active := false


func _make_meter_bar(root: Control, top: int, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.offset_left = 16
	bg.offset_top = top
	bg.offset_right = 186
	bg.offset_bottom = top + 8
	bg.color = Color(0, 0, 0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var fill := ColorRect.new()
	fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fill.offset_left = 18
	fill.offset_top = top + 2
	fill.offset_right = 184
	fill.offset_bottom = top + 6
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return fill


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menu must work while paused
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hud_root = root

	# --- Slim health bar, top-left ---
	var hp_bg := ColorRect.new()
	hp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_bg.offset_left = 16
	hp_bg.offset_top = 14
	hp_bg.offset_right = 186
	hp_bg.offset_bottom = 28
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hp_fill.offset_left = 18
	_hp_fill.offset_top = 16
	_hp_fill.offset_right = 184
	_hp_fill.offset_bottom = 26
	_hp_fill.color = Color(0.80, 0.16, 0.14, 0.95)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_fill)

	# --- Survival bars: stamina / hunger / thirst, slim, under the HP bar ---
	_stam_fill = _make_meter_bar(root, 32, Color(0.35, 0.78, 0.32, 0.95))
	_hunger_fill = _make_meter_bar(root, 44, Color(0.92, 0.55, 0.18, 0.95))
	_thirst_fill = _make_meter_bar(root, 56, Color(0.25, 0.55, 0.95, 0.95))

	# --- Dehydration vignette (blue pulse at 0 thirst) ---
	_dehy_vignette = ColorRect.new()
	_dehy_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dehy_vignette.color = Color(0.15, 0.30, 0.65, 0.0)
	_dehy_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dehy_vignette)

	# --- Compact day/clock panel, top-center ---
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -95
	panel.offset_right = 95
	panel.offset_top = 10
	panel.offset_bottom = 66
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	_day_label = Label.new()
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 15)
	_day_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_day_label)

	_clock_label = Label.new()
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 24)
	_clock_label.add_theme_color_override("font_color", Color.WHITE)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_clock_label)
	set_clock(1, 9, 0)

	# --- Wave status: slim label under the clock panel ---
	_wave_label = Label.new()
	_wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_label.offset_left = -160
	_wave_label.offset_right = 160
	_wave_label.offset_top = 70
	_wave_label.offset_bottom = 94
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 14)
	_wave_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
	_wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_wave_label.add_theme_constant_override("shadow_offset_x", 1)
	_wave_label.add_theme_constant_override("shadow_offset_y", 1)
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_label.text = "FORTIFY — NIGHTFALL COMES"
	root.add_child(_wave_label)

	# --- Desktop controls hint (hidden once touch mode engages) ---
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint_label.offset_left = 18
	_hint_label.offset_top = 72
	_hint_label.offset_right = 560
	_hint_label.offset_bottom = 172
	_hint_label.text = "WASD / ARROWS — move\nSHIFT — sprint   SPACE / CLICK — attack\nQ / E — rotate camera   F — use/search   TAB — backpack"
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)

	# --- Damage vignette (full-screen red, alpha driven in _process) ---
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.70, 0.05, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	# --- Touch controls (revealed on first touch) ---
	_joy = TouchJoystick.new()
	_joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joy.offset_left = 40
	_joy.offset_top = -280
	_joy.offset_right = 280
	_joy.offset_bottom = -40
	_joy.visible = false
	root.add_child(_joy)

	_attack_btn = Button.new()
	_attack_btn.text = "ATTACK"
	_attack_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack_btn.offset_left = -220
	_attack_btn.offset_top = -200
	_attack_btn.offset_right = -40
	_attack_btn.offset_bottom = -40
	_attack_btn.focus_mode = Control.FOCUS_NONE
	_attack_btn.add_theme_font_size_override("font_size", 24)
	var ab := StyleBoxFlat.new()
	ab.bg_color = Color(0.55, 0.10, 0.10, 0.55)
	ab.set_corner_radius_all(90)
	ab.border_width_left = 3
	ab.border_width_right = 3
	ab.border_width_top = 3
	ab.border_width_bottom = 3
	ab.border_color = Color(1, 0.35, 0.30, 0.70)
	_attack_btn.add_theme_stylebox_override("normal", ab)
	var ab2 := ab.duplicate() as StyleBoxFlat
	ab2.bg_color = Color(0.85, 0.20, 0.15, 0.75)
	_attack_btn.add_theme_stylebox_override("pressed", ab2)
	_attack_btn.add_theme_stylebox_override("hover", ab)
	_attack_btn.visible = false
	_attack_btn.button_down.connect(func() -> void: _attack_queued = true)
	root.add_child(_attack_btn)

	_touch_hint = Label.new()
	_touch_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_touch_hint.offset_left = -300
	_touch_hint.offset_right = 300
	_touch_hint.offset_top = -330
	_touch_hint.offset_bottom = -300
	_touch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_touch_hint.text = "Stick: move — push to edge to sprint"
	_touch_hint.add_theme_font_size_override("font_size", 15)
	_touch_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.60))
	_touch_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_hint.visible = false
	root.add_child(_touch_hint)

	# --- Death overlay ---
	_death_overlay = Button.new()
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.focus_mode = Control.FOCUS_NONE
	_death_overlay.visible = false
	var db := StyleBoxFlat.new()
	db.bg_color = Color(0.05, 0.0, 0.0, 0.82)
	_death_overlay.add_theme_stylebox_override("normal", db)
	_death_overlay.add_theme_stylebox_override("hover", db)
	_death_overlay.add_theme_stylebox_override("pressed", db)
	_death_overlay.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var dvbox := VBoxContainer.new()
	dvbox.set_anchors_preset(Control.PRESET_CENTER)
	dvbox.offset_left = -300
	dvbox.offset_right = 300
	dvbox.offset_top = -90
	dvbox.offset_bottom = 90
	dvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(dvbox)
	var dt := Label.new()
	dt.text = "YOU DIED"
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dt.add_theme_font_size_override("font_size", 56)
	dt.add_theme_color_override("font_color", Color(0.85, 0.15, 0.12))
	dt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dvbox.add_child(dt)
	var ds := Label.new()
	ds.text = "tap to wake up at the safehouse"
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ds.add_theme_font_size_override("font_size", 18)
	ds.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dvbox.add_child(ds)
	_death_overlay.pressed.connect(func() -> void: respawn_requested.emit())
	root.add_child(_death_overlay)

	# --- Phase 3: interact prompt label (bottom-center) ---
	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -300
	_prompt_label.offset_right = 300
	_prompt_label.offset_top = -352
	_prompt_label.offset_bottom = -318
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.visible = false
	root.add_child(_prompt_label)

	# --- Phase 3: touch USE button (bottom-right, above ATTACK) ---
	_use_btn = Button.new()
	_use_btn.text = "USE"
	_use_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_use_btn.offset_left = -190
	_use_btn.offset_top = -300
	_use_btn.offset_right = -60
	_use_btn.offset_bottom = -220
	_use_btn.focus_mode = Control.FOCUS_NONE
	_use_btn.add_theme_font_size_override("font_size", 20)
	var ub := StyleBoxFlat.new()
	ub.bg_color = Color(0.75, 0.60, 0.15, 0.55)
	ub.set_corner_radius_all(45)
	ub.border_width_left = 3
	ub.border_width_right = 3
	ub.border_width_top = 3
	ub.border_width_bottom = 3
	ub.border_color = Color(1.0, 0.88, 0.55, 0.70)
	_use_btn.add_theme_stylebox_override("normal", ub)
	var ub2 := ub.duplicate() as StyleBoxFlat
	ub2.bg_color = Color(0.95, 0.78, 0.25, 0.75)
	_use_btn.add_theme_stylebox_override("pressed", ub2)
	_use_btn.add_theme_stylebox_override("hover", ub)
	_use_btn.visible = false
	_use_btn.button_down.connect(func() -> void: interact_pressed.emit())
	root.add_child(_use_btn)

	# --- Wave loop: weapon display + touch weapon-swap (left of USE) ---
	_weapon_label = Label.new()
	_weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_label.offset_left = -340
	_weapon_label.offset_right = -200
	_weapon_label.offset_top = -216
	_weapon_label.offset_bottom = -192
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.add_theme_font_size_override("font_size", 15)
	_weapon_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_weapon_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_weapon_label.add_theme_constant_override("shadow_offset_x", 1)
	_weapon_label.add_theme_constant_override("shadow_offset_y", 1)
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_label.text = "NAIL BAT"
	_weapon_label.visible = false
	root.add_child(_weapon_label)

	_weapon_btn = Button.new()
	_weapon_btn.text = "SWAP"
	_weapon_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_btn.offset_left = -340
	_weapon_btn.offset_top = -300
	_weapon_btn.offset_right = -200
	_weapon_btn.offset_bottom = -220
	_weapon_btn.focus_mode = Control.FOCUS_NONE
	_weapon_btn.add_theme_font_size_override("font_size", 18)
	var wb := StyleBoxFlat.new()
	wb.bg_color = Color(0.25, 0.28, 0.35, 0.55)
	wb.set_corner_radius_all(40)
	wb.border_width_left = 3
	wb.border_width_right = 3
	wb.border_width_top = 3
	wb.border_width_bottom = 3
	wb.border_color = Color(0.70, 0.75, 0.85, 0.70)
	_weapon_btn.add_theme_stylebox_override("normal", wb)
	var wb2 := wb.duplicate() as StyleBoxFlat
	wb2.bg_color = Color(0.40, 0.44, 0.55, 0.75)
	_weapon_btn.add_theme_stylebox_override("pressed", wb2)
	_weapon_btn.add_theme_stylebox_override("hover", wb)
	_weapon_btn.visible = false
	_weapon_btn.button_down.connect(func() -> void: weapon_pressed.emit())
	root.add_child(_weapon_btn)

	# --- Phase 3: touch backpack button (top-right) ---
	_pack_btn = Button.new()
	_pack_btn.text = "PACK"
	_pack_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pack_btn.offset_left = -92
	_pack_btn.offset_top = 14
	_pack_btn.offset_right = -16
	_pack_btn.offset_bottom = 66
	_pack_btn.focus_mode = Control.FOCUS_NONE
	_pack_btn.add_theme_font_size_override("font_size", 16)
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.10, 0.11, 0.13, 0.70)
	pb.set_corner_radius_all(10)
	pb.border_width_left = 2
	pb.border_width_right = 2
	pb.border_width_top = 2
	pb.border_width_bottom = 2
	pb.border_color = Color(0.45, 0.38, 0.28, 0.9)
	_pack_btn.add_theme_stylebox_override("normal", pb)
	var pb2 := pb.duplicate() as StyleBoxFlat
	pb2.bg_color = Color(0.20, 0.21, 0.23, 0.85)
	_pack_btn.add_theme_stylebox_override("pressed", pb2)
	_pack_btn.add_theme_stylebox_override("hover", pb)
	_pack_btn.visible = false
	_pack_btn.button_down.connect(func() -> void: backpack_pressed.emit())
	root.add_child(_pack_btn)

	# --- MENU button (top-right, next to PACK): pause / seed / new game ---
	_hud_menu_btn = Button.new()
	_hud_menu_btn.text = "MENU"
	_hud_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_menu_btn.offset_left = -172
	_hud_menu_btn.offset_top = 14
	_hud_menu_btn.offset_right = -100
	_hud_menu_btn.offset_bottom = 66
	_hud_menu_btn.focus_mode = Control.FOCUS_NONE
	_hud_menu_btn.add_theme_font_size_override("font_size", 16)
	_hud_menu_btn.add_theme_stylebox_override("normal", pb)
	_hud_menu_btn.add_theme_stylebox_override("pressed", pb2)
	_hud_menu_btn.add_theme_stylebox_override("hover", pb)
	_hud_menu_btn.visible = false
	_hud_menu_btn.button_down.connect(func() -> void: menu_pressed.emit())
	root.add_child(_hud_menu_btn)

	_build_menu()

	# --- Phase 3: work progress bar (bottom-center, e.g. SEARCHING) ---
	_work_label = Label.new()
	_work_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_work_label.offset_left = -300
	_work_label.offset_right = 300
	_work_label.offset_top = -300
	_work_label.offset_bottom = -276
	_work_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_work_label.add_theme_font_size_override("font_size", 16)
	_work_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_work_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_label.visible = false
	root.add_child(_work_label)
	_work_bg = ColorRect.new()
	_work_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_work_bg.offset_left = -150
	_work_bg.offset_right = 150
	_work_bg.offset_top = -272
	_work_bg.offset_bottom = -260
	_work_bg.color = Color(0, 0, 0, 0.60)
	_work_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_bg.visible = false
	root.add_child(_work_bg)
	_work_fill = ColorRect.new()
	_work_fill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_work_fill.offset_left = -148
	_work_fill.offset_right = -148
	_work_fill.offset_top = -270
	_work_fill.offset_bottom = -262
	_work_fill.color = Color(0.95, 0.75, 0.30, 0.95)
	_work_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_fill.visible = false
	root.add_child(_work_fill)

	# --- Phase 3: sleep fade + "While You Slept" teaser ---
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	var toast_vbox := VBoxContainer.new()
	toast_vbox.set_anchors_preset(Control.PRESET_CENTER)
	toast_vbox.offset_left = -320
	toast_vbox.offset_right = 320
	toast_vbox.offset_top = -70
	toast_vbox.offset_bottom = 70
	toast_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_vbox)
	_toast = Label.new()
	_toast.text = "While You Slept..."
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 34)
	_toast.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("shadow_offset_x", 2)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	toast_vbox.add_child(_toast)
	_toast_sub = Label.new()
	_toast_sub.text = "The dead kept walking. Daybreak is yours."
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_sub.add_theme_font_size_override("font_size", 17)
	_toast_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.70))
	_toast_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_sub.visible = false
	toast_vbox.add_child(_toast_sub)


## Title / pause menu: full-screen overlay with the neighborhood seed,
## CONTINUE (pause only) and NEW GAME — NEW NEIGHBORHOOD.
func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 76) # fat-finger friendly on phones
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.15, 0.95)
	sb.set_corner_radius_all(12)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.55, 0.45, 0.30, 0.9)
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate() as StyleBoxFlat
	sb2.bg_color = Color(0.25, 0.22, 0.18, 0.95)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("hover", sb)
	return b


func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.visible = false
	add_child(_menu_root)

	_menu_dim = ColorRect.new()
	_menu_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_dim.color = Color(0.015, 0.02, 0.03, 0.96)
	_menu_root.add_child(_menu_dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -340
	vbox.offset_right = 340
	vbox.offset_top = -260
	vbox.offset_bottom = 260
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	_menu_root.add_child(vbox)

	_menu_title = Label.new()
	_menu_title.text = "LAST SHIFT"
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_title.add_theme_font_size_override("font_size", 76)
	_menu_title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.22))
	_menu_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_menu_title.add_theme_constant_override("shadow_offset_x", 4)
	_menu_title.add_theme_constant_override("shadow_offset_y", 4)
	vbox.add_child(_menu_title)

	_menu_sub = Label.new()
	_menu_sub.text = "The city fell. The streets are yours — if you survive them."
	_menu_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_sub.add_theme_font_size_override("font_size", 18)
	_menu_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	_menu_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_menu_sub.add_theme_constant_override("shadow_offset_x", 2)
	_menu_sub.add_theme_constant_override("shadow_offset_y", 2)
	_menu_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_menu_sub)

	_menu_seed = Label.new()
	_menu_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_seed.add_theme_font_size_override("font_size", 21)
	_menu_seed.add_theme_color_override("font_color", Color(0.95, 0.75, 0.30))
	_menu_seed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_menu_seed)

	_menu_continue = _menu_button("CONTINUE")
	_menu_continue.button_down.connect(func() -> void: continue_pressed.emit())
	vbox.add_child(_menu_continue)

	_menu_new = _menu_button("NEW GAME — NEW NEIGHBORHOOD")
	_menu_new.button_down.connect(func() -> void: new_game_pressed.emit())
	vbox.add_child(_menu_new)

	var hint := Label.new()
	hint.text = "Write down your seed — the same seed rebuilds the same streets."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.40))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)


func is_menu_open() -> bool:
	return _menu_open


func _set_menu(seed_text: String, title: String, show_continue: bool,
		show_sub: bool, dim_alpha := 0.96) -> void:
	_menu_open = true
	_menu_root.visible = true
	_menu_dim.color = Color(0.015, 0.02, 0.03, dim_alpha)
	_menu_title.text = title
	_menu_sub.visible = show_sub
	_menu_seed.text = seed_text
	_menu_continue.visible = show_continue
	_hud_menu_btn.visible = false
	_hud_root.visible = false


## Title screen: shown at boot when no seed is chosen yet. The dim stays
## light so the apocalyptic backdrop shows through.
func show_title() -> void:
	_set_menu("NO NEIGHBORHOOD YET — START A NEW GAME", "LAST SHIFT", false, true, 0.42)


## Pause menu: seed label, CONTINUE, NEW GAME.
func show_pause(seed: int) -> void:
	_set_menu("NEIGHBORHOOD %d" % seed, "PAUSED", true, false)


func hide_menu() -> void:
	_menu_open = false
	_menu_root.visible = false
	_hud_root.visible = true
	_hud_menu_btn.visible = true


## Loading veil: immediate tap feedback while a new neighborhood builds.
## Shown on NEW GAME tap, hidden once the run starts (scene reload frees it
## anyway — this is belt-and-suspenders for slow first builds on phones).
var _loading_label: Label

func show_loading(text: String) -> void:
	if _loading_label == null:
		_loading_label = Label.new()
		_loading_label.set_anchors_preset(Control.PRESET_CENTER)
		_loading_label.offset_left = -340
		_loading_label.offset_right = 340
		_loading_label.offset_top = 200
		_loading_label.offset_bottom = 260
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.add_theme_font_size_override("font_size", 22)
		_loading_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.60))
		_loading_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_loading_label.add_theme_constant_override("shadow_offset_x", 2)
		_loading_label.add_theme_constant_override("shadow_offset_y", 2)
		_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_root.add_child(_loading_label)
	_loading_label.text = text
	_loading_label.visible = true


func hide_loading() -> void:
	if _loading_label != null:
		_loading_label.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and not touch_mode:
		touch_mode = true
		_joy.visible = true
		_attack_btn.visible = true
		_pack_btn.visible = true
		_weapon_btn.visible = true
		_weapon_label.visible = true
		_touch_hint.visible = true
		_touch_hint_t = 6.0
		_hint_label.visible = false
		_refresh_prompt_visibility()


func _process(delta: float) -> void:
	if touch_mode:
		move_vector = _joy.output
		# Full tilt = sprint. No sprint button (mobile standard).
		sprint_held = _joy.output.length() > 0.92
		if _touch_hint_t > 0.0:
			_touch_hint_t -= delta
			if _touch_hint_t <= 0.0:
				_touch_hint.visible = false
	# Damage vignette: flash decays; low HP gets a heartbeat pulse.
	_flash = maxf(0.0, _flash - delta * 1.6)
	_pulse_t += delta # shared clock for all HUD pulses (meters, vignette)
	var a := _flash * 0.45
	if _hp_frac < 0.30 and not _death_overlay.visible:
		var beat := pow(maxf(0.0, sin(_pulse_t * 5.2)), 3.0)
		a = maxf(a, 0.10 + beat * 0.22)
	_vignette.color = Color(0.70, 0.05, 0.05, a)
	# Survival bars: pulse white when a meter is in warning (<25%).
	_stam_pulse = maxf(0.0, _stam_pulse - delta * 2.5)
	_flash_meter(_stam_fill, _stam_frac, Color(0.35, 0.78, 0.32, 0.95), _stam_pulse)
	_flash_meter(_hunger_fill, _hunger_frac, Color(0.92, 0.55, 0.18, 0.95), 0.0)
	_flash_meter(_thirst_fill, _thirst_frac, Color(0.25, 0.55, 0.95, 0.95), 0.0)
	# Dehydration: slow blue pulse around the screen edges.
	var da := 0.0
	if _dehydrated and not _death_overlay.visible:
		da = 0.07 + 0.05 * (0.5 + 0.5 * sin(_pulse_t * 3.0))
	_dehy_vignette.color = Color(0.15, 0.30, 0.65, da)
	# Phase 3: work bar + toast timers.
	if _work_t > 0.0:
		_work_t = maxf(0.0, _work_t - delta)
		var frac := 1.0 - _work_t / _work_dur
		_work_fill.offset_right = -148.0 + 296.0 * clampf(frac, 0.0, 1.0)
		if _work_t <= 0.0:
			hide_work_bar()
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
			_toast_sub.visible = false
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0 and not _interact_prompt_active:
			_prompt_label.visible = false
			_refresh_prompt_visibility()


# --- Phase 3: interact prompt + USE button ---

func show_interact_prompt(label: String) -> void:
	_interact_prompt_active = true
	if touch_mode:
		_prompt_label.text = label
	else:
		_prompt_label.text = "F — " + label
	_prompt_label.visible = true
	_refresh_prompt_visibility()


func hide_interact_prompt() -> void:
	_prompt_label.visible = false
	_interact_prompt_active = false
	_refresh_prompt_visibility()


## Transient center message ("NO AMMO", "BARRICADE BROKEN!"). Shares the
## prompt label but never fights a real interact prompt: on expiry the
## label hides only when no interact prompt is active.
func show_interact(text: String, duration := 1.5) -> void:
	_prompt_label.text = text
	_prompt_label.visible = true
	_msg_t = duration
	_refresh_prompt_visibility()


func _refresh_prompt_visibility() -> void:
	_use_btn.visible = touch_mode and _prompt_label.visible


# --- Phase 3: work progress bar ---

func show_work_bar(label: String, duration: float) -> void:
	_work_label.text = label
	_work_dur = maxf(0.05, duration)
	_work_t = _work_dur
	_work_fill.offset_right = -148.0
	_work_label.visible = true
	_work_bg.visible = true
	_work_fill.visible = true


func hide_work_bar() -> void:
	_work_t = 0.0
	_work_label.visible = false
	_work_bg.visible = false
	_work_fill.visible = false


# --- Phase 3: sleep fade + teaser ---

func fade_to_black(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0 if on else 0.0, 0.6)


func show_slept_teaser() -> void:
	_toast.visible = true
	_toast_sub.visible = true
	_toast_t = 3.2


## Wave loop: big center banner for NIGHT FALLS / WAVE SURVIVED events.
func show_banner(main_text: String, sub_text: String, duration := 4.0) -> void:
	_toast.text = main_text
	_toast_sub.text = sub_text
	_toast.visible = true
	_toast_sub.visible = true
	_toast_t = duration


## Wave loop: slim status under the clock. n=0 means daytime fortify phase.
func set_wave(n: int, remaining: int) -> void:
	if n <= 0:
		_wave_label.text = "FORTIFY — NIGHTFALL COMES"
	else:
		_wave_label.text = "WAVE %d — %d LEFT" % [n, remaining]


## Weapon display: name + ammo for guns. Desktop sees the label too.
func set_weapon(display: String) -> void:
	_weapon_label.text = display
	_weapon_label.visible = true


func queue_attack() -> void:
	_attack_queued = true


func consume_attack() -> bool:
	if _attack_queued:
		_attack_queued = false
		return true
	return false


func set_health(hp: float, max_hp: float) -> void:
	_hp_frac = clampf(hp / max_hp, 0.0, 1.0)
	_hp_fill.offset_right = 18.0 + 166.0 * _hp_frac
	_hp_fill.color = Color(0.80, 0.16, 0.14, 0.95) if _hp_frac > 0.3 \
		else Color(0.90, 0.08, 0.06, 1.0).lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_pulse_t * 8.0)))


func flash_damage() -> void:
	_flash = 1.0


## Survival meters: update the three slim bars (fractions 0..1).
func set_survival(stam_frac: float, hunger_frac: float, thirst_frac: float) -> void:
	_stam_frac = clampf(stam_frac, 0.0, 1.0)
	_hunger_frac = clampf(hunger_frac, 0.0, 1.0)
	_thirst_frac = clampf(thirst_frac, 0.0, 1.0)
	_stam_fill.offset_right = 18.0 + 166.0 * _stam_frac
	_hunger_fill.offset_right = 18.0 + 166.0 * _hunger_frac
	_thirst_fill.offset_right = 18.0 + 166.0 * _thirst_frac


func set_dehydrated(on: bool) -> void:
	_dehydrated = on


## Attack-denied feedback: the stamina bar flashes bright.
func pulse_stamina() -> void:
	_stam_pulse = 1.0


func _flash_meter(fill: ColorRect, frac: float, base: Color, pulse: float) -> void:
	var warn := frac < 0.25
	var blink := 0.0
	if warn:
		blink = 0.45 * (0.5 + 0.5 * sin(_pulse_t * 8.0))
	blink = maxf(blink, pulse * 0.6)
	fill.color = base.lerp(Color.WHITE, blink)


func show_death() -> void:
	_death_overlay.visible = true


func hide_death() -> void:
	_death_overlay.visible = false
	_flash = 0.0


func set_clock(day: int, hour: int, minute: int) -> void:
	_day_label.text = "DAY %d" % day
	_clock_label.text = "%02d:%02d" % [hour, minute]


## Minimap: attach the corner map widget (hides with the rest of the HUD).
func attach_minimap(view: Control) -> void:
	_hud_root.add_child(view)
