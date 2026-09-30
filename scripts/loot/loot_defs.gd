class_name LootDefs
extends RefCounted
## Phase 3 loot table: item ids, display names, heal values, colors.

const SCRAP := "scrap"
const CLOTH := "cloth"
const CANNED_FOOD := "canned_food"
const WATER := "water"
const MEDKIT := "medkit"
const BANDAGE := "bandage"
# Building-types items: medicine (strong heal), police key + lockpick (locked
# doors), rifle + ammo (INERT Phase-A loot — no weapon mechanics yet; they
# become a real weapon class in Phase B).
const MEDICINE := "medicine"
const POLICE_KEY := "police_key"
const LOCKPICK := "lockpick"
const RIFLE := "rifle"
const AMMO := "ammo"
# Wave-pivot items: wood (barricades), working guns + ammo, extra melee,
# medical supplies.
const WOOD := "wood"
const PISTOL := "pistol"
const SHOTGUN := "shotgun"
const AMMO_9MM := "ammo_9mm"
const SHELLS := "shells"
const MACHETE := "machete"
const FIRE_AXE := "fire_axe"
const HEALTH_KIT := "health_kit"
const PAINKILLERS := "painkillers"

# Grid display order for panels.
const ORDER := [CANNED_FOOD, WATER, MEDKIT, BANDAGE, HEALTH_KIT, PAINKILLERS,
	MEDICINE, POLICE_KEY, LOCKPICK, PISTOL, SHOTGUN, AMMO_9MM, SHELLS,
	RIFLE, AMMO, MACHETE, FIRE_AXE, WOOD, SCRAP, CLOTH]

const NAMES := {
	CANNED_FOOD: "Canned Food",
	WATER: "Clean Water",
	MEDKIT: "Medkit",
	BANDAGE: "Bandage",
	HEALTH_KIT: "Health Kit",
	PAINKILLERS: "Painkillers",
	MEDICINE: "Medicine",
	POLICE_KEY: "Police Key",
	LOCKPICK: "Lockpick",
	PISTOL: "Pistol",
	SHOTGUN: "Shotgun",
	AMMO_9MM: "9mm Rounds",
	SHELLS: "Shotgun Shells",
	RIFLE: "Rifle",
	AMMO: "Ammo",
	MACHETE: "Machete",
	FIRE_AXE: "Fire Axe",
	WOOD: "Wood Planks",
	SCRAP: "Scrap Metal",
	CLOTH: "Cloth",
}

const HEAL := {
	CANNED_FOOD: 25.0,
	WATER: 10.0,
	MEDKIT: 60.0,
	BANDAGE: 25.0,
	HEALTH_KIT: 70.0,
	PAINKILLERS: 30.0,
	MEDICINE: 80.0,
}

# Wave loop: timed medical use (seconds). Bandage is quick, health kit is
# slow, painkillers are fast + grant a stamina-regen boost. Medkit/medicine
# stay instant (field medicine vs. hospital supplies).
const USE_TIME := {
	BANDAGE: 1.2,
	HEALTH_KIT: 3.5,
	PAINKILLERS: 1.0,
}

const PAINKILLER_REGEN_MULT := 1.8
const PAINKILLER_REGEN_SECS := 60.0

const COLORS := {
	CANNED_FOOD: Color(0.85, 0.45, 0.20),
	WATER: Color(0.25, 0.55, 0.90),
	MEDKIT: Color(0.85, 0.20, 0.20),
	BANDAGE: Color(0.90, 0.88, 0.80),
	HEALTH_KIT: Color(0.95, 0.35, 0.35),
	PAINKILLERS: Color(0.95, 0.75, 0.30),
	MEDICINE: Color(0.55, 0.92, 0.62),
	POLICE_KEY: Color(0.85, 0.70, 0.25),
	LOCKPICK: Color(0.70, 0.70, 0.72),
	PISTOL: Color(0.25, 0.25, 0.28),
	SHOTGUN: Color(0.35, 0.22, 0.12),
	AMMO_9MM: Color(0.85, 0.65, 0.25),
	SHELLS: Color(0.75, 0.25, 0.15),
	RIFLE: Color(0.35, 0.30, 0.25),
	AMMO: Color(0.80, 0.60, 0.20),
	MACHETE: Color(0.60, 0.62, 0.65),
	FIRE_AXE: Color(0.70, 0.20, 0.12),
	WOOD: Color(0.55, 0.38, 0.22),
	SCRAP: Color(0.55, 0.57, 0.60),
	CLOTH: Color(0.70, 0.62, 0.45),
}


static func item_name(id: String) -> String:
	return String(NAMES.get(id, id))


static func item_heal(id: String) -> float:
	return float(HEAL.get(id, 0.0))


static func item_color(id: String) -> Color:
	return COLORS.get(id, Color.GRAY) as Color


static func is_usable(id: String) -> bool:
	return HEAL.has(id)
