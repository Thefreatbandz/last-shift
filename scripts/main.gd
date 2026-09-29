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
var _safehouse: Safehouse

# QA pass: indoor loot per house (world-space computed from house specs).
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
	InputSetup.configure()
	var visual: PlayerVisual = player.get_node("Visual") as PlayerVisual
	time_manager.build(self, sun, neighborhood, visual)
	time_manager.clock_changed.connect(hud.set_clock)
	Sound.bind_time(time_manager) # day/night ambience crossfade
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
		loot.add_container(spot, INDOOR_LOOT[i % INDOOR_LOOT.size()])

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

	# Audio hooks.
	loot.loot_granted.connect(_on_loot_granted.bind(player))
	crafting.crafted.connect(_on_crafted)
	safehouse.claimed_house.connect(_on_house_claimed.bind(safehouse))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and _inv_panel != null:
		_inv_panel.toggle()


func _process(_delta: float) -> void:
	# QA failsafe: the old one-sided world plane could let a squeezed body
	# tunnel below the world and fall forever. If it ever happens again,
	# put the player back on the safehouse porch instead of soft-locking.
	if player != null and player.global_position.y < -2.0:
		push_warning("LAST SHIFT failsafe: player fell below the world; teleporting to porch")
		player.global_position = Safehouse.PORCH + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO


func _on_respawn(health: PlayerHealth, combat: PlayerCombat) -> void:
	Sound.play("click") # the death-screen tap
	health.respawn()
	combat.suppress_attack(0.5) # the respawn tap must not trigger a swing


func _on_loot_granted(_items: Array, p: PlayerController) -> void:
	Sound.play_3d("pickup", p.global_position)


func _on_crafted(_recipe_id: String) -> void:
	Sound.play("craft_ok") # dark success chime over the workbench clank


func _on_house_claimed(sh: Safehouse) -> void:
	Sound.play_3d("claim", sh.global_position)
