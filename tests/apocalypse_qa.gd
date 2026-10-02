extends SceneTree
## Integration: the apocalypse phase holds together — night lighting,
## world dressing, and expansion coexist and stay within perf caps.
##   godot --headless --path . --script res://tests/apocalypse_qa.gd

var _booted := false
var _frames := 0
var _ok := true
var _main: Node
var _checks := 0

func _t(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("APQA FAIL: ", label)

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
	var nb = _main.get_node("Neighborhood")

	# --- Expansion: dirt roads + more buildings ---
	var rects: Array = nb.call("get_road_rects")
	_t(rects.size() == 4, "4 road rects (2 asphalt + 2 dirt), got %d" % rects.size())
	_t(int(nb.get("buildings").size()) >= 9, "9+ commercial buildings")
	var zones = nb.get("interior_zones")
	_t(zones != null, "interior zones built")

	# --- Dressing: blood, corpses, fires, rubble, wrecks ---
	var dress := _find(nb, "ApocalypseDressing")
	_t(dress != null, "ApocalypseDressing node present")
	var fire_lights := 0
	if dress != null:
		for n in dress.find_children("*", "OmniLight3D", true, false):
			fire_lights += 1
	_t(fire_lights <= 4 and fire_lights > 0, "barrel fire lights 1..4, got %d" % fire_lights)
	_t(_count_mm(dress) > 0, "dressing MultiMeshes present")

	# --- Lighting: lantern lights capped per zone, warm, shadowless ---
	var zl := 0
	var zl_ok := true
	if zones != null:
		for z in zones.get("zones"):
			var per := 0
			for n in (z["root"] as Node).find_children("*", "OmniLight3D", true, false):
				per += 1
				zl += 1
				var l := n as OmniLight3D
				if l.shadow_enabled or l.omni_range > 9.5:
					zl_ok = false
			if per > 2:
				zl_ok = false
	_t(zl_ok, "zone lantern lights capped at 2/zone, shadowless, <=9m")
	_t(zl > 0, "at least one lantern light exists, got %d" % zl)

	# --- Flashlight buff present ---
	var vis = _main.get_node("Player/Visual")
	_t(float(vis.get("_flashlight").get("spot_range")) >= 34.0, "flashlight range >= 34")
	# --- Night ambient floor lifted but still dark ---
	var tm = _main.get_node("TimeManager")
	tm.call("set_time", 1.0) # deep night
	var env: Environment = tm.get("_env")
	_t(env.ambient_light_energy >= 0.74 and env.ambient_light_energy < 0.9,
		"night ambient in [0.74, 0.9), got %f" % env.ambient_light_energy)

	# --- Determinism: no randomize() in the new/changed files ---
	for f in ["scripts/world/apocalypse_dressing.gd", "scripts/world/interior_zones.gd",
			"scripts/world/time_manager.gd", "scripts/world/neighborhood_builder.gd"]:
		var bad := false
		for line in FileAccess.get_file_as_string("res://%s" % f).split("\n"):
			var code := line.split("#")[0] # ignore comments
			if "randomize()" in code:
				bad = true
		_t(not bad, "no randomize() call in %s" % f)

	# --- One sun / one environment / one camera ---
	var suns := 0
	var wenv := 0
	var cams := 0
	for n in _main.find_children("*", "DirectionalLight3D", true, false):
		suns += 1
	for n in _main.find_children("*", "WorldEnvironment", true, false):
		wenv += 1
	for n in _main.find_children("*", "Camera3D", true, false):
		cams += 1
	_t(suns == 1, "one sun, got %d" % suns)
	_t(wenv == 1, "one WorldEnvironment, got %d" % wenv)
	_t(cams == 1, "one camera, got %d" % cams)

	print("APQA_RESULT ok=%s checks=%d" % [str(_ok).to_lower(), _checks])
	quit(0 if _ok else 1)
	return true

func _find(n: Node, cls: String) -> Node:
	for c in n.find_children("*", cls, true, false):
		return c
	return null

func _count_mm(n: Node) -> int:
	if n == null:
		return 0
	return n.find_children("*", "MultiMeshInstance3D", true, false).size()
