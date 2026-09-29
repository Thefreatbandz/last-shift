extends Node3D
## LAST SHIFT — Phase 1 bootstrap.
## Wires the world systems together: input, time/environment, neighborhood,
## player, camera and HUD.

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
