extends SceneTree
## QA for the prompt-size fix (Tbandz: SLEEP UNTIL MORNING filled the
## iPhone screen). Asserts the world-space prompts are constant on-screen
## size (fixed_size + tiny pixel_size) and fade out with distance, so
## they can never balloon when the camera is close.
## Run: godot --headless --path . --script res://tests/prompt_qa.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var ok := true
	ok = _check_interact(ok)
	ok = _check_float_label(ok)
	print("PROMPTQA_RESULT ok=", ok)
	quit(0 if ok else 1)
	return true


func _check(name: String, cond: bool, ok: bool) -> bool:
	print("PROMPTQA ", name, ": ", "PASS" if cond else "FAIL")
	return ok and cond


func _check_interact(ok: bool) -> bool:
	var im := InteractManager.new()
	root.add_child(im)
	var l: Label3D = im.get("_prompt_3d")
	ok = _check("interact_fixed_size", l.fixed_size, ok)
	ok = _check("interact_small_pixel", l.pixel_size <= 0.002, ok)
	ok = _check("interact_range_end_8m", l.visibility_range_end == 8.0, ok)
	ok = _check("interact_range_fade", l.visibility_range_end_margin > 0.0, ok)
	im.free()
	return ok


func _check_float_label(ok: bool) -> bool:
	# LootManager references the Sound autoload, which isn't registered in
	# bare --script mode: stub it and lazy-load the class so the float
	# label still exercises the real _spawn_float_label code path.
	var stub := Node.new()
	stub.name = "Sound"
	stub.set_script(load("res://tests/sound_stub.gd"))
	root.add_child(stub)
	var LM := load("res://scripts/loot/loot_manager.gd")
	var lm: Node3D = LM.new()
	root.add_child(lm)
	lm._spawn_float_label(Vector3.ZERO, "+1 TEST")
	var l: Label3D = null
	for c in lm.get_children():
		if c is Label3D:
			l = c
	ok = _check("float_label_spawned", l != null, ok)
	if l != null:
		ok = _check("float_fixed_size", l.fixed_size, ok)
		ok = _check("float_small_pixel", l.pixel_size <= 0.002, ok)
		ok = _check("float_range_end_10m", l.visibility_range_end == 10.0, ok)
		ok = _check("float_range_fade", l.visibility_range_end_margin > 0.0, ok)
	lm.free()
	return ok
