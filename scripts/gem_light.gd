extends Node3D
## A depth-tested light pulse leaking from a damaged gem's last stone cover.
## All geometry stays in the owning plate's space, including during recoil.

signal pulse_finished

const LIGHT_SHADER := preload("res://shaders/gem_light.gdshader")
const CRACK_OFFSET := 0.012
const RAY_OFFSET := 0.018
const CRACK_CORE_RATIO := 0.78
const MAX_RAYS := 10
const TIER_COLORS: Array[Color] = [
	Color("f3faff"), Color("64ff86"), Color("4896ff"),
	Color("ffe15b"), Color("be65ff"), Color("ff4c61")
]

var current_tier: int = -1
var pulse_count: int = 0

var _normal := Vector3.FORWARD
var _tangent := Vector3.RIGHT
var _bitangent := Vector3.UP
var _rng := RandomNumberGenerator.new()
var _seed_value := 0
var _latest_impact := Vector3.ZERO
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


@warning_ignore("unused_parameter")
func configure(face_points: PackedVector3Array, face_center: Vector3, normal: Vector3, seed_value: int) -> void:
	_ensure_meshes()
	clear()
	_normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	_tangent = _normal.cross(Vector3.UP).normalized()
	if _tangent.length_squared() < 0.1:
		_tangent = _normal.cross(Vector3.RIGHT).normalized()
	_bitangent = _normal.cross(_tangent).normalized()
	_seed_value = seed_value
	_rng.seed = seed_value
	_configured = true


func set_cracks(segments: Array[Dictionary], latest_impact: Vector3) -> void:
	# Stone owns the fracture geometry. This module only illuminates its current
	# visible centerlines; it never invents another crack or perimeter seam.
	_crack_segments.clear()
	_rays.clear()
	_dust.clear()
	_latest_impact = latest_impact
	for source_index in range(segments.size()):
		var source := segments[source_index]
		if not (source.get("a") is Vector3) or not (source.get("b") is Vector3):
			continue
		var a: Vector3 = source.a
		var b: Vector3 = source.b
		var width := maxf(float(source.get("width", 0.0)), 0.0)
		if a.distance_squared_to(b) <= 0.00000001 or width <= 0.0:
			continue
		var segment := source.duplicate(true)
		segment["source_index"] = source_index
		segment["width"] = width
		segment["weight"] = clampf(float(source.get("weight", 1.0)), 0.0, 1.0)
		segment["hit_id"] = int(source.get("hit_id", 0))
		segment["impact"] = source.get("impact", latest_impact)
		_crack_segments.append(segment)
	_build_rays()
	if is_instance_valid(_beam_mesh):
		_beam_mesh.mesh = null
		_crack_mesh.mesh = null
		_dust_mesh.mesh = null


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
	visible = not _crack_segments.is_empty()
	_beam_mesh.visible = not _rays.is_empty()
	_crack_mesh.visible = not _crack_segments.is_empty()
	_dust_mesh.visible = not _dust.is_empty()
	_update_visuals()
	set_process(true)


func clear() -> void:
	current_tier = -1
	pulse_count = 0
	_elapsed = 0.0
	_damage = 0.0
	_broken = false
	_latest_impact = Vector3.ZERO
	_crack_segments.clear()
	_rays.clear()
	_dust.clear()
	visible = false
	set_process(false)
	if is_instance_valid(_beam_material):
		for material in [_beam_material, _crack_material, _dust_material]:
			material.set_shader_parameter("pulse_amount", 0.0)
		_beam_mesh.mesh = null
		_crack_mesh.mesh = null
		_dust_mesh.mesh = null


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


func _build_rays() -> void:
	if _crack_segments.is_empty():
		return
	var nearest_impact := INF
	for segment in _crack_segments:
		var impact: Vector3 = segment.impact
		nearest_impact = minf(nearest_impact, impact.distance_to(_latest_impact))
	var fresh_indices: Array[int] = []
	var older_indices: Array[int] = []
	var fresh_hit_id := 0
	for i in range(_crack_segments.size()):
		var impact: Vector3 = _crack_segments[i].impact
		# A repeated strike can extend an older site without changing its hit ID.
		var fresh := impact.distance_to(_latest_impact) <= nearest_impact + 0.025
		_crack_segments[i]["fresh"] = fresh
		if fresh:
			fresh_indices.append(i)
			fresh_hit_id = maxi(fresh_hit_id, int(_crack_segments[i].hit_id))
		else:
			older_indices.append(i)
	_rng.seed = _seed_value + fresh_hit_id * 104729
	var ray_count := mini(MAX_RAYS, _crack_segments.size())
	var fresh_count := mini(fresh_indices.size(), maxi(int(ceil(float(ray_count) * 0.7)), ray_count - older_indices.size()))
	var chosen := _spaced_indices(fresh_indices, fresh_count)
	chosen.append_array(_spaced_indices(older_indices, ray_count - fresh_count))
	for selected in chosen:
		var segment := _crack_segments[selected]
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var impact: Vector3 = segment.impact
		var source_t := _rng.randf_range(0.24, 0.78)
		var source_point := a.lerp(b, source_t)
		var tangent := (b - a).normalized()
		var outward := source_point - impact
		outward -= _normal * outward.dot(_normal)
		outward = outward.normalized() if outward.length_squared() > 0.0000001 else tangent
		if tangent.dot(outward) < 0.0:
			tangent = -tangent
		var planar := (tangent * 0.72 + outward * 0.28).normalized()
		var fan := _rng.randf_range(0.85, 1.35)
		var ray_direction := (_normal + planar * fan).normalized()
		_rays.append({
			"origin": source_point + _normal * RAY_OFFSET,
			"direction": ray_direction,
			"length": _rng.randf_range(2.35, 2.95),
			"width": _rng.randf_range(0.24, 0.39),
			"weight": _rng.randf_range(0.88, 1.0) if bool(segment.fresh) else _rng.randf_range(0.45, 0.62),
			"source_index": int(segment.source_index),
			"source_hit_id": int(segment.hit_id),
			"source_a": a,
			"source_b": b,
			"source_impact": impact,
			"source_t": source_t,
			"tangent": tangent,
			"outward": outward,
			"fan_strength": fan,
			"fresh": bool(segment.fresh)
		})
	for i in range(12):
		_dust.append({"ray": i % maxi(_rays.size(), 1), "phase": _rng.randf_range(0.0, 0.65), "size": _rng.randf_range(0.022, 0.048), "offset": Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08))})


func _spaced_indices(candidates: Array[int], count: int) -> Array[int]:
	var chosen: Array[int] = []
	for i in range(mini(count, candidates.size())):
		chosen.append(candidates[int((float(i) + 0.5) * float(candidates.size()) / float(count))])
	return chosen


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
		_crack_mesh.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in _crack_segments:
		var a: Vector3 = segment.a + _normal * CRACK_OFFSET
		var b: Vector3 = segment.b + _normal * CRACK_OFFSET
		# Width is the stone renderer's complete visible half-width, including
		# weight and growth. Applying either again would misalign the two ribbons.
		var side := _normal.cross(b - a).normalized() * float(segment.width) * CRACK_CORE_RATIO
		var intensity := 1.0 if bool(segment.fresh) else 0.65
		_add_quad(surface, a - side, a + side, b - side, b + side, intensity)
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
