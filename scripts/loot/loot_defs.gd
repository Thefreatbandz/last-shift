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

# Grid display order for panels.
const ORDER := [CANNED_FOOD, WATER, MEDKIT, BANDAGE, MEDICINE, POLICE_KEY,
	LOCKPICK, RIFLE, AMMO, SCRAP, CLOTH]

const NAMES := {
	CANNED_FOOD: "Canned Food",
	WATER: "Clean Water",
	MEDKIT: "Medkit",
	BANDAGE: "Bandage",
	MEDICINE: "Medicine",
	POLICE_KEY: "Police Key",
	LOCKPICK: "Lockpick",
	RIFLE: "Rifle",
	AMMO: "Ammo",
	SCRAP: "Scrap Metal",
	CLOTH: "Cloth",
}

const HEAL := {
	CANNED_FOOD: 25.0,
	WATER: 10.0,
	MEDKIT: 60.0,
	BANDAGE: 25.0,
	MEDICINE: 80.0,
}

const COLORS := {
	CANNED_FOOD: Color(0.85, 0.45, 0.20),
	WATER: Color(0.25, 0.55, 0.90),
	MEDKIT: Color(0.85, 0.20, 0.20),
	BANDAGE: Color(0.90, 0.88, 0.80),
	MEDICINE: Color(0.55, 0.92, 0.62),
	POLICE_KEY: Color(0.85, 0.70, 0.25),
	LOCKPICK: Color(0.70, 0.70, 0.72),
	RIFLE: Color(0.35, 0.30, 0.25),
	AMMO: Color(0.80, 0.60, 0.20),
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
