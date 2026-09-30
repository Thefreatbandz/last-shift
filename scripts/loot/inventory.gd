class_name Inventory
extends Node
## Phase 3: player item counts + the safehouse stash. Emits `changed` on any
## mutation so panels refresh. `use()` needs a PlayerHealth hookup from main.

signal changed

var items: Dictionary = {} # id -> int
var stash: Dictionary = {} # id -> int

var health: PlayerHealth
var survival: SurvivalStats # set by main; food/water restore meters
var hud: Hud # set by main; timed medical use drives the work bar
var visual: PlayerVisual # set by main; bandaging plays the eat pose

var _using := "" # timed medical item currently being applied
var _use_t := 0.0


func _ready() -> void:
	# Cancel timed healing when hurt (connected once health is set).
	set_process(false)


func wire_health() -> void:
	if health != null and not health.damaged.is_connected(_on_damaged):
		health.damaged.connect(_on_damaged)


func using_item() -> bool:
	return _using != ""


func count(id: String) -> int:
	return int(items.get(id, 0))


func add(id: String, n: int = 1) -> void:
	items[id] = count(id) + n
	changed.emit()


func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left := count(id) - n
	if left <= 0:
		items.erase(id)
	else:
		items[id] = left
	changed.emit()
	return true


## Consume one usable item. Food restores hunger, water restores thirst,
## instant meds heal HP. Bandage / health kit / painkillers are TIMED:
## use() starts the application (work bar + pose); the heal lands when it
## finishes, and taking damage cancels it (item is still consumed).
## Each refuses when its target stat is already full.
## Returns false if wasted, missing, or already applying something.
func use(id: String) -> bool:
	if not LootDefs.is_usable(id) or count(id) <= 0:
		return false
	if health == null or health.is_dead():
		return false
	if _using != "":
		return false
	match id:
		LootDefs.CANNED_FOOD:
			if survival == null or survival.hunger >= SurvivalStats.MAX:
				return false
		LootDefs.WATER:
			if survival == null or survival.thirst >= SurvivalStats.MAX:
				return false
		_:
			if health.hp >= PlayerHealth.MAX_HP:
				return false
	if not remove(id, 1):
		return false
	if LootDefs.USE_TIME.has(id):
		_start_timed_use(id)
		return true
	_apply_instant(id)
	return true


func _apply_instant(id: String) -> void:
	match id:
		LootDefs.CANNED_FOOD:
			survival.eat_food()
		LootDefs.WATER:
			survival.drink_water()
		_:
			health.heal(float(LootDefs.item_heal(id)))
			Sound.play("eat")


func _start_timed_use(id: String) -> void:
	_using = id
	_use_t = float(LootDefs.USE_TIME[id])
	set_process(true)
	if hud != null:
		hud.show_work_bar(_use_label(id), _use_t)
	if visual != null:
		visual.play_eat()
	Sound.play("heal")


func _use_label(id: String) -> String:
	match id:
		LootDefs.BANDAGE:
			return "BANDAGING"
		LootDefs.HEALTH_KIT:
			return "HEALTH KIT"
		LootDefs.PAINKILLERS:
			return "PAINKILLERS"
	return "USING"


func _process(delta: float) -> void:
	if _using == "":
		set_process(false)
		return
	_use_t -= delta
	if _use_t > 0.0:
		return
	var id := _using
	_using = ""
	set_process(false)
	if hud != null:
		hud.hide_work_bar()
	health.heal(float(LootDefs.item_heal(id)))
	if id == LootDefs.PAINKILLERS and survival != null:
		survival.boost_stamina_regen(
			LootDefs.PAINKILLER_REGEN_MULT, LootDefs.PAINKILLER_REGEN_SECS)
	Sound.play("heal", 0.0, 1.2)


func _on_damaged() -> void:
	# Hit mid-application: the effect is lost (item already consumed).
	if _using != "":
		_using = ""
		set_process(false)
		if hud != null:
			hud.hide_work_bar()
			hud.show_interact("INTERRUPTED!", 1.2)


func stash_count(id: String) -> int:
	return int(stash.get(id, 0))


func deposit(id: String) -> bool:
	if count(id) <= 0:
		return false
	remove(id, 1)
	stash[id] = stash_count(id) + 1
	changed.emit()
	return true


func withdraw(id: String) -> bool:
	if stash_count(id) <= 0:
		return false
	var left := stash_count(id) - 1
	if left <= 0:
		stash.erase(id)
	else:
		stash[id] = left
	add(id, 1)
	return true
