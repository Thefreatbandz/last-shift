extends Node
## Minimal Sound-autoload stand-in for headless QA scripts that touch
## classes referencing the Sound singleton (autoloads aren't registered
## in bare --script SceneTree mode). Swallows every call used by the game.


func _ready() -> void:
	pass


func _unhandled(_property, _value) -> void:
	pass


func _get(property: StringName):
	return null


func _set(property: StringName, value) -> bool:
	return true


func play_3d(_name: String, _pos: Vector3, _vol := 1.0) -> void:
	pass


func play(_name: String, _vol := 1.0) -> void:
	pass


func bind_time(_t) -> void:
	pass
