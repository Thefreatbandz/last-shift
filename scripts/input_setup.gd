class_name InputSetup
extends RefCounted
## Registers the game's input actions at runtime (keeps project.godot clean
## and avoids brittle serialized InputEvent objects).

static func configure() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("sprint", [KEY_SHIFT])
	_bind("rotate_left", [KEY_Q])
	_bind("rotate_right", [KEY_E])
	_bind("attack", [KEY_SPACE])
	_bind("interact", [KEY_F]) # Phase 3: use / search / claim
	_bind("inventory", [KEY_TAB, KEY_I]) # Phase 3: backpack panel
	_bind("map", [KEY_M]) # minimap: tap the corner widget or M for full map
	_bind("menu", [KEY_ESCAPE]) # title/pause menu: Esc on desktop, MENU button on touch
	# Left mouse click also attacks (desktop). Re-applied cleanly so
	# repeated configure() calls never stack duplicate events.
	InputMap.action_erase_events("attack")
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_SPACE
	InputMap.action_add_event("attack", key_ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)


static func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
