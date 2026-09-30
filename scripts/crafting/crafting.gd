class_name Crafting
extends Node
## Phase 3: workbench recipes. Costs come from the Inventory; effects hook
## into combat (spiked bat) and medical/ammo supplies (health kit, 9mm,
## shells). Emits `crafted`.

signal crafted(recipe_id: String)

const RECIPES := [
	{"id": "spiked_bat", "name": "Spiked Bat", "cost": {"scrap": 3},
		"desc": "+12 bat damage. Nails through a bat.", "once": true},
	{"id": "bandage", "name": "Bandage", "cost": {"cloth": 1},
		"desc": "Heals 25 HP.", "once": false},
	{"id": "field_medkit", "name": "Field Medkit", "cost": {"cloth": 2, "scrap": 1},
		"desc": "Heals 60 HP.", "once": false},
	# Wave loop: the old abstract safehouse barricade is retired — real door
	# barricades live in the BarricadeManager. Crafting covers ammo/medical.
	{"id": "health_kit", "name": "Health Kit", "cost": {"cloth": 2, "bandage": 1},
		"desc": "Slow to apply. Heals 70 HP.", "once": false},
	{"id": "ammo_9mm", "name": "9mm Rounds", "cost": {"scrap": 2},
		"desc": "Hand-load 6 pistol rounds.", "once": false},
	{"id": "shells", "name": "Shotgun Shells", "cost": {"scrap": 2},
		"desc": "Hand-load 4 shells.", "once": false},
	{"id": "lockpick", "name": "Lockpick", "cost": {"scrap": 2},
		"desc": "Opens one locked door. Single use.", "once": false},
]

var inventory: Inventory
var safehouse: Safehouse
var combat: PlayerCombat

var _done: Dictionary = {}


func recipe_by_id(id: String) -> Dictionary:
	for r in RECIPES:
		if String((r as Dictionary)["id"]) == id:
			return r
	return {}


func is_done(id: String) -> bool:
	return bool(_done.get(id, false))


func can_craft(id: String) -> bool:
	var r := recipe_by_id(id)
	if r.is_empty() or is_done(id):
		return false
	for k in (r["cost"] as Dictionary).keys():
		var key := String(k)
		if inventory.count(key) < int((r["cost"] as Dictionary)[key]):
			return false
	return true


func cost_text(id: String) -> String:
	var r := recipe_by_id(id)
	var parts: PackedStringArray = []
	for k in (r["cost"] as Dictionary).keys():
		var key := String(k)
		parts.append("%dx %s" % [int((r["cost"] as Dictionary)[key]), LootDefs.item_name(key)])
	return " + ".join(parts)


func craft(id: String) -> bool:
	if not can_craft(id):
		return false
	var r := recipe_by_id(id)
	for k in (r["cost"] as Dictionary).keys():
		inventory.remove(String(k), int((r["cost"] as Dictionary)[k]))
	match id:
		"spiked_bat":
			combat.add_damage_bonus(12.0)
			combat.add_spikes()
			_done[id] = true
		"bandage":
			inventory.add("bandage", 1)
		"field_medkit":
			inventory.add("medkit", 1)
		"health_kit":
			inventory.add("health_kit", 1)
		"ammo_9mm":
			inventory.add("ammo_9mm", 6)
		"shells":
			inventory.add("shells", 4)
		"lockpick":
			inventory.add("lockpick", 1)
	Sound.play("craft") # workbench clank; main plays the success chime on `crafted`
	crafted.emit(id)
	return true
