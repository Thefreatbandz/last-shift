extends Node3D
## LAST SHIFT — Phase 2 bootstrap.
## Wires the world systems together: input, time/environment, neighborhood,
## player (+ combat & health), camera, HUD, noise bus and the zombie pack.

@onready var sun: DirectionalLight3D = $Sun
@onready var time_manager: TimeManager = $TimeManager
@onready var neighborhood: NeighborhoodBuilder = $Neighborhood
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD


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


func _on_respawn(health: PlayerHealth, combat: PlayerCombat) -> void:
	health.respawn()
	combat.suppress_attack(0.5) # the respawn tap must not trigger a swing
