class_name TitleBackdrop
extends Node3D
## Apocalyptic title-screen diorama: burning skyline silhouette, ruined
## street, drifting smoke, rising embers, flickering firelight. All
## procedural, ~60 cheap nodes, one light, one CPU particle system —
## phone-safe. Lives only on the title screen (freed by the scene reload
## on new game). Composition is centered so it reads in portrait and
## landscape.

var _t := 0.0
var _smoke: Array = []
var _glows: Array = []
var _flicker: OmniLight3D
var _cam: Camera3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1337
	_build_camera()
	_build_sky()
	_build_skyline(-72.0, 12, 12.0, 30.0, Color(0.05, 0.05, 0.08))
	_build_skyline(-48.0, 8, 8.0, 20.0, Color(0.03, 0.03, 0.05))
	_build_fire_glows()
	_build_street()
	_build_wreck()
	_build_rubble()
	_build_dead_light()
	_build_smoke()
	_build_embers()
	_build_flicker_light()


func _process(delta: float) -> void:
	_t += delta
	# Slow cinematic drift so the title feels alive.
	_cam.position.x = sin(_t * 0.11) * 1.6
	_cam.rotation.y = sin(_t * 0.11) * 0.035
	for s in _smoke:
		var p := s as MeshInstance3D
		p.position.x += delta * float(p.get_meta("drift"))
		p.position.y += delta * 0.35
		if p.position.y > 26.0:
			p.position.y = 2.0
			p.position.x = _rng.randf_range(-45.0, 45.0)
	var f := 0.75 + 0.25 * sin(_t * 9.0) * sin(_t * 3.7)
	for g in _glows:
		(g as MeshInstance3D).scale = Vector3.ONE * f
	if _flicker != null:
		_flicker.light_energy = 1.6 + 0.9 * sin(_t * 11.0) * sin(_t * 4.3)


func _mat(c: Color, emission := false, e_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = e_energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 5.0, 26.0)
	_cam.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	_cam.fov = 55.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true


func _build_sky() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = _sky_shader()
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 160)
	q.mesh = pm
	q.material_override = sm
	q.position = Vector3(0, 40, -110)
	add_child(q)


func _sky_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	vec3 horizon = vec3(0.95, 0.38, 0.12);
	vec3 mid = vec3(0.30, 0.10, 0.06);
	vec3 top = vec3(0.02, 0.025, 0.05);
	vec3 c = mix(horizon, mid, smoothstep(0.02, 0.42, h));
	c = mix(c, top, smoothstep(0.35, 0.95, h));
	ALBEDO = c;
}
"""
	return sh


func _build_skyline(z: float, count: int, h_min: float, h_max: float, c: Color) -> void:
	var layer := Node3D.new()
	layer.position.z = z
	add_child(layer)
	var m := _mat(c)
	var x := -58.0
	for i in count:
		var w := _rng.randf_range(6.0, 11.0)
		var h := _rng.randf_range(h_min, h_max)
		_box(layer, Vector3(w, h, 6.0), Vector3(x + w * 0.5, h * 0.5 - 2.0, 0), m)
		# Broken top: a smaller offset block reads as a ruined crown.
		if _rng.randf() < 0.6:
			_box(layer, Vector3(w * 0.45, _rng.randf_range(1.5, 4.0), 6.2),
				Vector3(x + w * _rng.randf_range(0.2, 0.6), h - 2.0 + 1.0, 0), m,
				_rng.randf_range(-0.15, 0.15))
		# A few lit windows burning in the dark.
		if _rng.randf() < 0.5:
			var wm := _mat(Color(1.0, 0.45, 0.12), true, 2.0)
			for k in _rng.randi_range(1, 3):
				_box(layer, Vector3(0.9, 1.2, 0.3),
					Vector3(x + _rng.randf_range(1.0, w - 1.0),
						_rng.randf_range(2.0, h - 3.0), 3.1), wm)
		x += w + _rng.randf_range(1.5, 4.0)


func _build_fire_glows() -> void:
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_color = Color(1.0, 0.42, 0.10, 0.55)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.40, 0.10)
	gm.emission_energy_multiplier = 1.6
	for gx in [-28.0, 4.0, 30.0]:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(_rng.randf_range(22.0, 34.0), _rng.randf_range(10.0, 16.0))
		q.mesh = pm
		q.material_override = gm
		q.position = Vector3(gx, _rng.randf_range(2.0, 5.0), -60.0)
		add_child(q)
		_glows.append(q)


func _build_street() -> void:
	var m := _mat(Color(0.07, 0.07, 0.08))
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 70)
	g.mesh = pm
	g.material_override = m
	g.position = Vector3(0, 0, -5)
	add_child(g)
	# Faint center line, broken.
	var lm := _mat(Color(0.35, 0.30, 0.18))
	for i in 5:
		_box(self, Vector3(2.2, 0.02, 0.35), Vector3(-14.0 + i * 7.0, 0.02, 2.0), lm)


func _build_wreck() -> void:
	var car := Node3D.new()
	car.position = Vector3(9.0, 0, -8.0)
	car.rotation.y = 0.5
	car.rotation.z = 0.06
	add_child(car)
	var dark := _mat(Color(0.10, 0.08, 0.08))
	var rust := _mat(Color(0.30, 0.16, 0.08))
	_box(car, Vector3(4.4, 1.0, 2.0), Vector3(0, 0.75, 0), rust)
	_box(car, Vector3(2.2, 0.8, 1.8), Vector3(-0.2, 1.6, 0), dark)
	for wx in [-1.5, 1.5]:
		for wz in [-1.0, 1.0]:
			_box(car, Vector3(0.7, 0.7, 0.4), Vector3(wx, 0.35, wz), dark)


func _build_rubble() -> void:
	var m := _mat(Color(0.09, 0.085, 0.09))
	for i in 9:
		var s := _rng.randf_range(0.5, 1.6)
		_box(self, Vector3(s, s * 0.7, s),
			Vector3(_rng.randf_range(-22.0, 22.0), s * 0.3, _rng.randf_range(-20.0, 6.0)),
			m, _rng.randf_range(0.0, PI))


func _build_dead_light() -> void:
	var pole := Node3D.new()
	pole.position = Vector3(-11.0, 0, -12.0)
	pole.rotation.z = 0.22
	add_child(pole)
	var m := _mat(Color(0.08, 0.08, 0.09))
	_box(pole, Vector3(0.35, 9.0, 0.35), Vector3(0, 4.5, 0), m)
	_box(pole, Vector3(2.4, 0.3, 0.3), Vector3(1.1, 8.9, 0), m)


func _smoke_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (x - 32.0) / 32.0
			var dy := (y - 32.0) / 32.0
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.16, 0.14, 0.14, a * a * 0.55))
	return ImageTexture.create_from_image(img)


func _build_smoke() -> void:
	var tex := _smoke_texture()
	for i in 7:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_texture = tex
		sm.albedo_color = Color(1, 1, 1, 1)
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var sz := _rng.randf_range(14.0, 26.0)
		pm.size = Vector2(sz, sz * 0.7)
		q.mesh = pm
		q.material_override = sm
		q.position = Vector3(_rng.randf_range(-45.0, 45.0),
			_rng.randf_range(2.0, 24.0), _rng.randf_range(-55.0, -15.0))
		q.set_meta("drift", _rng.randf_range(-0.8, 0.8))
		add_child(q)
		_smoke.append(q)


func _build_embers() -> void:
	var p := CPUParticles3D.new()
	p.amount = 42
	p.lifetime = 3.2
	p.preprocess = 3.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30, 1, 10)
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	p.color = Color(1.0, 0.5, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.10)
	m.emission_energy_multiplier = 2.5
	m.albedo_color = Color(1.0, 0.5, 0.12)
	p.material_override = m
	p.position = Vector3(0, 1.0, -30.0)
	add_child(p)


func _build_flicker_light() -> void:
	_flicker = OmniLight3D.new()
	_flicker.light_color = Color(1.0, 0.45, 0.15)
	_flicker.light_energy = 1.8
	_flicker.omni_range = 30.0
	_flicker.position = Vector3(0, 4.0, -18.0)
	add_child(_flicker)
