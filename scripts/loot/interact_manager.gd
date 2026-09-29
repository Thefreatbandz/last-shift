class_name InteractManager
extends Node3D
## Phase 3: one shared "nearest interactable" system. Anything searchable /
## usable registers a target node + prompt + action. Shows one floating
## world prompt and drives the HUD prompt / touch USE button. Desktop: F.

var player: PlayerController
var hud: Hud

var _entries: Array = [] # {node, prompt, radius, action, enabled}
var _current := -1
var _prompt_3d: Label3D


func _ready() -> void:
	_prompt_3d = Label3D.new()
	_prompt_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_3d.font_size = 64
	# Constant on-screen size: the label can never balloon when the camera
	# gets close (Tbandz iPhone report). Tuned via screenshot.
	_prompt_3d.fixed_size = true
	_prompt_3d.pixel_size = 0.0016
	_prompt_3d.modulate = Color(1.0, 0.88, 0.55)
	_prompt_3d.outline_size = 12
	_prompt_3d.outline_modulate = Color(0, 0, 0, 0.85)
	_prompt_3d.shaded = false
	_prompt_3d.visible = false
	# Fade out beyond ~8m so distant prompts never linger.
	_prompt_3d.visibility_range_end = 8.0
	_prompt_3d.visibility_range_end_margin = 3.0
	add_child(_prompt_3d)


## Returns an id for set_enabled / set_prompt.
func register(target: Node3D, prompt: String, radius: float, action: Callable) -> int:
	_entries.append({
		"node": target, "prompt": prompt, "radius": radius,
		"action": action, "enabled": true,
	})
	return _entries.size() - 1


func set_enabled(id: int, on: bool) -> void:
	if id >= 0 and id < _entries.size():
		(_entries[id] as Dictionary)["enabled"] = on
		if id == _current and not on:
			_current = -1
			_refresh_prompt()


func set_prompt(id: int, prompt: String) -> void:
	if id >= 0 and id < _entries.size():
		(_entries[id] as Dictionary)["prompt"] = prompt
		if id == _current:
			_refresh_prompt()


func try_interact() -> void:
	if _current < 0 or _current >= _entries.size():
		return
	var e := _entries[_current] as Dictionary
	if not bool(e["enabled"]):
		return
	(e["action"] as Callable).call()


func clear_current() -> void:
	_current = -1
	_refresh_prompt()


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("interact"):
		try_interact()
	var best := -1
	var best_d := 9999.0
	var pp := player.global_position
	for i in _entries.size():
		var e := _entries[i] as Dictionary
		if not bool(e["enabled"]):
			continue
		var n := e["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var d := pp.distance_to(n.global_position)
		if d < float(e["radius"]) and d < best_d:
			best = i
			best_d = d
	if best != _current:
		_current = best
		_refresh_prompt()


func _refresh_prompt() -> void:
	if _current < 0 or hud == null:
		_prompt_3d.visible = false
		if hud != null:
			hud.hide_interact_prompt()
		return
	var e := _entries[_current] as Dictionary
	var n := e["node"] as Node3D
	var label := String(e["prompt"])
	if hud.touch_mode:
		_prompt_3d.text = label
	else:
		_prompt_3d.text = "[F]  " + label
	_prompt_3d.global_position = n.global_position + Vector3(0, 1.7, 0)
	_prompt_3d.visible = true
	hud.show_interact_prompt(label)
