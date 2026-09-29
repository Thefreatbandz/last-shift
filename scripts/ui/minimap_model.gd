class_name MinimapModel
extends Node
## Minimap data model: owns the fog-of-war grid and gathers world state for
## the map views. Ticks at 10Hz (no per-frame work); views redraw on
## `updated`. North-up: world -Z is up, +X is right.

const CELL := 2.0 # fog cell size, meters
const HALF := 74.0 # must match NeighborhoodBuilder.MAP_HALF
const GRID := 74 # cells per side (covers the full 148m map)
const REVEAL_RADIUS := 12.0
const ZOMBIE_RANGE := 25.0
const TICK := 0.1

signal updated

var seed := -1

var _player: PlayerController
var _visual: PlayerVisual
var _hood: NeighborhoodBuilder
var _zombies: ZombieManager
var _loot: LootManager
var _safehouse: Safehouse

var _fog := PackedByteArray()
var _tick_t := 0.0
var _roads: Array = []
var _gas := Rect2()

# Reused per-tick mark lists (cleared + refilled, never reallocated hot).
var _zdots: Array[Vector2] = []
var _cun: Array[Vector2] = [] # unsearched containers
var _csearched: Array[Vector2] = [] # searched containers


func setup(p: PlayerController, v: PlayerVisual, hood: NeighborhoodBuilder,
		z: ZombieManager, loot: LootManager, sh: Safehouse) -> void:
	_player = p
	_visual = v
	_hood = hood
	_zombies = z
	_loot = loot
	_safehouse = sh
	seed = hood.world_seed
	_roads = hood.get_road_rects()
	_gas = hood.get_gas_rect()
	_fog = PackedByteArray()
	_fog.resize(GRID * GRID)
	_reveal(_player.global_position.x, _player.global_position.z,
		REVEAL_RADIUS + 6.0)


func _cell_index(wx: float, wz: float) -> int:
	var cx := clampi(int(floor((wx + HALF) / CELL)), 0, GRID - 1)
	var cz := clampi(int(floor((wz + HALF) / CELL)), 0, GRID - 1)
	return cz * GRID + cx


func is_revealed(wx: float, wz: float) -> bool:
	if _fog.is_empty():
		return false
	return _fog[_cell_index(wx, wz)] == 1


func _reveal(wx: float, wz: float, radius: float) -> void:
	var cr := int(ceil(radius / CELL))
	var ccx := clampi(int(floor((wx + HALF) / CELL)), 0, GRID - 1)
	var ccz := clampi(int(floor((wz + HALF) / CELL)), 0, GRID - 1)
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var ix := ccx + dx
			var iz := ccz + dz
			if ix < 0 or iz < 0 or ix >= GRID or iz >= GRID:
				continue
			# Cell-center distance check keeps the reveal circular.
			var cell_wx := (float(ix) + 0.5) * CELL - HALF
			var cell_wz := (float(iz) + 0.5) * CELL - HALF
			if Vector2(cell_wx - wx, cell_wz - wz).length() <= radius:
				_fog[iz * GRID + ix] = 1


func _process(delta: float) -> void:
	_tick_t += delta
	if _tick_t < TICK:
		return
	_tick_t = 0.0
	if not is_instance_valid(_player):
		return
	var pp := _player.global_position
	_reveal(pp.x, pp.z, REVEAL_RADIUS)
	_rebuild_marks(pp)
	updated.emit()


func _rebuild_marks(pp: Vector3) -> void:
	_zdots.clear()
	for z in _zombies.living_zombies():
		var zp := (z as Node3D).global_position
		if Vector2(zp.x - pp.x, zp.z - pp.z).length() <= ZOMBIE_RANGE:
			_zdots.append(Vector2(zp.x, zp.z))
	_cun.clear()
	_csearched.clear()
	for c in _loot.get_containers():
		var cp := (c as Node3D).global_position
		if (c as LootContainer).searched:
			_csearched.append(Vector2(cp.x, cp.z))
		else:
			_cun.append(Vector2(cp.x, cp.z))


# --- Read access for MapDraw (all map-space: x = world x, y = world z) ---

func player_pos() -> Vector2:
	var pp := _player.global_position
	return Vector2(pp.x, pp.z)


func player_yaw() -> float:
	return _visual.rotation.y


func houses() -> Array:
	return _hood.houses


func safehouse_index() -> int:
	return _hood.safehouse_index


func safehouse_pos() -> Vector2:
	var sp := _hood.safehouse_door_pos
	return Vector2(sp.x, sp.z)


func is_claimed() -> bool:
	return _safehouse.claimed


func road_rects() -> Array:
	return _roads


func gas_rect() -> Rect2:
	return _gas


func zombie_dots() -> Array[Vector2]:
	return _zdots


func containers_unsearched() -> Array[Vector2]:
	return _cun


func containers_searched() -> Array[Vector2]:
	return _csearched


## QA: how many fog cells are revealed (functional test hook).
func revealed_count() -> int:
	var n := 0
	for b in _fog:
		if b == 1:
			n += 1
	return n
