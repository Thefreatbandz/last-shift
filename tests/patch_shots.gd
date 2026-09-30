extends SceneTree
## Patch verification staging (xvfb):
##   patch_night_flashlight.png — deep night, flashlight on (readability check)
##   patch_craft_button.png     — touch HUD with CRAFT button under PACK
##   patch_craft_panel.png      — crafting panel opened via hud.craft_pressed
## Also prints: panel toggle open/close through the real signal wiring,
## field-craft result (lockpick from scrap).
## Usage: xvfb-run -a godot --path . --script res://tests/patch_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/patch_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _main: Node
var _player: Node3D
var _hud: Node
var _tm: Node


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("PSHOT saved ", name)


func _enable_touch() -> void:
	_hud.set("touch_mode", true)
	for n in ["_joy", "_attack_btn", "_pack_btn", "_weapon_btn",
			"_weapon_label", "_craft_btn", "_touch_hint"]:
		var c: Node = _hud.get(n)
		if c != null:
			(c as CanvasItem).visible = true
	var hint: Node = _hud.get("_hint_label")
	if hint != null:
		(hint as CanvasItem).visible = false


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _phase == 0 and _frames == 60:
		_player = _main.get_node("Player") as Node3D
		_hud = _main.get_node("HUD")
		_tm = _main.get_node("TimeManager")
		_tm.call("set_time", 23.5) # deep night; flashlight auto-on
		_enable_touch()
		_phase = 1
	elif _phase == 1 and _frames == 150:
		_shot("patch_night_flashlight")
		_phase = 2
	elif _phase == 2 and _frames == 165:
		_shot("patch_craft_button")
		var panel: Node = _main.get_node("CraftingPanel")
		print("PATCH craft_open_before=", bool(panel.call("is_open")))
		_hud.emit_signal("craft_pressed")
		_phase = 3
	elif _phase == 3 and _frames == 195:
		var panel: Node = _main.get_node("CraftingPanel")
		print("PATCH craft_open_after_emit=", bool(panel.call("is_open")))
		_shot("patch_craft_panel")
		_phase = 4
	elif _phase == 4 and _frames == 210:
		var panel: Node = _main.get_node("CraftingPanel")
		_hud.emit_signal("craft_pressed")
		_phase = 5
	elif _phase == 5 and _frames == 225:
		var panel: Node = _main.get_node("CraftingPanel")
		print("PATCH craft_open_after_close_emit=", bool(panel.call("is_open")))
		# Field craft: grant scrap, craft a lockpick through the real system.
		var inv: Node = _main.get_node("Inventory")
		var crafting: Node = _main.get_node("Crafting")
		inv.call("add", "scrap", 4)
		var ok: bool = bool(crafting.call("craft", "lockpick"))
		print("PATCH field_craft_lockpick=", ok,
			" lockpick_count=", int(inv.call("count", "lockpick")),
			" scrap_left=", int(inv.call("count", "scrap")))
		print("PATCH done")
		quit(0)
		return true
	return false
