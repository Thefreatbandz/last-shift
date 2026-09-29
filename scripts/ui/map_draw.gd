class_name MapDraw
extends RefCounted
## Static map renderer shared by the corner minimap and the expanded
## overlay. North-up: world -Z is up, +X is right. All drawing is
## immediate-mode (draw_rect / draw_circle / draw_colored_polygon) — cheap
## at the model's 10Hz redraw rate, no texture uploads.

static var _sb: StyleBoxFlat
static var _font: Font


static func _style() -> StyleBoxFlat:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color(0.02, 0.025, 0.035, 0.72)
		_sb.set_corner_radius_all(22)
		_sb.border_width_left = 2
		_sb.border_width_right = 2
		_sb.border_width_top = 2
		_sb.border_width_bottom = 2
		_sb.border_color = Color(0.55, 0.48, 0.34, 0.55)
	return _sb


static func _get_font() -> Font:
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font


static func draw_panel(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_style_box(_style(), rect)


## Draws the world (roads, houses, markers) centered on `center` at
## `px` pixels per meter. Unexplored areas stay dark (fog of war); the
## safehouse is always drawn (QoL: you always know where home is).
static func draw_world(canvas: CanvasItem, m: MinimapModel, center: Vector2,
		px: float) -> void:
	# --- Roads: subdivided into ~4m chunks so fog reveals them progressively.
	var road_col := Color(0.34, 0.35, 0.38, 0.85)
	for r in m.road_rects():
		var rr := r as Rect2
		var horizontal := rr.size.x > rr.size.y
		var length := rr.size.x if horizontal else rr.size.y
		var n := maxi(1, int(length / 4.0))
		for i in n:
			var t0 := float(i) / float(n)
			var t1 := float(i + 1) / float(n)
			var cx := rr.position.x + rr.size.x * (t0 + t1) * 0.5 \
				if horizontal else rr.position.x + rr.size.x * 0.5
			var cz := rr.position.y + rr.size.y * 0.5 \
				if horizontal else rr.position.y + rr.size.y * (t0 + t1) * 0.5
			if not m.is_revealed(cx, cz):
				continue
			var c0 := Vector2(
				rr.position.x + rr.size.x * (t0 if horizontal else 0.0),
				rr.position.y + rr.size.y * (0.0 if horizontal else t0))
			var c1 := Vector2(
				rr.position.x + rr.size.x * (t1 if horizontal else 1.0),
				rr.position.y + rr.size.y * (1.0 if horizontal else t1))
			var m0 := center + c0 * px
			var m1 := center + c1 * px
			canvas.draw_rect(Rect2(m0, m1 - m0).abs(), road_col)

	# --- Gas station footprint (explored only).
	var gas := m.gas_rect()
	if gas.has_area():
		var gc := gas.get_center()
		if m.is_revealed(gc.x, gc.y):
			var g0 := center + gas.position * px
			var g1 := center + (gas.position + gas.size) * px
			canvas.draw_rect(Rect2(g0, g1 - g0).abs(),
				Color(0.55, 0.45, 0.22, 0.8), false, 2.0)

	# --- Houses (safehouse always drawn; others need fog).
	var sh_idx := m.safehouse_index()
	var i := 0
	for h in m.houses():
		var hd := h as Dictionary
		var hp := hd["pos"] as Vector3
		var mp := center + Vector2(hp.x, hp.z) * px
		var hr := Rect2(mp - Vector2(float(hd["w"]), float(hd["d"])) * px * 0.5,
			Vector2(float(hd["w"]), float(hd["d"])) * px)
		if i == sh_idx:
			var col := Color(0.30, 0.80, 0.35, 0.95) if m.is_claimed() \
				else Color(0.95, 0.55, 0.15, 0.95)
			canvas.draw_rect(hr.grow(2.0), col)
			canvas.draw_rect(hr.grow(2.0), Color(1, 1, 1, 0.85), false, 1.5)
		elif m.is_revealed(hp.x, hp.z):
			canvas.draw_rect(hr, Color(0.42, 0.38, 0.33, 0.9))
		i += 1

	# --- Loot containers: gold = unsearched, dim = searched (explored only).
	for cp in m.containers_unsearched():
		if m.is_revealed(cp.x, cp.y):
			canvas.draw_circle(center + cp * px, 2.5, Color(0.95, 0.78, 0.30, 0.95))
	for cp in m.containers_searched():
		if m.is_revealed(cp.x, cp.y):
			canvas.draw_circle(center + cp * px, 2.0, Color(0.35, 0.35, 0.38, 0.7))

	# --- Zombies within earshot: red dots (no fog — you hear them coming).
	for zp in m.zombie_dots():
		canvas.draw_circle(center + zp * px, 3.0, Color(0.88, 0.14, 0.12, 0.95))

	# --- Player arrow (rotates with facing; triangle points north at yaw 0).
	var pp := center + m.player_pos() * px
	canvas.draw_set_transform(pp, -m.player_yaw(), Vector2.ONE)
	canvas.draw_colored_polygon(
		[Vector2(0, -7), Vector2(5, 6), Vector2(0, 3), Vector2(-5, 6)],
		Color(0.98, 0.97, 0.92, 1.0))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_north(canvas: CanvasItem, top: Vector2) -> void:
	canvas.draw_string(_get_font(), top + Vector2(-5, 15), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.65))


## Full-screen overlay: dimmed world, big map, seed label, legend.
static func draw_expanded(canvas: Control, m: MinimapModel) -> void:
	var size := canvas.size
	var f := _get_font()
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	var side := minf(size.x - 56.0, size.y - 190.0)
	var panel := Rect2((size.x - side) * 0.5, 84.0, side, side)
	draw_panel(canvas, panel)
	var c := panel.get_center()
	var px := (side * 0.5 - 26.0) / 74.0
	draw_world(canvas, m, c, px)
	draw_north(canvas, Vector2(c.x, panel.position.y + 4.0))
	canvas.draw_string(f, Vector2(30, 54), "NEIGHBORHOOD %d" % m.seed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.78, 0.40))
	# Legend under the panel.
	var ly := panel.position.y + side + 30.0
	var lx := (size.x - 460.0) * 0.5
	var items := [
		[Color(0.98, 0.97, 0.92), "YOU"],
		[Color(0.95, 0.55, 0.15), "SAFEHOUSE"],
		[Color(0.88, 0.14, 0.12), "ZOMBIE"],
		[Color(0.95, 0.78, 0.30), "LOOT"],
	]
	for it in items:
		canvas.draw_circle(Vector2(lx, ly - 4), 5.0, it[0] as Color)
		canvas.draw_string(f, Vector2(lx + 12, ly), it[1] as String,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.75))
		lx += 120.0
	canvas.draw_string(f, Vector2(30, size.y - 30), "TAP OR M TO CLOSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.55))
