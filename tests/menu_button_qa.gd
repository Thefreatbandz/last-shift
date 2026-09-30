extends SceneTree
## Button-path QA: simulate REAL taps on the title screen's
## "NEW GAME — NEW NEIGHBORHOOD" button via input injection
## (InputEventScreenTouch like iOS Safari sends, plus a mouse fallback).
## NOTE: Input.parse_input_event QUEUES events; they dispatch on later
## frames, so all tap effects are asserted a few frames after injection,
## never synchronously. Asserts: tap reaches the button (signal fires),
## a fresh run starts with a valid seed, then the pause-menu NEW GAME
## path is tapped too. Also unit-checks the loading veil.
##   godot --headless --path . --script res://tests/menu_button_qa.gd

var _booted := false
var _frames := 0
var _phase := 0
var _ok := true
var _main: Node
var _press_count := 0


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", -1)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		current_scene = _main
		_main.hud.new_game_pressed.connect(_on_ng_signal)
		return false
	_frames += 1
	if _phase == 0 and _frames == 30:
		# Force the portrait design viewport before reading rects.
		root.size = Vector2i(720, 1280)
	elif _phase == 0 and _frames == 70:
		_ok = _check("title_open", _main.hud.is_menu_open(), _ok)
		var btn: Button = _main.hud.get("_menu_new")
		_ok = _check("button_exists", btn != null, _ok)
		_ok = _check("button_visible", btn.visible and btn.is_visible_in_tree(), _ok)
		var r: Rect2 = btn.get_global_rect()
		print("MENUBTN rect=", r, " viewport=", root.size)
		_ok = _check("button_in_viewport", Rect2(Vector2.ZERO, root.size).grow(-1).intersects(r), _ok)
		# Loading veil unit check (independent of tap timing).
		_main.hud.show_loading("TEST")
		var ll: Label = _main.hud.get("_loading_label")
		_ok = _check("loading_shown", ll != null and ll.visible and ll.text == "TEST", _ok)
		_main.hud.hide_loading()
		_ok = _check("loading_hidden", not ll.visible, _ok)
		# iOS-style double tap on the real button.
		_tap(r.get_center())
		_tap(r.get_center())
		_phase = 1
		_frames = 0
	elif _phase == 1 and _frames == 15:
		# Queued input has dispatched and the deferred reload has run.
		_ok = _check("signal_emitted", _press_count >= 1, _ok)
		_main = current_scene # reload freed the old scene
		_ok = _check("run_started", _main.get("_run_started") == true, _ok)
		_ok = _check("seed_chosen", int(root.get_node("RunState").get("world_seed")) >= 0, _ok)
		_ok = _check("title_closed", not _main.hud.is_menu_open(), _ok)
		# Pause-menu NEW GAME path: open pause, let the layout settle
		# (CONTINUE appears, shifting the button), then tap NEW GAME.
		_press_count = 0
		_main._on_menu_button()
		_ok = _check("pause_open", _main.hud.is_menu_open(), _ok)
		_main.hud.new_game_pressed.connect(_on_ng_signal)
		_phase = 2
		_frames = 0
	elif _phase == 2 and _frames == 5:
		var btn2: Button = _main.hud.get("_menu_new")
		_tap(btn2.get_global_rect().get_center())
		_phase = 3
		_frames = 0
	elif _phase == 3 and _frames == 15:
		_ok = _check("pause_signal", _press_count >= 1, _ok)
		_main = current_scene
		_ok = _check("pause_new_run_started", _main.get("_run_started") == true, _ok)
		_ok = _check("pause_menu_closed", not _main.hud.is_menu_open(), _ok)
		print("MENUBTN_RESULT ok=", _ok)
		quit(0 if _ok else 1)
		return true
	return false


func _on_ng_signal() -> void:
	_press_count += 1


func _tap(pos: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = pos
	Input.parse_input_event(t)
	var t2 := InputEventScreenTouch.new()
	t2.pressed = false
	t2.position = pos
	Input.parse_input_event(t2)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = pos
	Input.parse_input_event(m)
	var m2 := InputEventMouseButton.new()
	m2.button_index = MOUSE_BUTTON_LEFT
	m2.pressed = false
	m2.position = pos
	Input.parse_input_event(m2)


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("MENUBTN ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond
