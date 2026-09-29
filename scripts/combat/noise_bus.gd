class_name NoiseBus
extends Node
## Phase 2: tiny event bus for sound. Emitters (sprinting player, melee
## swings) call emit_noise; ZombieManager forwards each pulse to every
## zombie, which decides whether it heard it.

signal noise_emitted(pos: Vector3, radius: float)


func emit_noise(pos: Vector3, radius: float) -> void:
	noise_emitted.emit(pos, radius)
