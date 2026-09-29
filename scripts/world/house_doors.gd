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
var _inv: Inventory
var _ids := {} # house index -> interact id
var _busy := {} # house index -> true while swinging
var _roof_hidden := {}
var _bids := {} # building index -> interact id
var _bbusy := {} # building index -> true while swinging
var _broof_hidden := {}


func setup(hood: NeighborhoodBuilder, interact: InteractManager,
		p: PlayerController, safehouse: Safehouse, inv: Inventory) -> void:
	_hood = hood
	_interact = interact
	_player = p
	_inv = inv
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
	# Commercial buildings. Locked doors (police station) show LOCKED and
	# need the police key or a crafted lockpick.
	for j in _hood.buildings.size():
		var b := _hood.buildings[j] as Dictionary
		var bdoor := b["door"] as Dictionary
		var bpivot := bdoor["pivot"] as Node3D
		var locked := bool(bdoor.get("locked", false))
		var bid := _interact.register(bpivot,
			"LOCKED" if locked else "OPEN DOOR", 2.8, _toggle_b.bind(j))
		_bids[j] = bid
		_bbusy[j] = false
		_broof_hidden[j] = false
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


## Building doors. Locked doors (police station) refuse to swing until the
## police key or a lockpick is consumed.
func building_door_count() -> int:
	return _hood.buildings.size()


func is_building_locked(j: int) -> bool:
	var b := _hood.buildings[j] as Dictionary
	return bool((b["door"] as Dictionary).get("locked", false))


## Tries key first, then lockpick. Returns true if the door is now unlocked.
func try_unlock_building(j: int) -> bool:
	var b := _hood.buildings[j] as Dictionary
	var door := b["door"] as Dictionary
	if not bool(door.get("locked", false)):
		return true
	if _inv != null and _inv.count(LootDefs.POLICE_KEY) > 0:
		_inv.remove(LootDefs.POLICE_KEY, 1)
		_unlock_building(j, door)
		return true
	if _inv != null and _inv.count(LootDefs.LOCKPICK) > 0:
		_inv.remove(LootDefs.LOCKPICK, 1)
		_unlock_building(j, door)
		return true
	return false


func _unlock_building(j: int, door: Dictionary) -> void:
	door["locked"] = false
	_interact.set_prompt(int(_bids[j]), "OPEN DOOR")
	Sound.play_3d("door", (door["pos"] as Vector3) + Vector3(0, 1.2, 0))


func _toggle_b(j: int) -> void:
	if bool(_bbusy.get(j, false)):
		return
	var b := _hood.buildings[j] as Dictionary
	var door := b["door"] as Dictionary
	if bool(door.get("locked", false)) and not try_unlock_building(j):
		# No key, no lockpick: thud + a temporary hint prompt.
		_interact.set_prompt(int(_bids[j]), "LOCKED — NEED KEY")
		Sound.play("click")
		var tw := create_tween()
		tw.tween_interval(1.6)
		tw.tween_callback(_revert_lock_prompt.bind(j))
		return
	var will_open := not bool(door["open"])
	Sound.play_3d("door", (door["pos"] as Vector3) + Vector3(0, 1.2, 0))
	set_building_door_open(j, will_open, true)


func _revert_lock_prompt(j: int) -> void:
	if is_building_locked(j):
		_interact.set_prompt(int(_bids[j]), "LOCKED")


func set_building_door_open(j: int, open: bool, animate := true) -> void:
	if j < 0 or j >= _hood.buildings.size():
		return
	var b := _hood.buildings[j] as Dictionary
	var door := b["door"] as Dictionary
	door["open"] = open
	var pivot := door["pivot"] as Node3D
	_blocker_set(door, open)
	if animate:
		_bbusy[j] = true
		var tw := create_tween()
		tw.tween_property(pivot, "rotation:y",
			OPEN_ANGLE if open else 0.0, SWING_TIME)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_clear_bbusy.bind(j))
	else:
		pivot.rotation.y = OPEN_ANGLE if open else 0.0
	_interact.set_prompt(int(_bids[j]), "CLOSE DOOR" if open else "OPEN DOOR")


func _clear_bbusy(j: int) -> void:
	_bbusy[j] = false


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
	# Commercial buildings hide their roof group the same way.
	for j in _hood.buildings.size():
		var b := _hood.buildings[j] as Dictionary
		var bp := b["pos"] as Vector3
		var binside := absf(pp.x - bp.x) < float(b["w"]) * 0.5 \
			and absf(pp.z - bp.z) < float(b["d"]) * 0.5
		if binside != bool(_broof_hidden[j]):
			_broof_hidden[j] = binside
			(b["roof"] as Node3D).visible = not binside
