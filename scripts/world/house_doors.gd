class_name HouseDoors
extends Node3D
## QA pass: owns every house door. Registers OPEN DOOR / CLOSE DOOR
## interactions, swings the hinge pivot, toggles the doorway blocker, and
## hides each house's roof group while the player is inside (the angled
## camera would otherwise clip through it).
## The safehouse door stays locked until Safehouse.claimed_house fires.

const OPEN_ANGLE := -1.85
const SWING_TIME := 0.7

var _hood: NeighborhoodBuilder
var _interact: InteractManager
var _player: PlayerController
var _ids := {} # house index -> interact id
var _busy := {} # house index -> true while swinging
var _roof_hidden := {}


func setup(hood: NeighborhoodBuilder, interact: InteractManager,
		p: PlayerController, safehouse: Safehouse) -> void:
	_hood = hood
	_interact = interact
	_player = p
	for i in _hood.houses.size():
		var h := _hood.houses[i] as Dictionary
		var door := h["door"] as Dictionary
		var pivot := door["pivot"] as Node3D
		var id := _interact.register(pivot, "OPEN DOOR", 2.8, _toggle.bind(i))
		_ids[i] = id
		_busy[i] = false
		_roof_hidden[i] = false
		if bool(door["safehouse"]):
			_interact.set_enabled(id, false) # boards hold it until claimed
	safehouse.claimed_house.connect(_on_safehouse_claimed)
	safehouse.doors = self


func safehouse_door_index() -> int:
	for i in _hood.houses.size():
		var door := (_hood.houses[i] as Dictionary)["door"] as Dictionary
		if bool(door["safehouse"]):
			return i
	return -1


func set_door_open(i: int, open: bool, animate := true) -> void:
	if i < 0 or i >= _hood.houses.size():
		return
	var h := _hood.houses[i] as Dictionary
	var door := h["door"] as Dictionary
	door["open"] = open
	var pivot := door["pivot"] as Node3D
	_blocker_set(door, open)
	if animate:
		_busy[i] = true
		var tw := create_tween()
		tw.tween_property(pivot, "rotation:y",
			OPEN_ANGLE if open else 0.0, SWING_TIME)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_clear_busy.bind(i))
	else:
		pivot.rotation.y = OPEN_ANGLE if open else 0.0
	_interact.set_prompt(int(_ids[i]), "CLOSE DOOR" if open else "OPEN DOOR")


func _clear_busy(i: int) -> void:
	_busy[i] = false


func _toggle(i: int) -> void:
	if bool(_busy.get(i, false)):
		return
	var h := _hood.houses[i] as Dictionary
	var door := h["door"] as Dictionary
	var will_open := not bool(door["open"])
	Sound.play_3d("door", (door["pos"] as Vector3) + Vector3(0, 1.2, 0))
	set_door_open(i, will_open, true)


func _blocker_set(door: Dictionary, open: bool) -> void:
	# Called from input context (InteractManager runs in physics) — defer.
	var blocker := door["blocker"] as StaticBody3D
	if is_instance_valid(blocker) and blocker.get_child_count() > 0:
		(blocker.get_child(0) as CollisionShape3D).set_deferred("disabled", open)


func _on_safehouse_claimed() -> void:
	var i := safehouse_door_index()
	if i >= 0:
		# Claim animation already swung the door via set_door_open.
		_interact.set_enabled(int(_ids[i]), true)


func _process(_delta: float) -> void:
	if _player == null or _hood == null:
		return
	var pp := _player.global_position
	for i in _hood.houses.size():
		var h := _hood.houses[i] as Dictionary
		var c := h["pos"] as Vector3
		var inside := absf(pp.x - c.x) < float(h["w"]) * 0.5 \
			and absf(pp.z - c.z) < float(h["d"]) * 0.5
		if inside != bool(_roof_hidden[i]):
			_roof_hidden[i] = inside
			(h["roof"] as Node3D).visible = not inside
