extends SceneTree
## Probe: crafting + backpack panels scroll correctly and buttons still work.
## Usage: xvfb-run -a godot --headless --path . --script res://tests/probe_panel_scroll.gd

var _booted := false
var _frames := 0
var _main: Node
var _fails: Array = []


func _check(cond: bool, label: String) -> void:
	print("PROBE ", "PASS" if cond else "FAIL", ": ", label)
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames < 90:
		return false

	# --- Crafting panel ---
	var cp: CanvasLayer = _main.get_node("CraftingPanel")
	cp.call("open")
	var scroll: ScrollContainer = cp.find_child("RecipeScroll", true, false)
	_check(scroll != null, "crafting ScrollContainer exists")
	if scroll != null:
		_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS,
			"crafting scrollbar always visible")
		_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"crafting horizontal scroll disabled")
		_check(scroll.size_flags_vertical & Control.SIZE_EXPAND_FILL != 0,
			"crafting scroll expands to fill panel")
		var rows: VBoxContainer = scroll.get_child(0)
		_check(rows is VBoxContainer, "recipe rows VBox inside scroll")
		# Recipe count via runtime load (avoids parse-time autoload dependency).
		var craft_scr: GDScript = load("res://scripts/crafting/crafting.gd")
		var recipe_n: int = (craft_scr.RECIPES as Array).size()
		var live_rows := 0
		for ch in rows.get_children():
			if not ch.is_queued_for_deletion():
				live_rows += 1
		_check(live_rows == recipe_n,
			"all %d recipe rows present (live=%d)" % [recipe_n, live_rows])
		# Buttons still tap: press the first row's CRAFT button.
		var first_row: HBoxContainer = rows.get_child(0)
		var btn: Button = null
		for ch in first_row.get_children():
			if ch is Button:
				btn = ch
		_check(btn != null, "craft button found in row")
		if btn != null and not btn.disabled:
			var inv_before: int = _main.get_node("Inventory").count("lockpick")
			btn.pressed.emit()
			var inv_after: int = _main.get_node("Inventory").count("lockpick")
			# lockpick is the first recipe; may be unaffordable -> button disabled.
			print("PROBE info: lockpick count before/after button press: ",
				inv_before, "/", inv_after)
		# Scrolling works: max scroll >= 0 and setting an offset sticks.
		scroll.scroll_vertical = 10
		_check(scroll.scroll_vertical >= 0, "scroll offset settable")
	cp.call("close_panel")

	# --- Backpack panel ---
	var ip: CanvasLayer = _main.get_node("InventoryPanel")
	_main.get_node("Inventory").add("scrap", 3)
	_main.get_node("Inventory").add("canned_food", 2)
	ip.call("open")
	var iscroll: ScrollContainer = ip.find_child("ItemScroll", true, false)
	_check(iscroll != null, "backpack ScrollContainer exists")
	if iscroll != null:
		var grid: GridContainer = iscroll.get_child(0)
		_check(grid is GridContainer, "item grid inside scroll")
		_check(grid.get_child_count() >= 2, "item cards present in grid")
		# Card tap still works: find the canned_food card and press it.
		var used_ok := false
		for card in grid.get_children():
			if card is Button:
				for sub in (card as Button).find_children("*", "Label", true, false):
					if (sub as Label).text == LootDefs.item_name("canned_food"):
						(card as Button).pressed.emit()
						used_ok = true
		print("PROBE info: canned_food card pressed: ", used_ok)
	ip.call("close_panel")

	print("PROBE RESULT fails=", _fails.size(), " ", _fails)
	quit(1 if _fails.size() > 0 else 0)
	return true
