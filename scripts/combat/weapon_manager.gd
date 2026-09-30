class_name WeaponManager
extends Node
## Owns the equipped weapon. The nail bat is the default and stays exactly
## as before (its numbers live here AND in PlayerCombat so combat can run
## without the manager wired). Machete / fire axe are faster/slower melee
## variants; pistol / shotgun are fired by RangedCombat.
##
## Bat stays mechanically unchanged: its profile here mirrors
## PlayerCombat's constants (swing 0.34 / cooldown 0.45 / damage 34 /
## range 2.2 / arc 65 / stamina 8 / noise 6).

signal equipped(id: String)

const BAT := "bat"
const MACHETE := "machete"
const FIRE_AXE := "fire_axe"
const PISTOL := "pistol"
const SHOTGUN := "shotgun"

# display order for the SWAP cycle
const ORDER := [BAT, MACHETE, FIRE_AXE, PISTOL, SHOTGUN]

const MELEE := {
	BAT: {"name": "NAIL BAT", "swing": 0.34, "cooldown": 0.45, "damage": 34.0,
		"range": 2.2, "arc": 65.0, "stamina": 8.0, "noise": 6.0},
	MACHETE: {"name": "MACHETE", "swing": 0.26, "cooldown": 0.36, "damage": 26.0,
		"range": 2.2, "arc": 70.0, "stamina": 6.0, "noise": 6.0},
	FIRE_AXE: {"name": "FIRE AXE", "swing": 0.42, "cooldown": 0.62, "damage": 52.0,
		"range": 2.5, "arc": 60.0, "stamina": 11.0, "noise": 7.0},
}

const GUNS := {
	PISTOL: {"name": "PISTOL", "damage": 45.0, "range": 20.0, "mag": 12,
		"reload": 1.6, "noise": 42.0, "spread": 1.5, "pellets": 1,
		"cooldown": 0.28, "stamina": 3.0, "ammo": "ammo_9mm", "sound": "gunshot"},
	SHOTGUN: {"name": "SHOTGUN", "damage": 16.0, "range": 13.0, "mag": 6,
		"reload": 2.6, "noise": 58.0, "spread": 6.0, "pellets": 6,
		"cooldown": 0.85, "stamina": 6.0, "ammo": "shells", "sound": "shotgun"},
}

# LootDefs id for each equippable ("" = always available).
const LOOT_ID := {
	BAT: "",
	MACHETE: "machete",
	FIRE_AXE: "fire_axe",
	PISTOL: "pistol",
	SHOTGUN: "shotgun",
}

var current := BAT

var _inv: Inventory
var _hud: Hud


static func is_gun(id: String) -> bool:
	return GUNS.has(id)


static func is_melee(id: String) -> bool:
	return MELEE.has(id)


func setup(inv: Inventory, hud: Hud) -> void:
	_inv = inv
	_hud = hud
	_refresh_label()


## A weapon is usable if owned (bat always). Guns need the gun item too.
func can_equip(id: String) -> bool:
	var loot: String = LOOT_ID.get(id, "")
	if loot == "":
		return true
	return _inv != null and _inv.count(loot) > 0


func equip(id: String) -> bool:
	if not MELEE.has(id) and not GUNS.has(id):
		return false
	if not can_equip(id):
		return false
	if current == id:
		return true
	current = id
	_refresh_label()
	equipped.emit(id)
	return true


## SWAP button / Q-style cycle: next owned weapon in ORDER, wrapping.
func cycle() -> bool:
	var idx := ORDER.find(current)
	for step in ORDER.size():
		idx = (idx + 1) % ORDER.size()
		var cand: String = ORDER[idx]
		if can_equip(cand):
			return equip(cand)
	return false


## Touch display string, e.g. "PISTOL 8/24". Desktop uses it too.
func display() -> String:
	var id := current
	if GUNS.has(id):
		var g: Dictionary = GUNS[id]
		var ranged := get_node_or_null("../Ranged") as RangedCombat
		var mag := ranged.mag_in(id) if ranged != null else int(g["mag"])
		var reserve := _inv.count(g["ammo"]) if _inv != null else 0
		return "%s %d/%d" % [g["name"], mag, reserve]
	return MELEE[id]["name"]


func _refresh_label() -> void:
	if _hud != null:
		_hud.set_weapon(display())


## Keep the HUD ammo line fresh after shots / reloads / looting.
func refresh_display() -> void:
	_refresh_label()
