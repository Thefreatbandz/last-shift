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
	hud.new_game_pressed.connect(_on_new_game)
	hud.show_title()


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
	zombies.setup(player, time_manager, noise, neighborhood.zombie_spawns)
	health.setup(player, hud, zombies)

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
	loot.setup(player, visual, inventory, interact, hud)

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
	doors.setup(neighborhood, interact, player, safehouse)

	# QA pass: one searchable container inside every house.
	for i in neighborhood.houses.size():
		var h := neighborhood.houses[i] as Dictionary
		var hp := h["pos"] as Vector3
		var spot := hp + Vector3(-float(h["w"]) * 0.5 + 1.0, 0,
			float(h["face"]) * (float(h["d"]) * 0.5 - 1.2))
		var table: Array = INDOOR_LOOT[2] if i == neighborhood.safehouse_index \
			else INDOOR_LOOT[i % INDOOR_LOOT.size()]
		loot.add_container(spot, table)

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
	_minimap_view = MinimapView.new()
	_minimap_view.name = "MinimapView"
	_minimap_view.setup(mmap)
	_minimap_view.tapped.connect(combat.suppress_attack.bind(0.2))
	hud.attach_minimap(_minimap_view)

	hud.interact_pressed.connect(interact.try_interact)
	hud.backpack_pressed.connect(_inv_panel.toggle)
	hud.menu_pressed.connect(_on_menu_button)
	hud.new_game_pressed.connect(_on_new_game)
	hud.continue_pressed.connect(_on_continue)

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
func _on_new_game() -> void:
	Sound.play("click")
	RunState.world_seed = randi() % 100000000
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_respawn(health: PlayerHealth, combat: PlayerCombat, survival: SurvivalStats) -> void:
	Sound.play("click") # the death-screen tap
	health.respawn()
	survival.on_respawn()
	combat.suppress_attack(0.5) # the respawn tap must not trigger a swing


func _on_loot_granted(_items: Array, p: PlayerController) -> void:
	Sound.play_3d("pickup", p.global_position)


func _on_crafted(_recipe_id: String) -> void:
	Sound.play("craft_ok") # dark success chime over the workbench clank


func _on_house_claimed(sh: Safehouse) -> void:
	Sound.play_3d("claim", sh.global_position)
