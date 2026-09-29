extends Node3D
## LAST SHIFT — Phase 3 bootstrap.
## Wires the world systems together: input, time/environment, neighborhood,
## player (+ combat & health), camera, HUD, noise bus, the zombie pack,
## and the Phase 3 survival layer (loot/search, inventory, safehouse,
## crafting + panels).

@onready var sun: DirectionalLight3D = $Sun
@onready var time_manager: TimeManager = $TimeManager
@onready var neighborhood: NeighborhoodBuilder = $Neighborhood
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var _inv_panel: InventoryPanel


func _ready() -> void:
	InputSetup.configure()
	var visual: PlayerVisual = player.get_node("Visual") as PlayerVisual
	time_manager.build(self, sun, neighborhood, visual)
	time_manager.clock_changed.connect(hud.set_clock)
	camera_rig.target = player
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
	zombies.setup(player, time_manager, noise)
	health.setup(player, hud, zombies)
	combat.setup(player, hud, zombies, noise, health)

	hud.respawn_requested.connect(_on_respawn.bind(health, combat))

	# Phase 3 systems.
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.health = health

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
	safehouse.setup(player, visual, inventory, health, hud, time_manager,
		zombies, neighborhood, interact)

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

	hud.interact_pressed.connect(interact.try_interact)
	hud.backpack_pressed.connect(_inv_panel.toggle)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and _inv_panel != null:
		_inv_panel.toggle()


func _on_respawn(health: PlayerHealth, combat: PlayerCombat) -> void:
	health.respawn()
	combat.suppress_attack(0.5) # the respawn tap must not trigger a swing
