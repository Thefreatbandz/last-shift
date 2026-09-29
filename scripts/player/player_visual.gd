class_name PlayerVisual
extends Node3D
## Procedural survivor visual, HD cleanup pass: premium stylized low-poly.
## Tapered frustum geometry (no stacked-box look), deliberate proportions,
## crisp intentional details, cohesive gritty palette with subtle rim light
## so the character pops. Same public API as before: set_target_yaw,
## set_flashlight, tick. Pivoted hips/knees/shoulders/elbows drive the
## weighted walk (knee flex, elbow bend, bob, sway, head counter-bob),
## idle breathing/sway with occasional blinks, chest flashlight at night.
## All meshes are low-poly primitives with shared materials (mobile-first).

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _head: Node3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _torso: MeshInstance3D
var _flashlight: SpotLight3D

var _phase := 0.0
var _idle_t := 0.0
var _blink_t := 0.0
var _target_yaw := 0.0
var _head_base_y := 0.0

# Phase 3: one-shot action overlays (kneel/search, pickup, eat, door push,
# hurt flinch, attack swing). Applied additively on top of the walk/idle pose
# each tick, so the base animation is never disturbed.
var _action := ""
var _action_t := 0.0
var _action_dur := 1.0
# Additive overlay via OverlayMixer: every frame the live base-pose values
# are read AFTER the base ran, pure envelope offsets (0 at both ends) are
# added, and any interrupted action's in-flight offsets decay out over 0.2s.
# Values can never go stale, never accumulate, and interrupts crossfade
# instead of popping.
var _mixer := OverlayMixer.new()
# Pure base-pose values from last frame (before any overlay). The base
# pose's easing lerps MUST read these, never the live nodes: the nodes
# carry last frame's overlay offsets, and lerping those would feed the
# offsets back into the base and amplify them ~8x. Updated every tick in
# _apply_action, before the overlay is applied.
var _base_prev := {}
# Two-hand grip telemetry: longest left-shoulder -> bat-handle distance seen
# during the current swing. The arms are 0.68 long; anything above means the
# off hand could not reach the handle (QA fails loudly on this).
var _max_grip_d := 0.0
# Stabilized IK solution from last frame. The raw two-bone solution can
# flip branches mid-swing (several radians in one frame) when the handle
# target swings past the pole; clamping the solution's per-frame change
# keeps the off hand's motion continuous (it tracks with a slight lag
# through the fastest part of the strike, which reads naturally).
var _ik_prev := {}

# Nail bat mount: combat hands us the weapon pivot; it rides in the right
# hand (forearm child) so the swing is genuinely arms-driven.
var _weapon_pivot: Node3D = null
var _weapon_rest_x := 0.0

# --- ANIMATION STATE-NAME CONTRACT -------------------------------------
# Standard state names (from Tbandz's character animation kit). Our
# procedural rig maps to these names; when GLB/FBX clips are imported
# later they drop in under these names with no rewiring.
#   idle        -> _idle (breathing, sway, blinks)
#   walk        -> _walk at low speed
#   run         -> _walk at high speed (phase-scaled)
#   sprint      -> _walk at full-tilt speed (same rig, faster phase)
#   crouch_idle -> play_kneel held (search pose doubles as crouch)
#   crouch_walk -> (reserved)
#   attack      -> play_attack: two-handed overhead bat swing, arms-driven
#   reload      -> (reserved: future firearms)
#   dodge       -> (reserved)
#   hurt        -> play_hurt_flinch: stagger back (0.45s)
#   land        -> (reserved)
#   fall        -> (reserved)
#   death       -> (handled by player death/respawn flow)
#   interact    -> play_door_push (door open/close push)
#   pickup      -> play_pickup (post-search grab beat)
#   equip       -> (reserved: future weapon swaps)
#   unequip     -> (reserved: future weapon swaps)
# -----------------------------------------------------------------------

# Materials (created once, shared across every part).
var _m_jacket: StandardMaterial3D
var _m_jacket_dark: StandardMaterial3D
var _m_pants: StandardMaterial3D
var _m_pants_dark: StandardMaterial3D
var _m_boots: StandardMaterial3D
var _m_boots_dark: StandardMaterial3D
var _m_sole: StandardMaterial3D
var _m_skin: StandardMaterial3D
var _m_skin_shade: StandardMaterial3D
var _m_hair: StandardMaterial3D
var _m_pack: StandardMaterial3D
var _m_pack_dark: StandardMaterial3D
var _m_eye: StandardMaterial3D
var _m_mouth: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_glove: StandardMaterial3D
var _m_scuff: StandardMaterial3D
var _m_lens: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build()
	_head_base_y = _head.position.y


func set_target_yaw(y: float) -> void:
	_target_yaw = y


func set_flashlight(on: bool) -> void:
	_flashlight.light_energy = 2.6 if on else 0.0
	_m_lens.emission_energy_multiplier = 3.0 if on else 0.0


func tick(delta: float, speed: float, moving: bool) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-10.0 * delta))
	# Occasional blink, both states.
	_blink_t += delta
	var eye_sy := 0.12 if fmod(_blink_t, 3.7) < 0.12 else 1.0
	_eye_l.scale.y = eye_sy
	_eye_r.scale.y = eye_sy
	var k := 1.0 - exp(-8.0 * delta)
	if moving:
		_walk(delta, speed, k)
		_idle_t = 0.0
	else:
		_idle(delta, k)
	_apply_action(delta)


func play_kneel(duration: float) -> void:
	_start_action("kneel", duration)


func play_pickup() -> void:
	_start_action("pickup", 0.6)


func play_eat() -> void:
	_start_action("eat", 0.9)


func play_door_push() -> void:
	_start_action("door", 1.1)


func play_hurt_flinch() -> void:
	_start_action("hurt", 0.45)


func play_attack(duration: float) -> void:
	_start_action("attack", duration)


## Combat mounts the nail-bat pivot in the right hand so the swing is
## arms-driven: the shoulder/elbow carry the bat through the arc.
func attach_weapon(pivot: Node3D) -> void:
	_weapon_pivot = pivot
	if _fore_r == null:
		# Visual not built yet (shouldn't happen — combat sets up after
		# _ready); fall back to the old floating mount.
		add_child(pivot)
		pivot.position = Vector3(0.33, 1.28, -0.06)
		_weapon_rest_x = 0.55
		pivot.rotation.x = _weapon_rest_x
		return
	_fore_r.add_child(pivot)
	pivot.position = Vector3(0, -0.37, -0.04) # in the gloved hand
	# Rest: business end angled down-forward, like the old mount.
	_weapon_rest_x = PI + 0.55
	pivot.rotation.x = _weapon_rest_x
	pivot.rotation.y = 0.0
	pivot.rotation.z = 0.0


func _start_action(name: String, dur: float) -> void:
	# Switching mid-envelope: the interrupted action's in-flight offsets
	# were captured from what was actually written last frame, so the new
	# action crossfades over 0.2s instead of popping.
	if _action != "":
		_mixer.interrupt()
	_action = name
	_action_t = 0.0
	_action_dur = dur
	if name == "attack":
		_ik_prev = {} # fresh swing, fresh IK tracking
		_max_grip_d = 0.0
	if name == "attack":
		_max_grip_d = 0.0


## Live base-pose channel values, read AFTER the base pose ran this frame.
## Channels the base never writes read as 0.0 (their rest value), so the
## offsets below stay pure additions.
func _read_base() -> Dictionary:
	return {
		"py": _body.position.y, "pz": 0.0,
		"rx": _body.rotation.x, "ry": 0.0, "rz": _body.rotation.z,
		"leg_l": _leg_l.rotation.x, "leg_r": _leg_r.rotation.x,
		"shin_l": _shin_l.rotation.x, "shin_r": _shin_r.rotation.x,
		"arm_l": _arm_l.rotation.x, "arm_r": _arm_r.rotation.x,
		"fore_l": _fore_l.rotation.x, "fore_r": _fore_r.rotation.x,
		"head_x": _head.rotation.x, "head_z": 0.0,
		"arml_z": 0.0, "armr_z": 0.0,
		"batx": 0.0, "batz": 0.0,
	}


func _write_channels(d: Dictionary) -> void:
	_body.position.y = d["py"]
	_body.position.z = d["pz"]
	_body.rotation.x = d["rx"]
	_body.rotation.y = d["ry"]
	_body.rotation.z = d["rz"]
	_leg_l.rotation.x = d["leg_l"]
	_leg_r.rotation.x = d["leg_r"]
	_shin_l.rotation.x = d["shin_l"]
	_shin_r.rotation.x = d["shin_r"]
	_arm_l.rotation.x = d["arm_l"]
	_arm_r.rotation.x = d["arm_r"]
	_fore_l.rotation.x = d["fore_l"]
	_fore_r.rotation.x = d["fore_r"]
	_head.rotation.x = d["head_x"]
	_head.rotation.z = d["head_z"]
	_arm_l.rotation.z = d["arml_z"]
	_arm_r.rotation.z = d["armr_z"]
	if _weapon_pivot != null:
		_weapon_pivot.rotation.x = _weapon_rest_x + d["batx"]
		_weapon_pivot.rotation.z = d["batz"]


## Last frame's pure base value for a channel (falls back to the live node
## on the very first frame). Keeps base-pose easing out of the overlay's
## feedback loop (see _base_prev).
func _base_prev_val(ch: String, cur: float) -> float:
	return float(_base_prev.get(ch, cur))


func _apply_action(delta: float) -> void:
	# Snapshot the pure base values for next frame's easing BEFORE the
	# overlay is applied (see _base_prev). This runs every tick, even with
	# no action active, so the easing never reads stale data.
	var base := _read_base()
	_base_prev = base
	# Keep mixing while an interrupted action's residue decays, even after
	# the action itself finished.
	if _action == "" and not _mixer.has_residue():
		return
	var offsets := {}
	if _action != "":
		_action_t += delta
		var t := clampf(_action_t / _action_dur, 0.0, 1.0)
		if _action == "attack":
			offsets = _attack_offsets(t)
		else:
			var e: float
			if _action == "kneel":
				# Ease in, hold through the search, ease out at the end.
				e = smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.8, 1.0, t))
			else:
				e = sin(t * PI) # smooth in/out one-shot
			offsets = _overlay_offsets(_action, e)
		if t >= 1.0:
			# Envelope is back at zero, so the last writes equal the live
			# base; the base pose takes over from here with nothing left.
			_action = ""
	_write_channels(_mixer.mix(delta, base, offsets))


## One-shot overlay channels as pure offsets: every value is 0 at both ends
## of its envelope, so interrupting or finishing an action leaves nothing
## behind (the mixer decays any residue).
func _overlay_offsets(action: String, e: float) -> Dictionary:
	var o := {}
	match action:
		"kneel":
			# Drop is tuned so the folded legs keep the feet planted: the
			# visual must never sink through the floor.
			o["py"] = -0.26 * e
			o["rx"] = 0.18 * e
			o["leg_l"] = -0.90 * e
			o["leg_r"] = -0.90 * e
			o["shin_l"] = 1.40 * e
			o["shin_r"] = 1.40 * e
			o["arm_l"] = 0.55 * e # reach forward into the chest
			o["arm_r"] = 0.55 * e
		"pickup":
			# Bow forward over the chest and grab: slight crouch keeps the
			# feet planted (no floor penetration), torso bends forward.
			o["rx"] = -0.30 * e
			o["py"] = -0.06 * e
			o["leg_l"] = 0.35 * e
			o["leg_r"] = 0.35 * e
			o["shin_l"] = -0.55 * e
			o["shin_r"] = -0.55 * e
			o["arm_l"] = 0.95 * e
			o["arm_r"] = 0.95 * e
			o["head_x"] = -0.25 * e
		"eat":
			o["arm_r"] = -1.35 * e
			o["fore_r"] = -0.90 * e
			o["head_x"] = 0.18 * e
		"door":
			o["arm_l"] = -1.15 * e
			o["arm_r"] = -1.15 * e
			o["rx"] = 0.28 * e
			o["pz"] = -0.12 * e
		"hurt":
			# Stagger BACK away from the attacker: positive rotation.x rocks
			# the torso toward +Z (behind a -Z-facing character).
			o["rz"] = 0.28 * e
			o["rx"] = 0.18 * e
			o["head_z"] = 0.30 * e
			o["arml_z"] = 0.50 * e
			o["armr_z"] = -0.50 * e
	return o


## TWO-HANDED OVERHEAD bat swing. Both arms lift the bat above/behind the
## head (left hand reaching to a second grip point down the handle), then the
## arms drive the bat down through an overhead arc to the strike point in
## front, then relax. The torso stays planted (legs bend, no lunge, no
## forward pitch) and the pose returns to zero on every channel by t=1.
func _attack_offsets(t: float) -> Dictionary:
	var wind := smoothstep(0.0, 0.25, t)
	var strike := smoothstep(0.25, 0.48, t)
	var relax := smoothstep(0.55, 1.0, t)
	var sh_x := lerpf(lerpf(0.0, 3.05, wind), 0.62, strike)
	sh_x = lerpf(sh_x, 0.0, relax)
	var sh_z := lerpf(lerpf(0.0, -0.38, wind), -0.34, strike)
	sh_z = lerpf(sh_z, 0.0, relax)
	var elb := lerpf(lerpf(0.0, 0.40, wind), 0.06, strike)
	elb = lerpf(elb, 0.0, relax)
	var whip := lerpf(lerpf(0.0, -0.90, wind), 0.35, strike)
	whip = lerpf(whip, 0.0, relax)
	var bz := lerpf(lerpf(0.0, 0.25, wind), 0.06, strike)
	bz = lerpf(bz, 0.0, relax)
	var se := strike * (1.0 - relax) # body envelope: engaged during the strike
	var o := {
		"arm_r": sh_x,
		"armr_z": sh_z,
		"fore_r": elb,
		"batx": whip,
		"batz": bz,
		"py": -0.06 * se,
		"leg_l": 0.22 * se,
		"leg_r": 0.22 * se,
		"shin_l": -0.30 * se,
		"shin_r": -0.30 * se,
		"ry": lerpf(lerpf(lerpf(0.0, -0.10, wind), 0.08, strike), 0.0, relax),
	}
	# Off-hand reach: the left arm is aimed with two-bone IK at a second
	# grip point on the bat handle. The bat rides on the right forearm, so
	# the handle point is derived from the right arm's posed chain here.
	var grip := lerpf(-0.20, -0.16, strike)
	var grip_w := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.88, 1.0, t))
	# The off hand travels up WITH the wind-up: gating its IK correction by
	# the wind envelope keeps the first frames from popping (a ~2 rad
	# correction applied in one frame) and reads as the hand coming up to
	# meet the bat.
	var lw := grip_w * wind
	var reach := _solve_left_grip(sh_x, sh_z, elb, whip, bz, grip, grip_w)
	# angle_difference: the IK solution is continuous as a rotation, but
	# atan2/asin wrap at +/-PI. Correcting via the shortest path keeps the
	# arm from spinning the long way around when the solution crosses the
	# branch cut mid-swing. _stabilize_ik additionally clamps the solution
	# itself so a branch flip can't teleport the hand.
	var thx := _stabilize_ik("thx", reach["thx"])
	var phz := _stabilize_ik("phz", reach["phz"])
	var elb2 := _stabilize_ik("elb", reach["elb"])
	o["arm_l"] = angle_difference(_arm_l.rotation.x, thx) * lw
	o["arml_z"] = angle_difference(_arm_l.rotation.z, phz) * lw
	o["fore_l"] = angle_difference(_fore_l.rotation.x, elb2) * lw
	return o


## Clamp a per-frame IK solution change to +/-0.5 rad: the raw two-bone
## solution can flip branches (multi-radian teleport) when the handle
## target swings past the pole vector mid-strike. The hand tracks the
## stabilized solution with a slight lag instead of snapping.
func _stabilize_ik(key: String, raw: float) -> float:
	var prev: float = float(_ik_prev.get(key, raw))
	var v := prev + clampf(angle_difference(prev, raw), -0.5, 0.5)
	_ik_prev[key] = v
	return v


## Aim the left arm at a handle point on the bat with two-bone IK.
## Returns the absolute shoulder x / z-tilt / elbow angles that put the
## left hand on the grip. `grip` is the handle offset from the right hand
## along the bat's +Y (tip direction); negative = down toward the pommel.
## Also records _max_grip_d (longest TRUE shoulder->grip distance seen while
## the off hand is engaged) for the two-hand QA check. At rest the handle
## is legitimately out of reach, so only the engaged region is tracked.
func _solve_left_grip(sh_x: float, sh_z: float, elb: float,
		whip: float, bz: float, grip: float, grip_w: float) -> Dictionary:
	var S_r := Vector3(0.26, 1.47, 0.0) # right shoulder, _body space
	var S_l := Vector3(-0.26, 1.47, 0.0) # left shoulder, _body space
	var L1 := 0.31
	var L2 := 0.37
	var R_arm := Basis(Vector3.RIGHT, sh_x) * Basis(Vector3(0, 0, 1), sh_z)
	var E := S_r + (R_arm * Vector3(0, -1, 0)) * L1
	var R_fore := R_arm * Basis(Vector3.RIGHT, elb)
	var H := E + (R_fore * Vector3(0, -0.37, -0.04))
	var R_bat := R_fore * Basis(Vector3.RIGHT, _weapon_rest_x + whip) \
		* Basis(Vector3(0, 0, 1), bz)
	var bdir := (R_bat * Vector3(0, 1, 0)).normalized()
	var G := H + bdir * grip
	var D := G - S_l
	var d_true := D.length()
	if grip_w > 0.5:
		_max_grip_d = maxf(_max_grip_d, d_true)
	var d := clampf(d_true, 0.25, L1 + L2 - 0.02)
	var dn := D / d_true
	# Elbow bend from the law of cosines; the pole keeps the elbow pointing
	# out-left instead of folding into the ribs.
	var cosA := clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var A := acos(cosA)
	var pole := Vector3(-0.75, 0.30, 0.50).normalized()
	var axis := dn.cross(pole)
	if axis.length() < 0.05:
		axis = Vector3.RIGHT
	else:
		axis = axis.normalized()
	var upper := (Basis(axis, A) * dn).normalized()
	var El := S_l + upper * L1
	var v := (G - El).normalized()
	# Shoulder aim: R = Rx(thx) * Rz(phz), R * (0,-1,0) = upper.
	var phz := asin(clampf(upper.x, -1.0, 1.0))
	phz = clampf(phz, -1.4, 1.4)
	var thx := atan2(-upper.z, -upper.y)
	# Elbow bend about the arm's local X, signed by the bend-plane normal.
	var B := acos(clampf(upper.dot(v), -1.0, 1.0))
	var local_x := Vector3(cos(phz), cos(thx) * sin(phz), sin(thx) * sin(phz))
	var sgn := signf((upper.cross(v)).dot(local_x))
	if sgn == 0.0:
		sgn = 1.0
	return {"thx": thx, "phz": phz, "elb": sgn * B}


## Bat tip position in _body space, derived from the CURRENT posed angles.
## Used by QA to verify a genuine overhead wind-up and downward strike arc.
func bat_tip_body() -> Vector3:
	var S_r := Vector3(0.26, 1.47, 0.0)
	var R_arm := Basis(Vector3.RIGHT, _arm_r.rotation.x) \
		* Basis(Vector3(0, 0, 1), _arm_r.rotation.z)
	var E := S_r + (R_arm * Vector3(0, -1, 0)) * 0.31
	var R_fore := R_arm * Basis(Vector3.RIGHT, _fore_r.rotation.x)
	var H := E + (R_fore * Vector3(0, -0.37, -0.04))
	var R_bat := R_fore * Basis(Vector3.RIGHT, _weapon_pivot.rotation.x) \
		* Basis(Vector3(0, 0, 1), _weapon_pivot.rotation.z)
	return H + (R_bat * Vector3(0, 1, 0)).normalized() * 0.45



func _walk(delta: float, speed: float, k: float) -> void:
	var intensity := clampf(speed / 5.2, 0.0, 1.4)
	_phase += delta * (3.6 + speed * 1.55)
	var s := sin(_phase)
	var c := cos(_phase)
	var swing := 0.62 * intensity
	# Hips swing; knees flex as each leg travels back.
	_leg_l.rotation.x = s * swing
	_leg_r.rotation.x = -s * swing
	_shin_l.rotation.x = -maxf(0.0, -s) * 0.95 * intensity
	_shin_r.rotation.x = -maxf(0.0, s) * 0.95 * intensity
	# Shoulders counter-swing; elbows carry a natural bend that deepens
	# with speed.
	_arm_l.rotation.x = -s * 0.50 * intensity
	_arm_r.rotation.x = s * 0.50 * intensity
	var elbow := 0.22 + 0.40 * intensity
	_fore_l.rotation.x = -elbow - maxf(0.0, -s) * 0.25 * intensity
	_fore_r.rotation.x = -elbow - maxf(0.0, s) * 0.25 * intensity
	# Weight: double-frequency bob, forward lean that deepens into a
	# sprint crouch, lateral sway.
	var bob := absf(c) * 0.055 * intensity
	_body.position.y = bob
	_body.rotation.x = -(0.05 + 0.16 * intensity)
	_body.rotation.z = s * 0.035 * intensity
	# Head stays level: counter-bob, slight forward pitch at speed.
	_head.position.y = _head_base_y - bob * 0.35
	_head.rotation.x = lerpf(_base_prev_val("head_x", _head.rotation.x), 0.06 * intensity, k)
	_head.rotation.y = lerpf(_head.rotation.y, 0.0, k)
	_torso.scale.y = 1.0


func _idle(delta: float, k: float) -> void:
	_idle_t += delta
	var b := sin(_idle_t * 2.0)
	var sway := sin(_idle_t * 0.9)
	_leg_l.rotation.x = lerpf(_base_prev_val("leg_l", _leg_l.rotation.x), 0.0, k)
	_leg_r.rotation.x = lerpf(_base_prev_val("leg_r", _leg_r.rotation.x), 0.0, k)
	_shin_l.rotation.x = lerpf(_base_prev_val("shin_l", _shin_l.rotation.x), 0.0, k)
	_shin_r.rotation.x = lerpf(_base_prev_val("shin_r", _shin_r.rotation.x), 0.0, k)
	_arm_l.rotation.x = lerpf(_base_prev_val("arm_l", _arm_l.rotation.x), b * 0.03, k)
	_arm_r.rotation.x = lerpf(_base_prev_val("arm_r", _arm_r.rotation.x), -b * 0.03, k)
	_fore_l.rotation.x = lerpf(_base_prev_val("fore_l", _fore_l.rotation.x), -0.12, k)
	_fore_r.rotation.x = lerpf(_base_prev_val("fore_r", _fore_r.rotation.x), -0.12, k)
	_body.position.y = b * 0.012
	_body.rotation.x = lerpf(_base_prev_val("rx", _body.rotation.x), -0.02, k)
	_body.rotation.z = sway * 0.012
	_head.position.y = _head_base_y + b * 0.004
	_head.rotation.x = lerpf(_head.rotation.x, 0.0, k)
	_head.rotation.y = sin(_idle_t * 0.45) * 0.10 # slow look-around
	_torso.scale.y = 1.0 + b * 0.018 # breathing


func _make_materials() -> void:
	_m_jacket = _mat(Color(0.23, 0.24, 0.27), 0.78, 0.14) # charcoal, faint rim
	_m_jacket_dark = _mat(Color(0.16, 0.17, 0.19), 0.85) # collar, hem, cuffs
	_m_pants = _mat(Color(0.33, 0.32, 0.26), 0.85) # cargo khaki-olive
	_m_pants_dark = _mat(Color(0.25, 0.24, 0.20), 0.90) # pockets, belt
	_m_boots = _mat(Color(0.18, 0.13, 0.09), 0.55) # worn leather, slight sheen
	_m_boots_dark = _mat(Color(0.12, 0.09, 0.06), 0.62) # toe, heel, laces
	_m_sole = _mat(Color(0.07, 0.07, 0.07), 1.0) # rubber sole
	_m_skin = _mat(Color(0.74, 0.56, 0.43), 0.60)
	_m_skin_shade = _mat(Color(0.62, 0.46, 0.34), 0.65) # brow, nose, ears
	_m_hair = _mat(Color(0.12, 0.09, 0.06), 0.95) # dark hair
	_m_pack = _mat(Color(0.34, 0.35, 0.23), 0.85, 0.12) # olive pack, faint rim
	_m_pack_dark = _mat(Color(0.25, 0.26, 0.17), 0.90) # pouches, straps
	_m_eye = _mat(Color(0.05, 0.04, 0.03), 0.35) # dark inset eyes
	_m_mouth = _mat(Color(0.40, 0.26, 0.20), 0.70)
	_m_dark = _mat(Color(0.09, 0.09, 0.10), 0.70) # zipper, buckles, lamp
	# HD upgrade pass: gloves, knee pads, scuffs, flashlight lens.
	_m_glove = _mat(Color(0.16, 0.14, 0.11), 0.85) # worn work gloves
	_m_scuff = _mat(Color(0.15, 0.15, 0.16), 0.95) # dirt/scuff patches
	_m_lens = StandardMaterial3D.new() # flashlight lens, glows when lit
	_m_lens.albedo_color = Color(0.9, 0.88, 0.80)
	_m_lens.emission_enabled = true
	_m_lens.emission = Color(1.0, 0.95, 0.80)
	_m_lens.emission_energy_multiplier = 0.0


func _mat(c: Color, rough := 0.85, rim := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.55
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Tapered box frustum: flat-shaded, 12 tris. top/bot are Vector2(width, depth)
## at +h/2 and -h/2. The workhorse of the HD low-poly look — tapered limbs,
## sloped hems, wedge noses/toes (pass a near-zero top for a knife edge).
func _frustum(parent: Node3D, top: Vector2, bot: Vector2, h: float,
		pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var tx := top.x * 0.5
	var tz := top.y * 0.5
	var bx := bot.x * 0.5
	var bz := bot.y * 0.5
	var hy := h * 0.5
	var t := [Vector3(-tx, hy, -tz), Vector3(tx, hy, -tz),
		Vector3(tx, hy, tz), Vector3(-tx, hy, tz)]
	var b := [Vector3(-bx, -hy, -bz), Vector3(bx, -hy, -bz),
		Vector3(bx, -hy, bz), Vector3(-bx, -hy, bz)]
	# CCW from outside: top, bottom, front(-z), back(+z), right(+x), left(-x).
	var quads := [
		[t[3], t[2], t[1], t[0]],
		[b[0], b[1], b[2], b[3]],
		[b[0], b[1], t[1], t[0]],
		[b[2], b[3], t[3], t[2]],
		[b[2], b[1], t[1], t[2]],
		[b[0], b[3], t[3], t[0]],
	]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for vi in tri:
				verts.append(q[vi])
				normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_build_legs()
	_build_torso()
	_build_arms()
	_build_head()
	_build_flashlight()


func _build_legs() -> void:
	# Leg pivot at the hip (y 0.98); shin pivot at the knee.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side, 0.98, 0.0)
		_body.add_child(leg)
		# Tapered thigh; one clean cargo pocket + flap on the outer thigh.
		_frustum(leg, Vector2(0.20, 0.22), Vector2(0.15, 0.17), 0.40,
			Vector3(0, -0.20, 0), _m_pants)
		_box(leg, Vector3(0.06, 0.14, 0.11),
			Vector3(0.115 * side, -0.20, 0.015), _m_pants_dark)
		_box(leg, Vector3(0.065, 0.04, 0.115),
			Vector3(0.115 * side, -0.115, 0.015), _m_pants)
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.40, 0)
		leg.add_child(shin)
		# Tapered shin, cuff, then a shaped boot: sole, upper, sloped toe
		# wedge, single lace panel, heel.
		_frustum(shin, Vector2(0.15, 0.17), Vector2(0.105, 0.125), 0.36,
			Vector3(0, -0.18, 0), _m_pants)
		_box(shin, Vector3(0.125, 0.07, 0.145), Vector3(0, -0.335, 0), _m_pants_dark)
		# Knee pad: hard shell + strap.
		_box(shin, Vector3(0.13, 0.13, 0.05), Vector3(0, -0.13, -0.075), _m_dark)
		_box(shin, Vector3(0.135, 0.03, 0.155), Vector3(0, -0.075, 0), _m_dark)
		_box(shin, Vector3(0.14, 0.07, 0.30), Vector3(0, -0.545, -0.045), _m_sole)
		_frustum(shin, Vector2(0.125, 0.14), Vector2(0.14, 0.155), 0.15,
			Vector3(0, -0.435, -0.01), _m_boots)
		_frustum(shin, Vector2(0.11, 0.03), Vector2(0.135, 0.19), 0.09,
			Vector3(0, -0.475, -0.115), _m_boots)
		_box(shin, Vector3(0.07, 0.02, 0.10),
			Vector3(0, -0.40, -0.075), _m_boots_dark, Vector3(0.45, 0, 0))
		_box(shin, Vector3(0.125, 0.09, 0.05), Vector3(0, -0.455, 0.085), _m_boots_dark)
		if side < 0.0:
			_leg_l = leg
			_shin_l = shin
		else:
			_leg_r = leg
			_shin_r = shin


func _build_torso() -> void:
	# Pelvis, belt, tapered jacket torso, flared hem.
	_box(_body, Vector3(0.36, 0.14, 0.24), Vector3(0, 1.00, 0), _m_pants_dark)
	_box(_body, Vector3(0.37, 0.05, 0.25), Vector3(0, 1.075, 0), _m_dark) # belt
	_torso = _frustum(_body, Vector2(0.50, 0.30), Vector2(0.42, 0.26), 0.52,
		Vector3(0, 1.32, 0), _m_jacket)
	_frustum(_body, Vector2(0.42, 0.26), Vector2(0.445, 0.275), 0.08,
		Vector3(0, 1.10, 0), _m_jacket_dark) # hem, slight flare
	# Clean zipper line + pull tab, one chest pocket with flap,
	# shoulder seams, crisp V collar front + back.
	_box(_body, Vector3(0.045, 0.46, 0.02), Vector3(0, 1.31, -0.142), _m_dark)
	_box(_body, Vector3(0.028, 0.05, 0.02), Vector3(0.032, 1.17, -0.148), _m_dark)
	_box(_body, Vector3(0.14, 0.10, 0.025), Vector3(-0.13, 1.38, -0.138), _m_jacket_dark)
	_box(_body, Vector3(0.145, 0.04, 0.03), Vector3(-0.13, 1.44, -0.138), _m_jacket)
	_box(_body, Vector3(0.035, 0.02, 0.26), Vector3(0.232, 1.565, 0), _m_jacket_dark)
	_box(_body, Vector3(0.035, 0.02, 0.26), Vector3(-0.232, 1.565, 0), _m_jacket_dark)
	_box(_body, Vector3(0.15, 0.10, 0.04), Vector3(0.08, 1.615, -0.105),
		_m_jacket_dark, Vector3(0.35, 0, -0.18))
	_box(_body, Vector3(0.15, 0.10, 0.04), Vector3(-0.08, 1.615, -0.105),
		_m_jacket_dark, Vector3(0.35, 0, 0.18))
	_box(_body, Vector3(0.28, 0.10, 0.045), Vector3(0, 1.615, 0.10),
		_m_jacket_dark, Vector3(-0.35, 0, 0))
	# Backpack: tapered main body, lid, front pouch + flap, side pouches,
	# bedroll, tidy straps, sternum strap, resting hood.
	_frustum(_body, Vector2(0.34, 0.20), Vector2(0.30, 0.17), 0.44,
		Vector3(0, 1.30, 0.235), _m_pack)
	_box(_body, Vector3(0.36, 0.10, 0.22), Vector3(0, 1.53, 0.235), _m_pack_dark)
	_box(_body, Vector3(0.22, 0.18, 0.08), Vector3(0, 1.21, 0.35), _m_pack_dark)
	_box(_body, Vector3(0.23, 0.05, 0.085), Vector3(0, 1.315, 0.35), _m_pack)
	_box(_body, Vector3(0.08, 0.16, 0.14), Vector3(0.195, 1.24, 0.235), _m_pack)
	_box(_body, Vector3(0.08, 0.16, 0.14), Vector3(-0.195, 1.24, 0.235), _m_pack)
	_cyl(_body, 0.07, 0.34, Vector3(0, 1.62, 0.235), _m_dark, Vector3(0, 0, PI * 0.5))
	_box(_body, Vector3(0.08, 0.40, 0.025), Vector3(0.15, 1.31, -0.143), _m_pack_dark)
	_box(_body, Vector3(0.08, 0.40, 0.025), Vector3(-0.15, 1.31, -0.143), _m_pack_dark)
	_box(_body, Vector3(0.24, 0.035, 0.02), Vector3(0, 1.40, -0.148), _m_dark)
	_frustum(_body, Vector2(0.24, 0.09), Vector2(0.27, 0.11), 0.10,
		Vector3(0, 1.56, 0.14), _m_jacket)
	# Wear and tear: scuff patches on the jacket shoulder and thigh.
	_box(_body, Vector3(0.10, 0.07, 0.02), Vector3(-0.19, 1.52, -0.135),
		_m_scuff, Vector3(0, 0, 0.2))
	_box(_body, Vector3(0.07, 0.10, 0.02), Vector3(0.15, 1.28, -0.140),
		_m_scuff, Vector3(0, 0, -0.15))


func _build_arms() -> void:
	# Shoulder pivot; elbow pivot partway down. Tapered sleeves.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.26 * side, 1.47, 0.0)
		_body.add_child(arm)
		_frustum(arm, Vector2(0.15, 0.165), Vector2(0.115, 0.135), 0.30,
			Vector3(0, -0.15, 0), _m_jacket)
		var fore := Node3D.new()
		fore.position = Vector3(0, -0.31, 0)
		arm.add_child(fore)
		_frustum(fore, Vector2(0.115, 0.135), Vector2(0.095, 0.11), 0.26,
			Vector3(0, -0.13, 0), _m_jacket)
		_box(fore, Vector3(0.115, 0.06, 0.13), Vector3(0, -0.27, 0), _m_jacket_dark)
		_frustum(fore, Vector2(0.10, 0.105), Vector2(0.085, 0.095), 0.12,
			Vector3(0, -0.35, -0.01), _m_glove) # work glove
		_box(fore, Vector3(0.10, 0.03, 0.10), Vector3(0, -0.30, -0.02),
			_m_glove) # glove cuff
		if side < 0.0:
			_arm_l = arm
			_fore_l = fore
		else:
			_arm_r = arm
			_fore_r = fore


func _build_head() -> void:
	_head = Node3D.new()
	_head.position = Vector3(0, 1.72, 0)
	_body.add_child(_head)
	# Neck, tapered skull (wide brow, narrower jaw).
	_cyl(_head, 0.06, 0.12, Vector3(0, -0.13, 0), _m_skin)
	_frustum(_head, Vector2(0.22, 0.23), Vector2(0.175, 0.195), 0.26,
		Vector3(0, 0.02, 0), _m_skin)
	# Tidy face: single brow bar, aligned inset eyes, wedge nose, thin mouth,
	# small ears.
	_box(_head, Vector3(0.17, 0.04, 0.03), Vector3(0, 0.06, -0.10), _m_skin_shade)
	_eye_l = _box(_head, Vector3(0.042, 0.036, 0.02), Vector3(-0.052, 0.012, -0.104), _m_eye)
	_eye_r = _box(_head, Vector3(0.042, 0.036, 0.02), Vector3(0.052, 0.012, -0.104), _m_eye)
	_frustum(_head, Vector2(0.032, 0.018), Vector2(0.045, 0.055), 0.085,
		Vector3(0, -0.015, -0.112), _m_skin_shade) # nose
	_box(_head, Vector3(0.088, 0.02, 0.015), Vector3(0, -0.072, -0.096), _m_mouth)
	_box(_head, Vector3(0.03, 0.07, 0.05), Vector3(-0.112, 0.005, 0.01), _m_skin_shade)
	_box(_head, Vector3(0.03, 0.07, 0.05), Vector3(0.112, 0.005, 0.01), _m_skin_shade)
	# Clean stylized hair: top cap, back mass, side slabs, tidy fringe row.
	_frustum(_head, Vector2(0.235, 0.245), Vector2(0.25, 0.26), 0.09,
		Vector3(0, 0.165, 0.005), _m_hair)
	_box(_head, Vector3(0.24, 0.17, 0.10), Vector3(0, 0.075, 0.125), _m_hair)
	_box(_head, Vector3(0.045, 0.15, 0.18), Vector3(-0.118, 0.05, 0.025), _m_hair)
	_box(_head, Vector3(0.045, 0.15, 0.18), Vector3(0.118, 0.05, 0.025), _m_hair)
	for i in 3:
		_box(_head, Vector3(0.068, 0.06, 0.035),
			Vector3(-0.072 + 0.072 * i, 0.135, -0.095), _m_hair,
			Vector3(-0.18, 0, 0))


func _build_flashlight() -> void:
	# Chest-mounted flashlight (SpotLight3D shines along its -Z).
	var lamp_mount := Node3D.new()
	lamp_mount.position = Vector3(0.18, 1.42, -0.20)
	lamp_mount.rotation.x = -0.32 # tilt slightly down
	_body.add_child(lamp_mount)
	# Strap holding the lamp to the chest strap.
	_box(_body, Vector3(0.10, 0.05, 0.03), Vector3(0.18, 1.42, -0.155), _m_dark)
	var lamp_body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.055
	cyl.height = 0.16
	cyl.radial_segments = 10
	lamp_body.mesh = cyl
	lamp_body.rotation.x = PI * 0.5
	lamp_body.material_override = _m_dark
	lamp_mount.add_child(lamp_body)
	# Glowing lens at the lamp's front face.
	_box(lamp_mount, Vector3(0.07, 0.07, 0.02), Vector3(0, 0, -0.085), _m_lens)
	_flashlight = SpotLight3D.new()
	_flashlight.spot_range = 15.0
	_flashlight.spot_angle = 34.0
	_flashlight.light_color = Color(1.0, 0.95, 0.85)
	_flashlight.light_energy = 0.0
	_flashlight.shadow_enabled = false
	lamp_mount.add_child(_flashlight)
