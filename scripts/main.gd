extends Node3D
## LAST SHIFT bootstrap.
## Title screen -> pick a world seed -> the neighborhood generates from that
## seed (same seed = identical streets, houses, safehouse). MENU (or Esc)
## pauses to a menu with the seed label, CONTINUE, and NEW GAME (fresh
## seed => fresh neighborhood, via scene reload).
## Wires the world systems together: input, time/environment, neighborhood,
## player (+ combat & health), camera, HUD, noise bus, the zombie pack,
## and the survival layer (loot/search, inventory, safehouse, crafting).

@onready var sun: DirectionalLight3D = $Sun
@onready var time_manager: TimeManager = $TimeManager
@onready var neighborhood: NeighborhoodBuilder = $Neighborhood
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var _inv_panel: InventoryPanel
var _craft_panel: CraftingPanel
var _safehouse: Safehouse
var _minimap_view: MinimapView
var _run_started := false
var _paused := false
var _test_frames := -1 # --quit-after=N (headless QA)

# QA pass: indoor loot per house (world-space computed from house specs).
# The safehouse always gets the medkit loadout (index 2); other houses cycle.
const INDOOR_LOOT := [
	[["canned_food", 2], ["water", 1]],
	[["scrap", 2], ["cloth", 2]],
	[["medkit", 1], ["cloth", 1]],
	[["water", 2], ["canned_food", 1]],
	[["scrap", 3]],
	[["cloth", 2], ["water", 1]],
	[["canned_food", 1], ["scrap", 1]],
	# Wave loop: barricade wood + field medicine in houses.
	[["wood", 3], ["scrap", 1]],
	[["bandage", 1], ["painkillers", 1], ["canned_food", 1]],
	[["wood", 2], ["cloth", 1], ["water", 1]],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Esc must reach us while paused
	InputSetup.configure()
	_parse_cli_args()
	if RunState.world_seed < 0:
		_show_title()
	else:
		_start_run(RunState.world_seed)


func _parse_cli_args() -> void:
	# Headless QA: --seed=12345 skips the title, --quit-after=200 exits
	# after N frames.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			RunState.world_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--quit-after="):
			_test_frames = int(arg.trim_prefix("--quit-after="))


## Title screen: no world built yet — freeze the player (whole subtree)
## behind the menu. The scene reloads fresh on new game, so no re-enable
## is needed.
func _show_title() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	_connect_menu_signals()
	# Apocalyptic diorama behind the menu; the scene reload on new game
	# frees it, so it only ever exists on the title screen.
	add_child(TitleBackdrop.new())
	hud.show_title()


## Menu signal wiring, guarded: _show_title() and _start_run() both wire the
## same HUD signals, and a double-connect would fire _on_new_game twice per
## tap (double reload on web is a real hang risk on iOS Safari).
func _connect_menu_signals() -> void:
	if not hud.new_game_pressed.is_connected(_on_new_game):
		hud.new_game_pressed.connect(_on_new_game)
	if not hud.continue_pressed.is_connected(_on_continue):
		hud.continue_pressed.connect(_on_continue)
	if not hud.menu_pressed.is_connected(_on_menu_button):
		hud.menu_pressed.connect(_on_menu_button)


## Builds the seeded neighborhood and wires every system to it.
func _start_run(seed: int) -> void:
	_run_started = true
	RunState.world_seed = seed
	neighborhood.build_world(seed)
	player.global_position = neighborhood.player_start

	var visual: PlayerVisual = player.get_node("Visual") as PlayerVisual
	time_manager.build(self, sun, neighborhood, visual)
	time_manager.clock_changed.connect(hud.set_clock)
	Sound.bind_time(time_manager) # day/night ambience crossfade
	camera_rig.target = player
	# Face the camera from the porch (street) side: the safehouse can face
	# +Z or -Z, and the default +Z camera would start inside the house.
	var sh := neighborhood.houses[neighborhood.safehouse_index] as Dictionary
	camera_rig.set_yaw_immediate(0.0 if float(sh["face"]) > 0.0 else PI)
	camera_rig.snap()
	player.camera_rig = camera_rig
	player.hud = hud

	# Phase 2 systems.
	var noise := NoiseBus.new()
	noise.name = "NoiseBus"
	add_child(noise)

	var zombies := ZombieManager.new()
	zombies.name = "Zombies"
	add_child(zombies)

	var combat := player.get_node("Combat") as PlayerCombat
	var health := player.get_node("Health") as PlayerHealth
	zombies.setup(player, time_manager, noise, neighborhood.zombie_spawns,
		neighborhood.brute_spawns, neighborhood.building_zombie_spawns)
	health.setup(player, hud, zombies)
	player.health = health # the dead don't walk; the corpse is a ragdoll

	# Survival meters: stamina, hunger, thirst.
	var survival := SurvivalStats.new()
	survival.name = "Survival"
	add_child(survival)
	player.survival = survival
	survival.setup(player, hud, health, time_manager)

	combat.setup(player, hud, zombies, noise, health, survival)

	hud.respawn_requested.connect(_on_respawn.bind(health, combat, survival))

	# Phase 3 systems.
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.health = health
	inventory.survival = survival

	var interact := InteractManager.new()
	interact.name = "Interact"
	add_child(interact)
	interact.player = player
	interact.hud = hud

	var loot := LootManager.new()
	loot.name = "Loot"
	add_child(loot)
	loot.setup(player, visual, inventory, interact, hud, neighborhood.outdoor_loot)
	loot.world_seed = seed
	zombies.set_drop_context(loot, seed) # zombie drops: ~1 in 3 kills
	combat.choppables = neighborhood.choppable_trees
	for t in neighborhood.choppable_trees:
		(t as ChoppableTree).felled.connect(_on_tree_felled)

	var safehouse := Safehouse.new()
	safehouse.name = "Safehouse"
	add_child(safehouse)
	safehouse.door_pos = neighborhood.safehouse_door_pos
	safehouse.porch = neighborhood.safehouse_porch
	safehouse.setup(player, visual, inventory, health, hud, time_manager,
		zombies, neighborhood, interact)
	safehouse.survival = survival
	_safehouse = safehouse

	# QA pass: enterable-house doors (open/close, roof hiding).
	var doors := HouseDoors.new()
	doors.name = "HouseDoors"
	add_child(doors)
	doors.setup(neighborhood, interact, player, safehouse, inventory)

	# Wave loop: barricades -> weapons/guns -> waves. Order matters:
	# barricades need doors + interact; zombies need barricades for
	# pounding; combat needs weapons + ranged; waves need it all.
	var barricades := BarricadeManager.new()
	barricades.name = "Barricades"
	add_child(barricades)
	barricades.setup(neighborhood, doors, interact, inventory, survival,
		hud, player, safehouse)
	doors.barricades = barricades
	zombies.barricades = barricades

	# Interior zones: teleport triggers + the zombie director. Needs doors,
	# barricades, zombies and the player — all of which exist now.
	if neighborhood.interior_zones != null:
		neighborhood.interior_zones.setup_runtime(player, zombies, doors,
			barricades, noise, camera_rig)

	inventory.hud = hud
	inventory.visual = visual
	inventory.wire_health()

	var weapons := WeaponManager.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.setup(inventory, hud)

	var ranged := RangedCombat.new()
	ranged.name = "Ranged"
	add_child(ranged)
	ranged.setup(player, hud, zombies, noise, inventory, survival, weapons)

	combat.weapons = weapons
	combat.ranged = ranged
	combat.wire_weapons()

	var waves := WaveManager.new()
	waves.name = "Waves"
	add_child(waves)
	waves.setup(time_manager, neighborhood, player, zombies, hud)
	safehouse.waves = waves
	loot.wave_manager = waves # wave scarcity: gun/ammo finds thin out

	# QA pass: one searchable container inside every house. The police
	# station key hides in one non-safehouse house (seeded pick).
	var key_idx := (seed * 7 + 3) % maxi(neighborhood.houses.size(), 1)
	if key_idx == neighborhood.safehouse_index:
		key_idx = (key_idx + 1) % neighborhood.houses.size()
	for i in neighborhood.houses.size():
		var h := neighborhood.houses[i] as Dictionary
		var hp := h["pos"] as Vector3
		var hw := float(h["w"])
		var hd := float(h["d"])
		var hface := float(h["face"])
		var spot := hp + Vector3(-hw * 0.5 + 1.0, 0,
			hface * (hd * 0.5 - 1.2))
		var table: Array = INDOOR_LOOT[2] if i == neighborhood.safehouse_index \
			else INDOOR_LOOT[i % INDOOR_LOOT.size()]
		if i == key_idx:
			table = table.duplicate(true)
			table.append(["police_key", 1])
		loot.add_container(spot, table)
		# Interior-loot density: searchable spots where people kept things.
		# Local layout mirrors _build_interior (world = pos + local, the
		# house root is never rotated). Clearances verified for w in
		# [6.8, 8.6], d in [6.2, 7.6] against counter/bed/couch/shelf
		# solids, the door swing, and (safehouse) the workbench/stash.
		var is_sh := i == neighborhood.safehouse_index
		if not is_sh:
			# Duffel of clothes at the foot of the bed. Skipped in the
			# safehouse: the bedroll lives in that corner.
			var bedx := -(hw * 0.5 - 1.35)
			var bedz := -hface * (hd * 0.5 - 1.75)
			loot.add_container(hp + Vector3(bedx + 0.55, 0, bedz + hface * 1.15),
				[["cloth", 2], ["bandage", 1]], "duffel")
		# Junk in the back corner between the bed and the couch.
		var ck := "crate" if i % 3 != 2 else "trash"
		var ctable: Array = [["scrap", 2], ["cloth", 1]] if ck == "crate" \
			else [["scrap", 1], ["cloth", 1]]
		loot.add_container(
			hp + Vector3(-0.5, 0, -hface * (hd * 0.5) + hface * 0.9),
			ctable, ck)

	# Building types: seeded interior loot containers per building.
	for bl in neighborhood.building_loot:
		var bd := bl as Dictionary
		loot.add_container(bd["pos"], bd["items"], String(bd.get("kind", "crate")))

	var crafting := Crafting.new()
	crafting.name = "Crafting"
	add_child(crafting)
	crafting.inventory = inventory
	crafting.safehouse = safehouse
	crafting.combat = combat

	_inv_panel = InventoryPanel.new()
	_inv_panel.name = "InventoryPanel"
	_inv_panel.setup(inventory, visual)
	add_child(_inv_panel)

	var stash_panel := StashPanel.new()
	stash_panel.name = "StashPanel"
	stash_panel.setup(inventory)
	add_child(stash_panel)

	var craft_panel := CraftingPanel.new()
	craft_panel.name = "CraftingPanel"
	craft_panel.setup(crafting)
	add_child(craft_panel)
	_craft_panel = craft_panel

	safehouse.set_panels(craft_panel, stash_panel)

	# HD pass: ambient world life — sprint dust + wind-blown leaves.
	var ambient := AmbientFX.new()
	ambient.name = "AmbientFX"
	add_child(ambient)
	ambient.setup(player)

	# Minimap: fog-of-war neighborhood map (corner widget + M/tap overlay).
	var mmap := MinimapModel.new()
	mmap.name = "Minimap"
	add_child(mmap)
	mmap.setup(player, visual, neighborhood, zombies, loot, safehouse)
	if neighborhood.interior_zones != null:
		mmap.set_zones(neighborhood.interior_zones)
	_minimap_view = MinimapView.new()
	_minimap_view.name = "MinimapView"
	_minimap_view.setup(mmap)
	_minimap_view.tapped.connect(combat.suppress_attack.bind(0.2))
	hud.attach_minimap(_minimap_view)

	hud.interact_pressed.connect(interact.try_interact)
	hud.backpack_pressed.connect(_inv_panel.toggle)
	hud.craft_pressed.connect(_craft_panel.toggle)
	_connect_menu_signals()

	# Audio hooks.
	loot.loot_granted.connect(_on_loot_granted.bind(player))
	crafting.crafted.connect(_on_crafted)
	safehouse.claimed_house.connect(_on_house_claimed.bind(safehouse))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and _inv_panel != null and not _paused:
		_inv_panel.toggle()
	if event.is_action_pressed("map") and _run_started and not _paused \
			and _minimap_view != null:
		_minimap_view.toggle_expanded()
	if event.is_action_pressed("menu") and _run_started:
		if _paused:
			_on_continue()
		else:
			_on_menu_button()


func _process(_delta: float) -> void:
	if _test_frames > 0:
		_test_frames -= 1
		if _test_frames == 0:
			get_tree().quit()
	if not _run_started:
		return
	# QA failsafe: the old one-sided world plane could let a squeezed body
	# tunnel below the world and fall forever. If it ever happens again,
	# put the player back on the safehouse porch instead of soft-locking.
	if player != null and player.global_position.y < -2.0:
		push_warning("LAST SHIFT failsafe: player fell below the world; teleporting to porch")
		player.global_position = _safehouse.porch + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO


func _on_menu_button() -> void:
	if _paused or not _run_started:
		return
	Sound.play("click")
	_paused = true
	get_tree().paused = true
	hud.show_pause(RunState.world_seed)


func _on_continue() -> void:
	if not _paused:
		return
	Sound.play("click")
	_paused = false
	get_tree().paused = false
	hud.hide_menu()


## New neighborhood: pick a fresh seed and reload the scene — the reload
## tears down every system cleanly (no stale interactions, no leaks).
## Hardened for touch: the tap shows immediate feedback (so a slow world
## build never reads as "nothing happened"), extra taps while the reload is
## queued are ignored, and the reload itself is deferred out of GUI input
## dispatch (calling reload synchronously from a button signal is fragile
## on iOS Safari's web build).
var _new_game_queued := false

func _on_new_game() -> void:
	if _new_game_queued:
		return
	_new_game_queued = true
	RunState.world_seed = randi() % 100000000
	get_tree().paused = false
	Sound.play("click")
	hud.show_loading("BUILDING NEIGHBORHOOD...")
	call_deferred("_do_new_game_reload")


func _do_new_game_reload() -> void:
	get_tree().reload_current_scene()


func _on_respawn(health: PlayerHealth, combat: PlayerCombat, survival: SurvivalStats) -> void:
	Sound.play("click") # the death-screen tap
	var visual := player.get_node("Visual") as PlayerVisual
	visual.rebuild() # discard the ragdoll, rebuild the procedural body
	health.respawn()
	survival.on_respawn()
	combat.refresh_weapon_visual() # re-attach the weapon to the new arm
	combat.suppress_attack(0.5) # the respawn tap must not trigger a swing


func _on_loot_granted(_items: Array, p: PlayerController) -> void:
	Sound.play_3d("pickup", p.global_position)
	# Loot-notice hardening: an unmissable center toast naming every item,
	# on top of the 3D float labels. Silence is never acceptable here.
	if _items.size() > 0:
		var parts := PackedStringArray()
		for it in _items:
			parts.append("+%d %s" % [int(it[1]),
				LootDefs.item_name(String(it[0])).to_upper()])
		hud.show_pickup_toast("  ".join(parts))


## Wood economy: a felled dead tree pays out its wood.
func _on_tree_felled(tree: ChoppableTree, wood: int) -> void:
	var inv := get_node("Inventory") as Inventory
	inv.add(LootDefs.WOOD, wood)
	var lm := get_node("Loot") as LootManager
	lm._spawn_float_label(tree.global_position + Vector3(0, 1.4, 0),
		"+%d WOOD" % wood)
	hud.show_pickup_toast("+%d WOOD" % wood)
	Sound.play_3d("pickup", tree.global_position)


func _on_crafted(_recipe_id: String) -> void:
	Sound.play("craft_ok") # dark success chime over the workbench clank


func _on_house_claimed(sh: Safehouse) -> void:
	Sound.play_3d("claim", sh.global_position)
