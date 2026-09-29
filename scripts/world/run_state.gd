extends Node
## Cross-scene-run state for LAST SHIFT. Survives reload_current_scene() so a
## "new neighborhood" is just: set world_seed, reload, rebuild.
## world_seed < 0 means "not chosen yet" — the bootstrap shows the title
## screen instead of starting a run. Plain integer seeds: shareable between
## players, and ready if multiplayer ever needs matching worlds.
var world_seed: int = -1
