class_name ZombieVisual
extends Node3D
## Phase 2 procedural walker, HD upgrade: sharper low-poly anatomy built from
## tapered frustums — defined skull (brow ridge, cheek planes, sunken
## sockets), exposed bone (forearm, shin, ribs, teeth), torn cloth strips
## hanging off the shirt/sleeves, per-instance body types (lanky / stocky /
## gaunt via seeded body scale). Same builder pattern as PlayerVisual
## (pivoted limbs) and the same public API: set_target_yaw, tick,
## tick_dead (death crumple), play_lunge, play_hit_reaction, flash_hit,
## set_eye_glow. All materials remain STATIC and shared across instances
## (mobile-first). Eyes glow at night.

var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D

var _phase := 0.0
var _target_yaw := 0.0
var _lunge_t := 0.0
var _head_base_y := 0.0
var _is_brute := false # set_brute(): heavier stomp in the shamble

# Per-instance visual variant key (QA: variety actually varies). Built in
# _build() from the seeded picks: shirt/pants/skin/wounds/shorts/stump/hair.
var _v_key := ""

# --- Hit feedback (combat): flinch overlay + white/red damage flash. ---
var _flinch_e := 99.0 # elapsed since flinch start; > FLINCH_TIME = inactive
const FLINCH_TIME := 0.30
# Additive flinch overlay via OverlayMixer: play_hit_reaction starts the
# envelope; _apply_flinch adds pure offsets on top of the live base pose
# each frame. An interrupting hit (or death) decays the in-flight offsets
# over 0.2s instead of popping, and nothing can ever accumulate.
var _mixer := OverlayMixer.new()
# Pure base-pose values from last frame (before the flinch overlay). The
# idle easing MUST read these, never the live nodes: the nodes carry last
# frame's flinch offsets, and lerping those would feed the offsets back
# into the base and amplify them. Updated every tick (see tick()).
var _base_prev := {}
# Lunge -> shamble crossfade: captured pose + remaining blend time.
var _lunge_from := {}
var _lunge_blend := 0.0
var _flash_t := 0.0
var _flash_on := false
var _meshes: Array[MeshInstance3D] = []

# Phase 3: idle variation — occasional twitches so no two zombies stand alike.
# Offsets are applied differentially (current minus previous frame) so the
# base pose always wins back with zero residual when the twitch ends.
var _twitch_t := 2.0
var _twitch_kind := 0 # 0 none, 1 head snap, 2 arm spasm, 3 body shudder
var _twitch_dur := 0.5
var _twitch_el := 0.0
var _twitch_dir := 1.0
var _twitch_prev := 0.0
static var _flash_mat: StandardMaterial3D = null

# --- ANIMATION STATE-NAME CONTRACT -------------------------------------
# Standard state names (from Tbandz's character animation kit). Our
# procedural rig maps to these names; when GLB/FBX clips are imported
# later they drop in under these names with no rewiring.
#   idle        -> _idle_sway (breathing, blinks of variation via twitch)
#   walk        -> _shamble (dragging asymmetric gait: weight shift,
#                    torso twist, scraping foot, out-of-phase arm sway)
#   run         -> _shamble at chase speed (faster phase, wider swing)
#   attack      -> _lunge: arms-only claw swipe, body planted (0.38s):
#                    wind-up coil, violent snap peaking at the 0.22s
#                    damage instant, soft recover
#   attack_2    -> (reserved: brute overhead slam variant)
#   hit_front   -> play_hit_reaction: hard stagger — torso rocks back,
#                    body shoved a step, asymmetric arm flail (0.30s)
#   hit_back    -> (reserved: directional flinch; currently hit_front)
#   hit_left    -> (reserved: directional flinch; currently hit_front)
#   hit_right   -> (reserved: directional flinch; currently hit_front)
#   stagger     -> (reserved: heavy-hit stagger; currently hit_front)
#   crawl       -> (reserved)
#   crawl_attack-> (reserved)
#   turn_left   -> yaw easing in tick() (lerp_angle toward _target_yaw)
#   turn_right  -> yaw easing in tick()
#   fall        -> (reserved)
#   death       -> tick_dead: two-stage crumple — fast waist fold with
#                    arm sprawl, then a soft settle (0.45s; AI lays the
#                    body flat underneath)
#   death_2     -> (reserved: alternate death variant)
#   death_crawl -> (reserved)
# -----------------------------------------------------------------------

# Death crumple: folded over ~0.45s by tick_dead (called from the AI's dead
# branch), on top of the whole-body fall-flat the AI already applies.
var _dead_t := -1.0
const DEAD_TIME := 0.45

# Shared materials, built once for every zombie.
static var _mats: Dictionary = {}


static func shared_mats() -> Dictionary:
	if _mats.is_empty():
		_mats["skin"] = _mk(Color(0.52, 0.58, 0.46), 0.85) # pale grey-green
		_mats["skin_dark"] = _mk(Color(0.38, 0.44, 0.34), 0.9)
		_mats["shirt"] = _mk(Color(0.30, 0.28, 0.32), 0.95) # torn dark shirt
		_mats["shirt_b"] = _mk(Color(0.36, 0.26, 0.20), 0.95) # variant: filthy brown
		_mats["shirt_c"] = _mk(Color(0.22, 0.26, 0.30), 0.95) # variant: dead blue
		_mats["shirt_d"] = _mk(Color(0.32, 0.34, 0.20), 0.95) # variant: sickly olive
		_mats["shirt_e"] = _mk(Color(0.42, 0.20, 0.18), 0.95) # variant: faded crimson
		_mats["shirt_f"] = _mk(Color(0.20, 0.32, 0.32), 0.95) # variant: dirty teal
		_mats["shirt_dark"] = _mk(Color(0.14, 0.13, 0.16), 1.0)
		_mats["pants"] = _mk(Color(0.25, 0.24, 0.28), 0.95) # ripped trousers
		_mats["pants_b"] = _mk(Color(0.30, 0.28, 0.20), 0.95) # variant: khaki
		_mats["pants_c"] = _mk(Color(0.18, 0.22, 0.32), 0.95) # variant: dark denim
		_mats["pants_d"] = _mk(Color(0.12, 0.12, 0.14), 0.95) # variant: torn black
		_mats["skin_b"] = _mk(Color(0.55, 0.52, 0.38), 0.85) # sallow yellow-grey
		_mats["skin_c"] = _mk(Color(0.45, 0.45, 0.44), 0.9) # ashen pale
		_mats["wound"] = _mk(Color(0.32, 0.10, 0.08), 1.0) # dark wounds
		var bloodm := _mk(Color(0.22, 0.05, 0.05), 0.45) # dried blood, wet sheen
		bloodm.metallic = 0.1 # V3: faint specular so wounds glint
		_mats["blood"] = bloodm
		var bonem := _mk(Color(0.78, 0.72, 0.58), 0.7) # exposed bone
		bonem.metallic = 0.05 # V3: faint mineral sheen
		_mats["bone"] = bonem
		_mats["hair"] = _mk(Color(0.16, 0.13, 0.10), 1.0) # matted hair
		var eye := StandardMaterial3D.new()
		eye.albedo_color = Color(0.85, 0.82, 0.55)
		eye.emission_enabled = true
		eye.emission = Color(0.9, 0.85, 0.45)
		eye.emission_energy_multiplier = 0.0
		_mats["eye"] = eye
	return _mats


static func _mk(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func set_eye_glow(energy: float) -> void:
	var eye := shared_mats()["eye"] as StandardMaterial3D
	eye.emission_energy_multiplier = energy


func _ready() -> void:
	shared_mats()
	_build()
	_head_base_y = _head.position.y
	_collect_meshes(self)
	_get_flash_mat()


## Brute variant look: riot-gear remnant. Bulkier body, tactical vest,
## shoulder pads, cracked riot helmet. Called by ZombieAI.make_brute().
func set_brute() -> void:
	if _is_brute:
		return # idempotent: gear meshes must never stack
	_is_brute = true
	_body.scale = Vector3(1.32, 1.10, 1.22)
	# Thicker limbs: the bulk has to read in the silhouette, not just the
	# torso. Arm/leg pivots scale their children (cheap, no new meshes).
	_arm_l.scale = Vector3(1.35, 1.0, 1.35)
	_arm_r.scale = Vector3(1.35, 1.0, 1.35)
	_leg_l.scale = Vector3(1.25, 1.0, 1.25)
	_leg_r.scale = Vector3(1.25, 1.0, 1.25)
	var M := shared_mats()
	var gear: Material = M["pants"] # dark charcoal
	# Tactical vest over the torso.
	_box(_body, Vector3(0.58, 0.52, 0.44), Vector3(0, 1.12, 0.02), gear)
	_box(_body, Vector3(0.40, 0.30, 0.05), Vector3(0, 1.14, -0.20),
		M["shirt_dark"]) # vest front plate
	# Shoulder pads.
	_box(_body, Vector3(0.24, 0.18, 0.32), Vector3(-0.38, 1.36, 0), gear)
	_box(_body, Vector3(0.24, 0.18, 0.32), Vector3(0.38, 1.36, 0), gear)
	# Cracked riot helmet.
	_box(_head, Vector3(0.36, 0.22, 0.38), Vector3(0, 0.13, -0.01), gear)
	_box(_head, Vector3(0.30, 0.10, 0.02), Vector3(0, 0.02, -0.19),
		M["wound"]) # shattered visor
	_meshes.clear()
	_collect_meshes(self) # include the gear in the hit-flash pass
	# NOTE: set_brute recollects; cleared first (called after _ready's pass).


func set_target_yaw(y: float) -> void:
	_target_yaw = y


## Directed head snap: the zombie visibly reacts to a noise, turning its
## head toward the stimulus before it starts moving. Reuses the head-snap
## twitch channel (differential offsets, zero residue) with a forced
## direction instead of a random one.
func notice(dir_sign: float) -> void:
	if _ragdolled:
		return
	_twitch_kind = 1
	_twitch_dur = 0.45
	_twitch_el = 0.0
	_twitch_dir = dir_sign if dir_sign != 0.0 else 1.0
	_twitch_prev = 0.0
	_twitch_t = randf_range(2.5, 6.5) # don't chain another twitch right after


## QA: the per-instance visual variant key (shirt/pants/skin/wounds/etc).
func variant_key() -> String:
	return _v_key


## QA: live pose snapshot for animation checks.
func debug_pose() -> Dictionary:
	return {
		"phase": _phase,
		"arm_l_x": _arm_l.rotation.x,
		"arm_r_x": _arm_r.rotation.x,
		"body_y": _body.position.y,
		"is_brute": _is_brute,
	}


func play_lunge() -> void:
	_lunge_t = 0.38


## Called by ZombieAI.take_damage: quick stagger — torso rocks back, head
## snaps, arms flail up — blended as an overlay on top of the shamble.
func play_hit_reaction(_from_dir: Vector3) -> void:
	if _ragdolled:
		return
	# Unwind any in-flight flinch: its offsets decay out over 0.2s, so
	# rapid hits can't stack residue or pop.
	if _flinch_e <= FLINCH_TIME:
		_mixer.interrupt()
	_flinch_e = 0.0


## Brief white/red emissive flash so the connect reads even at distance.
func flash_hit() -> void:
	if _ragdolled:
		return
	_flash_t = 0.13
	_set_flash(true)


## Called once by ZombieAI._die: folds the body into a crumple.
func play_death() -> void:
	# Unwind any in-flight flinch; its offsets decay out over 0.2s into the
	# death pose (tick_dead keeps mixing until the residue is gone).
	if _flinch_e <= FLINCH_TIME:
		_mixer.interrupt()
	_flinch_e = 99.0
	_dead_t = 0.0


# --- Procedural ragdoll death (ProcRagdoll) -------------------------------
# Part descriptors for ProcRagdoll.spawn: pivot, collision box (center in
# pivot space + size), mass. The torso (limb=false) is what everything
# joints to.
func ragdoll_parts() -> Array:
	return [
		{"pivot": _body, "center": Vector3(0, 1.08, 0),
			"size": Vector3(0.55, 0.78, 0.42), "mass": 9.0, "limb": false},
		{"pivot": _head, "center": Vector3(0, 0.02, 0),
			"size": Vector3(0.30, 0.32, 0.30), "mass": 2.2, "limb": true},
		{"pivot": _arm_l, "center": Vector3(0, -0.30, 0),
			"size": Vector3(0.20, 0.66, 0.20), "mass": 2.6, "limb": true},
		{"pivot": _arm_r, "center": Vector3(0, -0.30, 0),
			"size": Vector3(0.20, 0.66, 0.20), "mass": 2.6, "limb": true},
		{"pivot": _leg_l, "center": Vector3(0, -0.44, 0),
			"size": Vector3(0.24, 0.92, 0.26), "mass": 4.6, "limb": true},
		{"pivot": _leg_r, "center": Vector3(0, -0.44, 0),
			"size": Vector3(0.24, 0.92, 0.26), "mass": 4.6, "limb": true},
	]


var _ragdolled := false


## Called by ZombieAI._die when the ragdoll spawns: the physics server owns
## the pivots now — every procedural writer must stand down (and any
## mid-death hit flash is cleared so it can't stick on the corpse).
func set_ragdolled() -> void:
	_ragdolled = true
	_mixer.interrupt()
	_flinch_e = 99.0
	_flash_t = 0.0
	_set_flash(false)
	_dead_t = -1.0


func tick(delta: float, speed: float, moving: bool) -> void:
	if _ragdolled:
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-6.0 * delta))
	var was_lunge := _lunge_t > 0.0
	if was_lunge:
		_lunge_t -= delta
		_lunge(delta)
		if _lunge_t <= 0.0:
			# Final lunge frame: capture the lunge pose BEFORE the base
			# pose below overwrites it, then crossfade into the base over
			# 0.15s instead of snapping (the shamble phase was frozen
			# during the lunge, so its legs would otherwise jump).
			_lunge_from = {
				"rx": _body.rotation.x, "rz": _body.rotation.z,
				"ry": _body.rotation.y, "px": _body.position.x,
				"pz": _body.position.z, "py": _body.position.y,
				"leg_l": _leg_l.rotation.x, "leg_r": _leg_r.rotation.x,
				"arm_l": _arm_l.rotation.x, "arm_r": _arm_r.rotation.x,
				"head_x": _head.rotation.x,
			}
			_lunge_blend = 0.15
	if _lunge_t <= 0.0:
		# Base pose. Also runs on the lunge's final frame so the crossfade
		# below has a live target to blend toward.
		if moving:
			_shamble(delta, speed)
		else:
			_idle_sway(delta)
	if _lunge_blend > 0.0:
		_lunge_blend -= delta
		var w := 1.0 - smoothstep(0.0, 0.15, maxf(_lunge_blend, 0.0))
		w = w * w * (3.0 - 2.0 * w) # smootherstep: gentler ends
		_body.rotation.x = lerpf(_lunge_from["rx"], _body.rotation.x, w)
		_body.rotation.z = lerpf(_lunge_from["rz"], _body.rotation.z, w)
		_body.rotation.y = lerpf(_lunge_from["ry"], _body.rotation.y, w)
		_body.position.x = lerpf(_lunge_from["px"], _body.position.x, w)
		_body.position.z = lerpf(_lunge_from["pz"], _body.position.z, w)
		_body.position.y = lerpf(_lunge_from["py"], _body.position.y, w)
		_leg_l.rotation.x = lerpf(_lunge_from["leg_l"], _leg_l.rotation.x, w)
		_leg_r.rotation.x = lerpf(_lunge_from["leg_r"], _leg_r.rotation.x, w)
		_arm_l.rotation.x = lerpf(_lunge_from["arm_l"], _arm_l.rotation.x, w)
		_arm_r.rotation.x = lerpf(_lunge_from["arm_r"], _arm_r.rotation.x, w)
		_head.rotation.x = lerpf(_lunge_from["head_x"], _head.rotation.x, w)
	# Snapshot the pure base values for next frame's idle easing BEFORE the
	# flinch overlay is applied (see _base_prev). Every tick, flinch or not.
	var fbase := _flinch_base()
	_base_prev = fbase
	if _flinch_e <= FLINCH_TIME:
		_apply_flinch(delta, fbase)
	elif _mixer.has_residue():
		# The flinch ended while an older interrupt was still decaying:
		# keep mixing with empty offsets until the residue is fully gone,
		# so _last_total can't get stuck above zero.
		_write_flinch(_mixer.mix(delta, fbase, {}))
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_flash(false)


## Death branch: the AI rotates the whole body flat; this folds the limbs
## in so it reads as a crumple, not a stiff board falling over.
func tick_dead(delta: float) -> void:
	if _ragdolled:
		return
	if _dead_t < 0.0:
		return
	_apply_twitch(delta, false) # finish any in-flight twitch, start none
	_dead_t += delta
	var t := clampf(_dead_t / DEAD_TIME, 0.0, 1.0)
	# Two-stage: a fast crumple (fold at the waist, arms sprawl) then a
	# soft settle into the ground. Ease-out cubic on the crumple, gentle
	# ease on the settle.
	var e1 := 1.0 - pow(1.0 - clampf(t / 0.62, 0.0, 1.0), 3.0) # crumple
	var e2 := clampf((t - 0.62) / 0.38, 0.0, 1.0) # settle
	e2 = e2 * e2 * (3.0 - 2.0 * e2)
	_body.position.y = -0.34 * e1 - 0.06 * e2 # torso sinks, then settles
	_body.rotation.x = 0.34 + 0.55 * e1 # folds forward at the waist
	_body.rotation.z = 0.22 * e1 + 0.06 * e2 # slight sideways twist
	_head.rotation.x = 0.18 + 0.85 * e1 # chin drops to chest
	_head.rotation.z = 0.35 * e1 + 0.10 * e2 # lolls to one side
	_arm_l.rotation.x = -0.55 - 0.55 * e1
	_arm_r.rotation.x = -0.75 - 0.45 * e1
	_arm_l.rotation.z = 0.10 + 0.55 * e1 + 0.35 * e2 # arms sprawl outward
	_arm_r.rotation.z = -0.14 - 0.55 * e1 - 0.35 * e2
	_leg_l.rotation.x = 0.25 * e1
	_leg_r.rotation.x = -0.30 * e1
	_shin_l.rotation.x = -0.55 * e1
	_shin_r.rotation.x = -0.70 * e1
	# Decay any interrupted flinch residue into the death pose instead of
	# snapping it away.
	if _mixer.has_residue():
		_write_flinch(_mixer.mix(delta, _flinch_base(), {}))


## Last frame's pure base value for a channel (falls back to the live node
## on the very first frame). Keeps the idle easing out of the flinch
## overlay's feedback loop (see _base_prev).
func _base_prev_val(ch: String, cur: float) -> float:
	return float(_base_prev.get(ch, cur))


## Live base-pose values for the flinch channels. The base pose writes
## body.position.z (shamble lurch), so it reads live — the flinch overlay
## never touches z, it just must not reset it.
func _flinch_base() -> Dictionary:
	return {
		"rx": _body.rotation.x, "pz": _body.position.z,
		"py": _body.position.y,
		"head_x": _head.rotation.x,
		"arm_l": _arm_l.rotation.x, "arm_r": _arm_r.rotation.x,
		"arml_z": _arm_l.rotation.z, "armr_z": _arm_r.rotation.z,
	}


func _write_flinch(d: Dictionary) -> void:
	_body.rotation.x = d["rx"]
	_body.position.z = d["pz"]
	_head.rotation.x = d["head_x"]
	_arm_l.rotation.x = d["arm_l"]
	_arm_r.rotation.x = d["arm_r"]
	_arm_l.rotation.z = d["arml_z"]
	_arm_r.rotation.z = d["armr_z"]


func _apply_flinch(delta: float, base: Dictionary) -> void:
	# Pure envelope offsets (0 -> 1 -> 0 over FLINCH_TIME), added on top of
	# the live base pose. The envelope is sampled BEFORE advancing, so an
	# interrupting hit starts its new envelope at exactly 0 while the
	# captured residue carries the continuity (no double-count, no pop).
	# The final sample lands on t=1 (f=0), leaving _last_total at zero.
	var t := clampf(_flinch_e / FLINCH_TIME, 0.0, 1.0)
	_flinch_e += delta
	var f := sin(t * PI)
	# Quality pass: a real STAGGER, not a twitch. The torso rocks back
	# hard, the whole body is shoved backward a step, the head snaps,
	# and the arms flail up ASYMMETRICALLY (one high, one wide) so it
	# reads at a glance even mid-shamble.
	var offsets := {
		"rx": f * 0.52, # torso rocks BACK, away from the attacker
		"pz": f * 0.22, # shoved BACKWARD a real step
		"head_x": f * 0.62, # head snaps back
		"arm_l": -f * 1.15, # left arm flails high
		"arm_r": -f * 0.65, # right arm flails wide
		"arml_z": f * 0.55,
		"armr_z": -f * 0.65,
	}
	_write_flinch(_mixer.mix(delta, base, offsets))


func _set_flash(on: bool) -> void:
	if _flash_on == on:
		return
	_flash_on = on
	for m in _meshes:
		m.material_overlay = _flash_mat if on else null


func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		_collect_meshes(c)


static func _get_flash_mat() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.82, 0.78)
	return _flash_mat


func _shamble(delta: float, speed: float) -> void:
	# Slow, dragging, asymmetric shamble with arm lag — quality pass:
	# lateral weight shift, torso twist against the hips, one foot
	# audibly dragging (flat, scraping), arms swinging out of phase.
	_phase += delta * (2.2 + speed * 1.1)
	var s := sin(_phase)
	var s2 := sin(_phase * 0.5 + 1.3) # asymmetry: one leg drags
	var swing := 0.42 + speed * 0.06
	_leg_l.rotation.x = s * swing
	_leg_r.rotation.x = -s2 * swing * 0.8
	_shin_l.rotation.x = -maxf(0.0, -s) * 0.5
	_shin_r.rotation.x = -maxf(0.0, s2) * 0.35 # dragging leg barely bends
	# Dragging foot scrapes: the right leg stays flatter and lower through
	# its swing, never lifting like the left.
	_leg_r.rotation.z = 0.05 + s2 * 0.03
	# Dangling arms: hang forward-down, lag behind the body sway, swinging
	# out of phase with each other (left leads, right trails). Brutes
	# swing wider — the bulk has to read in motion too.
	var sway := 1.3 if _is_brute else 1.0
	var lag := sin(_phase - 0.9)
	_arm_l.rotation.x = -0.55 + lag * 0.16 * sway
	_arm_r.rotation.x = -0.75 + sin(_phase * 0.5 + 0.4) * 0.20 * sway
	_arm_l.rotation.z = 0.10 + s * 0.06 * sway
	_arm_r.rotation.z = -0.14 + s2 * 0.07 * sway
	# Heavy hunch + lateral WEIGHT SHIFT (hips rock side to side as the
	# weight transfers) + torso twist against the stride + head loll.
	# NOTE: keep the COMBINED lateral (body.z + head.z) modest — the head
	# sits 1.5m up, so large angles read as a detached head in stills.
	# Upgrade: a forward LURCH synced to the stride (the step lands with
	# weight) and a heavier vertical bob for brutes (stomp). Bob stays
	# phase-locked so it never fights the leg motion.
	var stomp := 1.7 if _is_brute else 1.0
	_body.rotation.x = 0.34 + sin(_phase) * 0.02
	_body.rotation.z = sin(_phase * 0.5) * 0.08
	_body.rotation.y = sin(_phase * 0.5 + 0.6) * 0.05 # twist vs hips
	_body.position.x = sin(_phase * 0.5) * 0.04 # weight shift
	_body.position.y = absf(cos(_phase)) * 0.035 * stomp
	_body.position.z = -absf(sin(_phase)) * 0.035 # forward lurch on the step
	_head.position.y = _head_base_y - absf(cos(_phase)) * 0.015 * stomp
	_head.rotation.z = sin(_phase * 0.5 + 0.7) * 0.20
	_head.rotation.x = 0.18 + sin(_phase * 0.33) * 0.07
	_apply_twitch(delta) # keep advancing: never freeze a twitch mid-flight


func _idle_sway(delta: float) -> void:
	_phase += delta * 1.1
	# Delta-based easing (frame-rate independent): ease toward the rest pose
	# instead of snapping when the shamble stops. Reads last frame's PURE
	# base values so flinch offsets can't feed back into the easing.
	var k := 1.0 - exp(-8.0 * delta)
	_leg_l.rotation.x = lerpf(_base_prev_val("leg_l", _leg_l.rotation.x), 0.0, k)
	_leg_r.rotation.x = lerpf(_base_prev_val("leg_r", _leg_r.rotation.x), 0.0, k)
	_arm_l.rotation.x = lerpf(_base_prev_val("arm_l", _arm_l.rotation.x), -0.55, k)
	_arm_r.rotation.x = lerpf(_base_prev_val("arm_r", _arm_r.rotation.x), -0.75, k)
	_body.rotation.x = lerpf(_base_prev_val("rx", _body.rotation.x), 0.34, k)
	_body.position.y = lerpf(_base_prev_val("py", _body.position.y), 0.0, k)
	_body.position.z = lerpf(_base_prev_val("pz", _body.position.z), 0.0, k)
	_body.rotation.z = sin(_phase) * 0.035
	_head.rotation.z = sin(_phase * 0.7) * 0.12
	_head.rotation.x = 0.18
	_apply_twitch(delta)


func _apply_twitch(delta: float, can_trigger := true) -> void:
	# Additive overlay: every few seconds one random twitch fires.
	# The twitch MUST advance in every animation state (not just idle):
	# the offsets are differential and only net back to zero if the
	# twitch runs to completion. A twitch frozen mid-flight by a state
	# change used to leave the head permanently twisted.
	_twitch_t -= delta
	if can_trigger and _twitch_kind == 0 and _twitch_t <= 0.0:
		_twitch_kind = randi_range(1, 3)
		_twitch_dur = randf_range(0.35, 0.65)
		_twitch_el = 0.0
		_twitch_dir = 1.0 if randf() < 0.5 else -1.0
		_twitch_prev = 0.0
		_twitch_t = randf_range(2.5, 6.5)
	if _twitch_kind == 0:
		return
	_twitch_el += delta
	var t := clampf(_twitch_el / _twitch_dur, 0.0, 1.0)
	var f := sin(t * PI)
	var d := f - _twitch_prev # differential: no accumulation, no residue
	_twitch_prev = f
	match _twitch_kind:
		1: # head snap
			_head.rotation.y += d * 0.70 * _twitch_dir
			_head.rotation.x = 0.18 - f * 0.22 # base pose sets this absolutely
		2: # arm spasm
			_arm_r.rotation.x -= d * 0.80
			_arm_r.rotation.z -= d * 0.50 * _twitch_dir
		3: # body shudder
			_body.rotation.z += d * 0.12 * _twitch_dir
			_body.rotation.x -= d * 0.10
	if t >= 1.0:
		_twitch_kind = 0
		_twitch_prev = 0.0


func _lunge(delta: float) -> void:
	# ARMS-ONLY swipe (Tbandz: "the zombie swings and kinda swung his body").
	# The body stays planted: no forward pitch, no rock, no leg shift, no
	# lateral drift. Quality pass: real attack SHAPE — wind-up anticipation
	# (arms coil up/back, slight crouch) then a violent SNAP down, strike
	# peaking at t=0.58 of the envelope (0.22s: exactly when the AI lands
	# damage), then a soft recover. Same 0.38s envelope the AI's damage
	# timing was tuned against. Damage, range, cooldown, AI: untouched.
	var t := 1.0 - _lunge_t / 0.38 # 0 -> 1
	var rest_l := -0.55
	var rest_r := -0.75
	var wound_l := -1.70 # coiled high: a bigger, clearer telegraph
	var wound_r := -1.90
	var struck_l := 0.35 # raked down past rest
	var struck_r := 0.25
	var ax_l := rest_l
	var ax_r := rest_r
	var spread := 0.0
	var dip := 0.0
	var head_x := 0.18
	if t < 0.32:
		# WIND-UP: arms coil up and back, body sinks a breath, head tilts
		# up — the tell before the swipe.
		var f := t / 0.32
		f = 1.0 - pow(1.0 - f, 2.0) # ease-out: quick coil, held threat
		ax_l = lerpf(rest_l, wound_l, f)
		ax_r = lerpf(rest_r, wound_r, f)
		dip = -0.03 * f
		head_x = 0.18 - 0.14 * f
	elif t < 0.62:
		# STRIKE: violent snap down. pow>1 keeps the first instants slow
		# then whips through — the claws land at peak velocity.
		var f := (t - 0.32) / 0.30
		f = pow(f, 2.0)
		ax_l = lerpf(wound_l, struck_l, f)
		ax_r = lerpf(wound_r, struck_r, f)
		spread = f * 0.22 # claws spread on the strike
		dip = -0.03 + 0.09 * f # body drops INTO the swipe
		head_x = 0.04 + 0.30 * f # head snaps down with the arms
	else:
		# RECOVER: soft ease back to the dangling rest pose.
		var f := (t - 0.62) / 0.38
		f = f * f * (3.0 - 2.0 * f) # smootherstep
		ax_l = lerpf(struck_l, rest_l, f)
		ax_r = lerpf(struck_r, rest_r, f)
		spread = 0.22 * (1.0 - f)
		dip = 0.06 * (1.0 - f)
		head_x = 0.34 - 0.16 * f
	_body.rotation.x = 0.34 # base hunch, held — no rock
	_body.rotation.z = 0.0
	_body.rotation.y = 0.0
	_body.position.x = 0.0
	_body.position.y = dip # vertical only: the feet never move
	_arm_l.rotation.x = ax_l
	_arm_r.rotation.x = ax_r
	_arm_l.rotation.z = 0.10 + spread
	_arm_r.rotation.z = -0.14 - spread
	_head.rotation.x = head_x
	_head.rotation.z = 0.0
	_leg_l.rotation.x = 0.0 # feet planted
	_leg_r.rotation.x = 0.0
	_leg_r.rotation.z = 0.0
	_shin_l.rotation.x = 0.0
	_shin_r.rotation.x = 0.0
	_apply_twitch(delta, false) # finish any in-flight twitch, start none


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


## Tapered box frustum: flat-shaded, 12 tris. top/bot are Vector2(width,
## depth) at +h/2 and -h/2 — the workhorse of the HD low-poly look.
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


func _build() -> void:
	var M := shared_mats()
	# Per-instance variety: seeded picks across an expanded wardrobe —
	# zero extra materials, every zombie reads different. Same global-RNG
	# convention the file already uses (visual-only draws; layout hashes
	# untouched, seed_qa green).
	var shirts: Array = [M["shirt"], M["shirt_b"], M["shirt_c"],
		M["shirt_d"], M["shirt_e"], M["shirt_f"]]
	var pants_arr: Array = [M["pants"], M["pants_b"], M["pants_c"], M["pants_d"]]
	var skins: Array = [M["skin"], M["skin_b"], M["skin_c"]]
	var si := randi_range(0, shirts.size() - 1)
	var pi := randi_range(0, pants_arr.size() - 1)
	var ki := randi_range(0, skins.size() - 1)
	var shirt: Material = shirts[si]
	var pants: Material = pants_arr[pi]
	var skin: Material = skins[ki]
	var wounds := randi_range(0, 2) # 0 chest cavity, 1 neck+arm, 2 gut+thigh
	var shorts := randf() < 0.25 # torn shorts: bare legs, no trousers
	var stump := randf() < 0.15 # right forearm lost: bloody stump
	var hair_v := randi_range(0, 2) # 0 matted, 1 patchy, 2 bald
	_v_key = "s%dp%dk%dw%d%s%sh%d" % [si, pi, ki, wounds,
		"o" if shorts else "", "t" if stump else "", hair_v]
	_body = Node3D.new()
	_body.rotation.x = 0.34 # permanent hunch
	add_child(_body)
	var bt := randf() # body type
	if bt < 0.33:
		_body.scale = Vector3(0.90, 1.10, 0.90) # lanky: tall, narrow
	elif bt < 0.66:
		_body.scale = Vector3(1.16, 0.94, 1.08) # stocky: wide, short
	else:
		_body.scale = Vector3(0.84, 1.02, 0.84) # gaunt: skeletal
	_build_legs(M, pants, skin, shorts)
	_build_torso(M, shirt, wounds)
	_build_arms(M, shirt, skin, stump)
	_build_head(M, skin, hair_v)


func _build_legs(M: Dictionary, pants: Material, skin: Material,
		shorts: bool) -> void:
	# Tapered thighs; trousers or torn shorts. One shin is always stripped
	# to the bone (iconic); with shorts both legs go bare.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side, 0.92, 0.0)
		_body.add_child(leg)
		_frustum(leg, Vector2(0.19, 0.21), Vector2(0.14, 0.16), 0.38,
			Vector3(0, -0.19, 0), pants)
		if shorts:
			# Torn shorts hem instead of a full trouser leg.
			_box(leg, Vector3(0.20, 0.10, 0.02), Vector3(0, -0.30, -0.10),
				pants, Vector3(0.4, 0, 0.2 * side))
		else:
			# Torn cuff flap.
			_box(leg, Vector3(0.05, 0.14, 0.02),
				Vector3(0.08 * side, -0.36, -0.09), pants,
				Vector3(0.5, 0, 0.3 * side))
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.38, 0)
		leg.add_child(shin)
		# Knee joint block.
		_box(shin, Vector3(0.16, 0.12, 0.17), Vector3(0, -0.02, 0),
			M["skin_dark"])
		if side < 0.0:
			# Left: flesh shin with a deep gash, shoe intact — or bare
			# with shorts (shoe lost, bloody foot).
			_frustum(shin, Vector2(0.14, 0.16), Vector2(0.10, 0.12), 0.32,
				Vector3(0, -0.20, 0), skin)
			_box(shin, Vector3(0.09, 0.16, 0.02),
				Vector3(0.02, -0.20, -0.075), M["wound"],
				Vector3(0.1, 0, 0.15)) # gash
			if shorts:
				_frustum(shin, Vector2(0.11, 0.12), Vector2(0.13, 0.22), 0.09,
					Vector3(0, -0.40, -0.03), M["blood"]) # mangled foot
			else:
				_box(shin, Vector3(0.16, 0.10, 0.28),
					Vector3(0, -0.40, -0.04), M["shirt_dark"]) # shoe
			_leg_l = leg
			_shin_l = shin
		else:
			# Right: trousers torn away — bare tibia, bloody foot, no shoe.
			_box(shin, Vector3(0.055, 0.30, 0.055), Vector3(0.015, -0.21, 0),
				M["bone"], Vector3(0.06, 0, 0.05)) # tibia
			_box(shin, Vector3(0.045, 0.28, 0.045),
				Vector3(-0.035, -0.21, 0.01), M["bone"],
				Vector3(-0.05, 0, -0.06)) # fibula
			_box(shin, Vector3(0.10, 0.10, 0.13), Vector3(0, -0.06, 0),
				M["wound"]) # flesh remnant at knee
			_frustum(shin, Vector2(0.11, 0.12), Vector2(0.13, 0.22), 0.09,
				Vector3(0, -0.40, -0.03), M["blood"]) # mangled foot
			_leg_r = leg
			_shin_r = shin


func _build_torso(M: Dictionary, shirt: Material, wounds: int) -> void:
	# Tapered torso, torn shirt; wounds vary per instance (variant 0 keeps
	# the classic ripped-open chest).
	_frustum(_body, Vector2(0.44, 0.30), Vector2(0.36, 0.26), 0.48,
		Vector3(0, 1.16, 0.02), shirt)
	match wounds:
		0:
			# Torn-open chest: dark cavity, rib slivers, bite wound.
			_box(_body, Vector3(0.22, 0.24, 0.03),
				Vector3(-0.05, 1.14, -0.115), M["wound"])
			for i in 2:
				_box(_body, Vector3(0.16 - 0.02 * i, 0.025, 0.02),
					Vector3(-0.05, 1.18 - 0.07 * i, -0.128), M["bone"],
					Vector3(0, 0, 0.12 * (i - 0.5))) # exposed ribs
			_box(_body, Vector3(0.13, 0.11, 0.02),
				Vector3(-0.05, 1.06, -0.128), M["blood"]) # bite wound
			# Blood streak down the shirt.
			_box(_body, Vector3(0.07, 0.22, 0.02),
				Vector3(0.08, 1.02, -0.125), M["blood"])
		1:
			# Neck gash + clawed shoulder.
			_box(_body, Vector3(0.16, 0.07, 0.03),
				Vector3(0.04, 1.36, -0.10), M["wound"],
				Vector3(0, 0, 0.35)) # throat tear
			_box(_body, Vector3(0.10, 0.05, 0.02),
				Vector3(0.10, 1.32, -0.115), M["blood"],
				Vector3(0, 0, -0.2))
			for i in 3: # claw marks across the shoulder
				_box(_body, Vector3(0.16, 0.022, 0.015),
					Vector3(-0.12, 1.30 - 0.045 * i, -0.105), M["wound"],
					Vector3(0, 0, 0.5))
		_:
			# Gut wound low on the torso, blood-soaked hem.
			_box(_body, Vector3(0.18, 0.16, 0.03),
				Vector3(0.03, 0.98, -0.115), M["wound"]) # torn belly
			_box(_body, Vector3(0.10, 0.08, 0.035),
				Vector3(0.03, 0.98, -0.11), M["blood"])
			_box(_body, Vector3(0.20, 0.10, 0.02),
				Vector3(-0.02, 0.90, -0.12), M["blood"]) # soaked hem
	# Hanging cloth strips off the ripped hem — they sway with the shamble
	# via the body's rotation (rigid, cheap, reads as motion).
	for i in 2:
		var sx := -0.06 + 0.12 * i
		_box(_body, Vector3(0.055, 0.14, 0.015),
			Vector3(sx, 0.86, -0.12), shirt,
			Vector3(0, 0, 0.14 * (1 if i % 2 == 0 else -1)))
	# Shoulder pad of bunched torn cloth (left; the right sleeve is
	# already ragged).
	_box(_body, Vector3(0.16, 0.10, 0.18), Vector3(-0.25, 1.36, 0),
		M["shirt_dark"], Vector3(0, 0, 0.25))


func _build_arms(M: Dictionary, shirt: Material, skin: Material,
		stump: bool) -> void:
	# Dangle forward-down; one forearm stripped to the bone, torn sleeves.
	# Some lose the right forearm entirely (bloody stump).
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.26 * side, 1.34, 0.0)
		arm.rotation.x = -0.65
		_body.add_child(arm)
		_frustum(arm, Vector2(0.15, 0.16), Vector2(0.11, 0.13), 0.28,
			Vector3(0, -0.14, 0), shirt) # sleeve
		# Torn sleeve strips.
		_box(arm, Vector3(0.04, 0.12, 0.015), Vector3(0.06 * side, -0.30, -0.06),
			shirt, Vector3(0.4, 0, 0.5 * side))
		if side < 0.0:
			# Left: bare forearm with a wound, claw hand.
			_frustum(arm, Vector2(0.11, 0.12), Vector2(0.08, 0.09), 0.24,
				Vector3(0, -0.38, 0), skin)
			_box(arm, Vector3(0.10, 0.09, 0.02), Vector3(0, -0.36, -0.06),
				M["wound"])
			_frustum(arm, Vector2(0.09, 0.10), Vector2(0.06, 0.11), 0.10,
				Vector3(0, -0.54, -0.01), M["skin_dark"]) # claw hand
			_arm_l = arm
		elif stump:
			# Right forearm lost: ragged stump, blood-capped.
			_frustum(arm, Vector2(0.11, 0.12), Vector2(0.09, 0.10), 0.12,
				Vector3(0, -0.32, 0), skin)
			_box(arm, Vector3(0.10, 0.07, 0.10), Vector3(0, -0.40, 0),
				M["blood"]) # stump cap
			_box(arm, Vector3(0.03, 0.06, 0.03), Vector3(0.02, -0.38, 0),
				M["bone"], Vector3(0.2, 0, 0)) # bone shard
			_arm_r = arm
		else:
			# Right: flesh torn away — radius + ulna, one dangling finger bone.
			_box(arm, Vector3(0.04, 0.22, 0.04), Vector3(0.02, -0.38, 0),
				M["bone"], Vector3(0.08, 0, 0.04))
			_box(arm, Vector3(0.035, 0.20, 0.035), Vector3(-0.03, -0.38, 0.01),
				M["bone"], Vector3(-0.06, 0, -0.05))
			_box(arm, Vector3(0.09, 0.08, 0.10), Vector3(0, -0.28, 0),
				M["wound"]) # flesh remnant at elbow
			_box(arm, Vector3(0.022, 0.07, 0.022), Vector3(0, -0.53, -0.01),
				M["bone"], Vector3(0.3, 0, 0)) # finger bone
			_arm_r = arm


func _build_head(M: Dictionary, skin: Material, hair_v: int) -> void:
	# Defined skull: tapered cranium (wide brow, narrow jaw), brow ridge,
	# cheek planes, sunken sockets, exposed teeth under the mouth gash.
	# Skin tone varies per instance; hair: 0 matted, 1 patchy, 2 bald.
	_head = Node3D.new()
	_head.position = Vector3(0, 1.50, -0.10)
	_head.rotation.x = 0.18
	_body.add_child(_head)
	_frustum(_head, Vector2(0.24, 0.25), Vector2(0.17, 0.19), 0.26,
		Vector3(0, 0.01, 0), skin) # tapered skull
	# Brow ridge + sunken eye sockets.
	_box(_head, Vector3(0.20, 0.045, 0.05), Vector3(0, 0.055, -0.105),
		M["skin_dark"], Vector3(-0.15, 0, 0))
	for side in [-1.0, 1.0]:
		_box(_head, Vector3(0.075, 0.07, 0.03),
			Vector3(0.058 * side, 0.005, -0.10), M["skin_dark"]) # socket
		_box(_head, Vector3(0.05, 0.045, 0.02),
			Vector3(0.058 * side, 0.005, -0.115), M["eye"])
		# Cheek planes: angled slabs under the sockets.
		_box(_head, Vector3(0.07, 0.05, 0.04),
			Vector3(0.085 * side, -0.055, -0.075), skin,
			Vector3(0.3, 0.35 * side, 0))
	# Nose: broken wedge, one nostril dark.
	_frustum(_head, Vector2(0.035, 0.02), Vector2(0.05, 0.06), 0.09,
		Vector3(0.01, -0.03, -0.115), M["skin_dark"],
		Vector3(0.2, 0, 0.1))
	# Mouth gash with exposed teeth; slack jaw below.
	_box(_head, Vector3(0.17, 0.05, 0.03), Vector3(0, -0.095, -0.10), M["wound"])
	_box(_head, Vector3(0.13, 0.028, 0.015), Vector3(0, -0.088, -0.112),
		M["bone"]) # teeth
	_frustum(_head, Vector2(0.15, 0.16), Vector2(0.12, 0.13), 0.09,
		Vector3(0, -0.155, -0.01), M["skin_dark"]) # slack jaw
	# Head wound with bone showing.
	_box(_head, Vector3(0.12, 0.10, 0.03), Vector3(0.07, 0.10, 0.02),
		M["wound"], Vector3(0, 0, 0.4))
	_box(_head, Vector3(0.06, 0.05, 0.035), Vector3(0.07, 0.10, 0.015),
		M["bone"], Vector3(0, 0, 0.4)) # cracked skull
	if hair_v == 0:
		# Matted hair: top cap, back mass, one clump over the forehead.
		_frustum(_head, Vector2(0.25, 0.26), Vector2(0.26, 0.27), 0.10,
			Vector3(0, 0.165, 0.01), M["hair"])
		_box(_head, Vector3(0.24, 0.18, 0.10), Vector3(0, 0.07, 0.13), M["hair"])
		_box(_head, Vector3(0.06, 0.10, 0.05), Vector3(-0.05, 0.14, -0.09),
			M["hair"], Vector3(-0.3, 0, 0.2)) # clump over forehead
	elif hair_v == 1:
		# Patchy: thin cap + one side clump, scalp showing through.
		_frustum(_head, Vector2(0.24, 0.25), Vector2(0.25, 0.26), 0.06,
			Vector3(0, 0.16, 0.01), M["hair"])
		_box(_head, Vector3(0.08, 0.12, 0.06), Vector3(0.09, 0.10, 0.05),
			M["hair"], Vector3(0, 0, -0.3))
	else:
		# Bald: bare scalp with a cracked plate.
		_box(_head, Vector3(0.10, 0.04, 0.08), Vector3(-0.04, 0.15, 0.0),
			M["wound"], Vector3(0, 0, 0.2))
