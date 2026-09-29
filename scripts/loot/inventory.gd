class_name Inventory
extends Node
## Phase 3: player item counts + the safehouse stash. Emits `changed` on any
## mutation so panels refresh. `use()` needs a PlayerHealth hookup from main.

signal changed

var items: Dictionary = {} # id -> int
var stash: Dictionary = {} # id -> int

var health: PlayerHealth


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


## Consume one usable item (food / meds). Returns false if wasted or missing.
func use(id: String) -> bool:
	if not LootDefs.is_usable(id) or count(id) <= 0:
		return false
	if health == null or health.is_dead():
		return false
	if health.hp >= PlayerHealth.MAX_HP:
		return false
	if not remove(id, 1):
		return false
	health.heal(float(LootDefs.item_heal(id)))
	return true


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
