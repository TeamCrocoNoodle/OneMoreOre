extends Node3D
## A depth-tested light pulse leaking from a damaged gem's last stone cover.
## All geometry stays in the owning plate's space, including during recoil.

signal pulse_finished

const LIGHT_SHADER := preload("res://shaders/gem_light.gdshader")
const TIER_COLORS: Array[Color] = [
	Color("f3faff"), Color("64ff86"), Color("4896ff"),
	Color("ffe15b"), Color("be65ff"), Color("ff4c61")
]

var current_tier: int = -1
var pulse_count: int = 0

var _face_points := PackedVector3Array()
var _center := Vector3.ZERO
var _normal := Vector3.FORWARD
var _tangent := Vector3.RIGHT
var _bitangent := Vector3.UP
var _rng := RandomNumberGenerator.new()
var _crack_segments: Array[Dictionary] = []
var _rays: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _beam_mesh: MeshInstance3D
var _crack_mesh: MeshInstance3D
var _dust_mesh: MeshInstance3D
var _beam_material: ShaderMaterial
var _crack_material: ShaderMaterial
var _dust_material: ShaderMaterial
var _elapsed := 0.0
var _duration := 0.8
var _damage := 0.0
var _broken := false
var _configured := false


func configure(face_points: PackedVector3Array, face_center: Vector3, normal: Vector3, seed_value: int) -> void:
	_ensure_meshes()
	clear()
	_face_points = face_points.duplicate()
	_center = face_center
	_normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	_tangent = _normal.cross(Vector3.UP).normalized()
	if _tangent.length_squared() < 0.1:
		_tangent = _normal.cross(Vector3.RIGHT).normalized()
	_bitangent = _normal.cross(_tangent).normalized()
	_rng.seed = seed_value
	_build_paths()
	_configured = true


func pulse(tier: int, damage_ratio: float, broken: bool = false) -> void:
	if not _configured:
		return
	current_tier = clampi(tier, 0, 5)
	pulse_count += 1
	_damage = clampf(damage_ratio, 0.0, 1.0)
	_broken = broken
	_elapsed = 0.0
	_duration = 1.05 if broken else 0.80
	for material in [_beam_material, _crack_material, _dust_material]:
		material.set_shader_parameter("light_color", TIER_COLORS[current_tier])
	_draw_cracks()
	visible = true
	_beam_mesh.visible = true
	_crack_mesh.visible = true
	_dust_mesh.visible = true
	_update_visuals()
	set_process(true)


func clear() -> void:
	current_tier = -1
	pulse_count = 0
	_elapsed = 0.0
	_damage = 0.0
	_broken = false
	visible = false
	set_process(false)
	if is_instance_valid(_beam_material):
		for material in [_beam_material, _crack_material, _dust_material]:
			material.set_shader_parameter("pulse_amount", 0.0)


func _ready() -> void:
	_ensure_meshes()
	if current_tier < 0:
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	_update_visuals()
	if _elapsed >= _duration:
		_beam_mesh.visible = false
		_dust_mesh.visible = false
		_crack_mesh.visible = not _broken
		_crack_material.set_shader_parameter("pulse_amount", 0.0 if _broken else 0.045 + _damage * 0.08)
		set_process(false)
		pulse_finished.emit()


func _ensure_meshes() -> void:
	if is_instance_valid(_beam_mesh):
		return
	_beam_material = _make_material(0)
	_crack_material = _make_material(1)
	_dust_material = _make_material(2)
	_beam_mesh = _make_mesh("LightShafts", _beam_material)
	_crack_mesh = _make_mesh("LitFissures", _crack_material)
	_dust_mesh = _make_mesh("CrystalMotes", _dust_material)


func _make_material(kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LIGHT_SHADER
	material.set_shader_parameter("effect_kind", kind)
	return material


func _make_mesh(mesh_name: String, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _build_paths() -> void:
	_crack_segments.clear()
	_rays.clear()
	_dust.clear()
	if _face_points.size() < 3:
		return
	var branch_count := mini(5, _face_points.size())
	for branch in range(branch_count):
		var edge_index := int(float(branch) / float(branch_count) * float(_face_points.size()))
		var edge_point := _face_points[edge_index].lerp(_face_points[(edge_index + 1) % _face_points.size()], _rng.randf_range(0.22, 0.72))
		var travel := edge_point - _center
		var outward := travel.normalized()
		var sideways := _normal.cross(outward).normalized()
		var start := _center + travel * _rng.randf_range(0.04, 0.13)
		var previous := start
		for step in range(4):
			var progress := float(step + 1) / 4.0
			var point := start.lerp(edge_point, progress)
			if step < 3:
				point += sideways * _rng.randf_range(-0.045, 0.045)
			_crack_segments.append({"a": previous, "b": point, "progress": float(step) / 4.0, "branch": branch})
			if step == 1 or step == 3:
				var origin := previous.lerp(point, _rng.randf_range(0.38, 0.76)) + _normal * 0.018
				var fan := _rng.randf_range(0.85, 1.35)
				var ray_direction := (_normal + outward * fan + sideways * _rng.randf_range(-0.26, 0.26)).normalized()
				_rays.append({"origin": origin, "direction": ray_direction, "length": _rng.randf_range(2.35, 2.95), "width": _rng.randf_range(0.24, 0.39), "weight": _rng.randf_range(0.80, 1.0), "branch": branch})
			previous = point
		# A short section of the seam also glows, so the rays have an obvious source.
		var seam_a := _face_points[edge_index].lerp(edge_point, 0.70)
		var seam_b := edge_point.lerp(_face_points[(edge_index + 1) % _face_points.size()], 0.36)
		_crack_segments.append({"a": seam_a, "b": seam_b, "progress": 0.70, "branch": branch})
	for i in range(12):
		_dust.append({"ray": i % maxi(_rays.size(), 1), "phase": _rng.randf_range(0.0, 0.65), "size": _rng.randf_range(0.022, 0.048), "offset": Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08))})


func _update_visuals() -> void:
	var progress := clampf(_elapsed / _duration, 0.0, 1.0)
	var attack := lerpf(0.52, 1.0, smoothstep(0.0, 0.055, _elapsed))
	var tail := pow(1.0 - smoothstep(0.08, 1.0, progress), 1.30)
	var energy := attack * tail * (1.0 + _damage * 0.30 + (0.28 if _broken else 0.0))
	_beam_material.set_shader_parameter("pulse_amount", energy)
	_dust_material.set_shader_parameter("pulse_amount", energy)
	_crack_material.set_shader_parameter("pulse_amount", energy * 1.10 + (0.045 + _damage * 0.08) * tail)
	_beam_material.set_shader_parameter("age", _elapsed)
	_draw_beams(progress)
	_draw_dust(progress)


func _draw_cracks() -> void:
	if _crack_segments.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var growth := clampf(0.44 + _damage * 0.68, 0.0, 1.0)
	var width := lerpf(0.014, 0.040, _damage)
	for segment in _crack_segments:
		var start: float = segment.progress
		if start >= growth:
			continue
		var a: Vector3 = segment.a + _normal * 0.012
		var b: Vector3 = segment.b + _normal * 0.012
		b = a.lerp(b, clampf((growth - start) * 4.0, 0.0, 1.0))
		var side := _normal.cross(b - a).normalized() * width * (1.0 - start * 0.35)
		_add_quad(surface, a - side, a + side, b - side * 0.72, b + side * 0.72, 1.0)
	_crack_mesh.mesh = surface.commit()


func _view_basis() -> Basis:
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if is_instance_valid(camera):
			return global_basis.inverse() * camera.global_basis
	return Basis(_tangent, _bitangent, _normal)


func _draw_beams(progress: float) -> void:
	if _rays.is_empty():
		return
	var camera_basis := _view_basis()
	var toward_camera := camera_basis.z.normalized()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var extension := lerpf(0.76, 1.0, smoothstep(0.0, 0.14, _elapsed))
	for ray in _rays:
		var origin: Vector3 = ray.origin
		var direction: Vector3 = ray.direction
		var length := float(ray.length) * lerpf(0.95, 1.07, _damage) * extension
		var width := float(ray.width) * lerpf(0.82, 1.35, _damage)
		var side := direction.cross(toward_camera).normalized()
		if side.length_squared() < 0.1:
			side = camera_basis.x.normalized()
		var tip := origin + direction * length
		var base_width := lerpf(0.015, 0.034, _damage)
		_add_quad(surface, origin - side * base_width, origin + side * base_width, tip - side * width, tip + side * width, float(ray.weight))
		# A narrow crossed sheet adds volume when the plate is seen obliquely.
		var crossed := direction.cross(side).normalized()
		_add_quad(surface, origin - crossed * base_width, origin + crossed * base_width, tip - crossed * width * 0.54, tip + crossed * width * 0.54, float(ray.weight) * 0.30)
	_beam_mesh.mesh = surface.commit()


func _draw_dust(progress: float) -> void:
	if _rays.is_empty():
		return
	var camera_basis := _view_basis()
	var right := camera_basis.x.normalized()
	var up := camera_basis.y.normalized()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mote in _dust:
		var ray: Dictionary = _rays[int(mote.ray)]
		var travel := float(mote.phase) + progress * 0.56
		if travel >= 1.0:
			continue
		var origin: Vector3 = ray.origin
		var direction: Vector3 = ray.direction
		var offset: Vector2 = mote.offset
		var center := origin + direction * travel * float(ray.length) + right * offset.x + up * offset.y
		var size := float(mote.size) * (0.70 + _damage * 0.48) * sin(travel * PI)
		_add_quad(surface, center - right * size - up * size, center + right * size - up * size, center - right * size + up * size, center + right * size + up * size, 1.0 - travel * 0.6)
	_dust_mesh.mesh = surface.commit()


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, alpha: float) -> void:
	var vertices := PackedVector3Array([a, b, d, a, d, c])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	for i in range(6):
		surface.set_color(Color(1.0, 1.0, 1.0, alpha))
		surface.set_uv(uvs[i])
		surface.add_vertex(vertices[i])
