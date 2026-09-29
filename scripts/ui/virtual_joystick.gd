class_name TouchJoystick
extends Control
## Touch joystick: fixed base, knob follows the drag within a radius.
## Tracks a single touch index so it multitouches cleanly with buttons.
## `output` is a -1..1 Vector2 (screen space: up = -Y = forward).

var output := Vector2.ZERO
var radius := 110.0

var _touch := -1
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1 and get_global_rect().has_point(t.position):
			_touch = t.index
			_update_knob(t.position)
			accept_event()
		elif not t.pressed and t.index == _touch:
			_touch = -1
			_knob = Vector2.ZERO
			output = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			_update_knob(d.position)
			accept_event()


func _update_knob(p: Vector2) -> void:
	var off := p - get_global_rect().get_center()
	if off.length() > radius:
		off = off.normalized() * radius
	_knob = off
	output = off / radius
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius, Color(0, 0, 0, 0.35))
	draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	draw_circle(c + _knob, 44.0, Color(1, 1, 1, 0.28))
