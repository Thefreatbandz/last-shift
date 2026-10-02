extends SceneTree
## Smoke: boot the real game on 3 seeds, run 200 frames each, count
## gameplay script errors. Usage: --script res://tests/smoke3.gd SEED
## (seed passed via OS.get_cmdline_user_args())

var _booted := false
var _frames := 0
var _main: Node
var _errs := 0

func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		var args := OS.get_cmdline_user_args()
		var seed := int(args[0]) if args.size() > 0 else 48392017
		root.get_node("RunState").set("world_seed", seed)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames >= 200:
		print("SMOKE seed done frames=200 errors=", _errs)
		quit(0)
		return true
	return false
