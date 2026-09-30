extends SceneTree
## Wave-system screenshot staging v2 (xvfb):
##   wave_banner_night.png    — night sky + NIGHT FALLS banner + wave counter
##   wave_barricade_pound.png — barricaded door, zombie pounding, stage-1 damage
##   wave_pistol_fire.png     — pistol muzzle flash vs zombie
##   wave_machete.png         — machete equipped
##   wave_axe.png             — fire axe equipped
##   wave_meds.png            — inventory open: bandage / health kit / painkillers
##   wave_ragdoll.png         — shotgun kill mid-tumble
## Usage: xvfb-run -a godot --path . --script res://tests/wave_shots.gd
## Writes to ~/workspace/last-shift/polish_shots/wave_*.png.

const OUT := "/home/hatch/workspace/last-shift/polish_shots"

var _booted := false
var _frames := 0
var _phase := 0
var _t0 := 0
var _main: Node
var _player: Node3D
var _cam: Camera3D
var _z: Node = null
var _dpos := Vector3.ZERO
var _out := Vector3.ZERO


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")
	print("WSHOT saved ", name)


func _fwd() -> Vector3:
	var f: Vector3 = -_cam.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _in_view(dist: float, side := 0.0) -> Vector3:
	var f := _fwd()
	var r := Vector3(f.z, 0.0, -f.x)
	var p: Vector3 = _player.global_position + f * dist + r * side
	p.y = 0.3
	return p


func _snap_cam() -> void:
	var rig: Node = _main.get_node("CameraRig")
	rig.call("snap")
	await process_frame
	await process_frame


func _alive() -> Array:
	var out: Array = []
	for z in _main.get_node("Zombies").get("zombies"):
		if not bool(z.call("is_dead")):
			out.append(z)
	return out


func _kill_all() -> void:
	for z in _alive():
		(z as Node).call("take_damage", 99999.0,
			(z as Node3D).global_position + Vector3(0, 0, 1.0), 0.5)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("RunState").set("world_seed", 48392017)
		var ps := load("res://scenes/main.tscn") as PackedScene
		_main = ps.instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var now := Time.get_ticks_msec()
	if _phase == 0 and _frames == 60:
		_player = _main.get_node("Player")
		_cam = root.get_camera_3d()
		_phase = 1
	# --- Shot 1: night banner ------------------------------------------------
	elif _phase == 1 and _frames == 70:
		_main.get_node("TimeManager").call("set_time", 19.0)
		var hud: Node = _main.get_node("HUD")
		hud.call("set_wave", 1, 12)
		hud.call("show_banner", "NIGHT FALLS", "WAVE 1 INCOMING — GET INSIDE", 30.0)
		var zs := _alive()
		if zs.size() >= 2:
			(zs[0] as Node3D).global_position = _in_view(4.5, -1.5)
			(zs[1] as Node3D).global_position = _in_view(5.5, 1.5)
		_snap_cam()
		_phase = 2
	elif _phase == 2 and _frames == 80:
		_shot("wave_banner_night")
		_phase = 3
	# --- Clear the wave so dawn comes properly --------------------------------
	elif _phase == 3 and _frames == 100:
		_kill_all()
		_t0 = now
		_phase = 4
	elif _phase == 4 and now - _t0 >= 1500:
		# Wave cleared -> clock jumped to dawn. Push to mid-morning light.
		_main.get_node("TimeManager").call("set_time", 9.5)
		_player.get_node("Health").call("heal", 999.0)
		_phase = 5
	# --- Shot 2: barricade pounding (player safe INSIDE) ----------------------
	elif _phase == 5 and now - _t0 >= 2200:
		var bar: Node = _main.get_node("Barricades")
		var nb: Node = _main.get_node("Neighborhood")
		var st: Dictionary = bar.get("_st")
		_dpos = (st["h0"] as Dictionary)["pos"]
		var hpos: Vector3 = (nb.houses[0] as Dictionary)["pos"]
		_out = _dpos - hpos
		_out.y = 0.0
		_out = _out.normalized()
		# Player OUTSIDE, 4m from the door; zombie at the door pounds it
		# (door within 2.4m takes priority over chasing the player).
		_player.global_position = _dpos + _out * 4.0
		# yaw=PI puts the camera south of the player, looking north at the door
		# (yaw=0 would put the house between the camera and the door).
		_main.get_node("CameraRig").call("set_yaw_immediate", PI)
		var inv: Node = _main.get_node("Inventory")
		inv.call("add", "wood", 6)
		inv.call("add", "scrap", 6)
		bar.call("_try_build", "h0", st["h0"])
		for i in 5:
			bar.call("pound", "h0", 8.0) # visible stage-1 damage
		# Fresh zombie for the pounding (earlier ones were cleared).
		var zm: Node = _main.get_node("Zombies")
		_z = zm.call("_spawn_at", _dpos + _out * 1.5)
		if _z != null:
			(_z as Node3D).global_position = _dpos + _out * 1.5
			_z.call("on_noise", _player.global_position, 999.0)
		_snap_cam()
		_t0 = now
		_phase = 6
	elif _phase == 6 and now - _t0 >= 2600:
		if _z != null and is_instance_valid(_z) and not bool(_z.call("is_dead")):
			(_z as Node).get("visual").call("play_lunge")
		_shot("wave_barricade_pound")
		_phase = 7
	# --- Shot 3: pistol muzzle flash ------------------------------------------
	elif _phase == 7 and now - _t0 >= 3400:
		# Step outside to a clear spot for the gun shots.
		_player.global_position = _dpos + _out * 6.0
		_player.get_node("Health").call("heal", 999.0)
		var inv: Node = _main.get_node("Inventory")
		inv.call("add", "pistol", 1)
		inv.call("add", "ammo_9mm", 24)
		_main.get_node("Weapons").call("equip", "pistol")
		var zm: Node = _main.get_node("Zombies")
		var pz: Node = zm.call("_spawn_at", _in_view(4.0))
		if pz != null:
			(pz as Node3D).look_at(_player.global_position, Vector3.UP)
		_snap_cam()
		_phase = 8
	elif _phase == 8:
		var ranged: Node = _main.get_node("Ranged")
		var mag: Dictionary = ranged.get("mag")
		mag["pistol"] = 12
		ranged.call("try_fire")
		ranged.set("_flash_t", 0.5) # hold the flash for the capture
		_shot("wave_pistol_fire")
		_phase = 9
	# --- Shot 4: machete -------------------------------------------------------
	elif _phase == 9:
		var inv: Node = _main.get_node("Inventory")
		inv.call("add", "machete", 1)
		_main.get_node("Weapons").call("equip", "machete")
		_snap_cam()
		_t0 = now
		_phase = 10
	elif _phase == 10 and now - _t0 >= 700:
		_shot("wave_machete")
		_phase = 11
	# --- Shot 5: fire axe ------------------------------------------------------
	elif _phase == 11:
		var inv: Node = _main.get_node("Inventory")
		inv.call("add", "fire_axe", 1)
		_main.get_node("Weapons").call("equip", "fire_axe")
		_snap_cam()
		_t0 = now
		_phase = 12
	elif _phase == 12 and now - _t0 >= 700:
		_shot("wave_axe")
		_phase = 13
	# --- Shot 6: medical supplies (work bar during bandage use) -------------------
	elif _phase == 13:
		var inv: Node = _main.get_node("Inventory")
		inv.call("add", "bandage", 2)
		inv.call("add", "health_kit", 1)
		inv.call("add", "painkillers", 1)
		_player.get_node("Health").call("damage", 30.0, _player.global_position)
		inv.call("use", "bandage")
		_snap_cam()
		_t0 = now
		_phase = 14
	elif _phase == 14 and now - _t0 >= 600:
		_shot("wave_meds")
		_phase = 15
	# --- Shot 7: ragdoll mid-tumble --------------------------------------------
	elif _phase == 15:
		_kill_all() # clear the set so only the ragdoll subject is fresh
		var zm: Node = _main.get_node("Zombies")
		var zp := _in_view(3.0)
		_z = zm.call("_spawn_at", zp)
		_snap_cam()
		_phase = 151
	elif _phase == 151:
		# Let the spawn settle a frame, then land the killing blow.
		if _z != null and is_instance_valid(_z):
			var zp: Vector3 = (_z as Node3D).global_position
			_z.call("take_damage", 99999.0, zp + _fwd() * -1.0, 1.6)
			_t0 = now
			_phase = 16
		else:
			_phase = 17
	elif _phase == 16 and now - _t0 >= 220:
		_shot("wave_ragdoll")
		_phase = 17
	elif _phase == 17 and now - _t0 >= 1200:
		print("WSHOT done")
		quit(0)
		return true
	return false
