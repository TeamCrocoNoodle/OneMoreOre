extends Node3D
## A depth-tested light pulse leaking from a damaged gem's last stone cover.
## All geometry stays in the owning plate's space, including during recoil.

signal pulse_finished

const LIGHT_SHADER := preload("res://shaders/gem_light.gdshader")
const BEAM_SHADER := preload("res://shaders/gem_beam.gdshader")
const CRACK_OFFSET := 0.012
const GLOW_OFFSET := 0.010
const RAY_OFFSET := 0.018
const CRACK_CORE_RATIO := 0.42
const CRACK_GLOW_RATIO := 1.7
const SHEET_OPACITY := 0.26
const TIER_COLORS: Array[Color] = [
	Color("f3faff"), Color("64ff86"), Color("4896ff"),
	Color("ffe15b"), Color("be65ff"), Color("ff4c61"), Color("f1ddff")
]

var current_tier: int = -1
var pulse_count: int = 0

var _normal := Vector3.FORWARD
var _tangent := Vector3.RIGHT
var _bitangent := Vector3.UP
var _rng := RandomNumberGenerator.new()
var _seed_value := 0
var _latest_impact := Vector3.ZERO
var _emitter_position := Vector3.ZERO
var _projection_scale := 6.0
var _crack_segments: Array[Dictionary] = []
var _rays: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _beam_mesh: MeshInstance3D
var _crack_mesh: MeshInstance3D
var _dust_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _source_mesh: MeshInstance3D
var _beam_material: ShaderMaterial
var _crack_material: ShaderMaterial
var _dust_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _source_material: ShaderMaterial
var _elapsed := 0.0
var _duration := 0.9
var _damage := 0.0
var _broken := false
var _configured := false
var _surface_geometry: RefCounted


func configure(face_points: PackedVector3Array, face_center: Vector3, normal: Vector3, seed_value: int, source_position: Vector3 = Vector3.INF, solid_surface: bool = false, surface_geometry: RefCounted = null) -> void:
	_ensure_meshes()
	clear()
	_surface_geometry = surface_geometry
	_normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	_tangent = _normal.cross(Vector3.UP).normalized()
	if _tangent.length_squared() < 0.1:
		_tangent = _normal.cross(Vector3.RIGHT).normalized()
	_bitangent = _normal.cross(_tangent).normalized()
	var extent := 0.0
	for point in face_points:
		extent += point.distance_to(face_center)
	extent = maxf(extent / maxf(float(face_points.size()), 1.0), 0.35)
	_emitter_position = source_position if source_position != Vector3.INF else face_center - _normal * extent * 0.7
	# Keep the gem's lateral placement, but give very shallow sockets enough
	# optical depth that tiny cracks cannot project into enormous triangles.
	var depth := _normal.dot(face_center - _emitter_position)
	var minimum_depth := maxf(extent * 0.60, 0.24)
	if not solid_surface and depth < minimum_depth:
		_emitter_position -= _normal * (minimum_depth - depth)
		depth = minimum_depth
	_projection_scale = 1.0 + clampf(extent * 3.5, 1.8, 3.1) / (depth + RAY_OFFSET)
	if solid_surface:
		# The socket is inside every face. Keep that common source inside the
		# solid: a front-only optical-depth correction could cross its rear wall.
		_projection_scale = clampf(_projection_scale, 2.8, 5.5)
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
		_glow_mesh.mesh = null
		_source_mesh.mesh = null


func pulse(tier: int, damage_ratio: float, broken: bool = false) -> void:
	if not _configured:
		return
	current_tier = clampi(tier, 0, TIER_COLORS.size()-1)
	pulse_count += 1
	_damage = clampf(damage_ratio, 0.0, 1.0)
	_broken = broken
	_elapsed = 0.0
	_duration = 1.10 if broken else 0.90
	for material in [_beam_material, _crack_material, _dust_material, _glow_material, _source_material]:
		material.set_shader_parameter("light_color", TIER_COLORS[current_tier])
		material.set_shader_parameter("prismatic", current_tier == 6)
	if broken:
		# Destruction keeps the final hit's tier/provenance but never uploads
		# geometry that the owning stone will immediately hide and free.
		visible = false
		set_process(false)
		for material in [_beam_material, _crack_material, _dust_material, _glow_material, _source_material]:
			material.set_shader_parameter("pulse_amount", 0.0)
		return
	_draw_cracks()
	_draw_beams()
	_draw_dust()
	visible = not _crack_segments.is_empty()
	_beam_mesh.visible = not _rays.is_empty()
	_crack_mesh.visible = not _crack_segments.is_empty()
	_dust_mesh.visible = not _dust.is_empty()
	_glow_mesh.visible = not _crack_segments.is_empty()
	_source_mesh.visible = not _rays.is_empty()
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
		for material in [_beam_material, _crack_material, _dust_material, _glow_material, _source_material]:
			material.set_shader_parameter("pulse_amount", 0.0)
		_beam_mesh.mesh = null
		_crack_mesh.mesh = null
		_dust_mesh.mesh = null
		_glow_mesh.mesh = null
		_source_mesh.mesh = null


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
		_crack_mesh.visible = false
		_glow_mesh.visible = false
		_source_mesh.visible = false
		visible = false
		set_process(false)
		pulse_finished.emit()


func _ensure_meshes() -> void:
	if is_instance_valid(_beam_mesh):
		return
	_beam_material = _make_material(0)
	_crack_material = _make_material(1)
	_dust_material = _make_material(2)
	_glow_material = _make_material(3)
	_source_material = _make_material(4)
	_beam_mesh = _make_mesh("LightShafts", _beam_material)
	_crack_mesh = _make_mesh("LitFissures", _crack_material)
	_dust_mesh = _make_mesh("CrystalMotes", _dust_material)
	_glow_mesh = _make_mesh("FissureGlow", _glow_material)
	_source_mesh = _make_mesh("LightSources", _source_material)


func _make_material(kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER if kind == 0 else LIGHT_SHADER
	material.render_priority = 0 if kind == 0 else 1
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
	var fresh_hit_id := 0
	for i in range(_crack_segments.size()):
		var impact: Vector3 = _crack_segments[i].impact
		# A repeated strike can extend an older site without changing its hit ID.
		var fresh := impact.distance_to(_latest_impact) <= nearest_impact + 0.025
		_crack_segments[i]["fresh"] = fresh
		if fresh:
			fresh_hit_id = maxi(fresh_hit_id, int(_crack_segments[i].hit_id))
	_rng.seed = _seed_value + fresh_hit_id * 104729
	# Every visible section emits a sheet, including older and shorter cracks.
	# Reduce each sheet's opacity as the network grows so overlapping light
	# stays translucent instead of covering the stone in a solid color.
	var density_scale := clampf(sqrt(10.0 / float(_crack_segments.size())), 0.5, 1.0)
	for segment in _crack_segments:
		if not bool(segment.get("has_centerline", true)):
			continue
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var normal: Vector3 = segment.get("normal", _normal)
		var offset_a: Vector3 = segment.get("offset_a", normal)
		var offset_b: Vector3 = segment.get("offset_b", normal)
		var impact: Vector3 = segment.impact
		var source_t := 0.5
		var source_point := a.lerp(b, source_t)
		var source_a := a + offset_a * RAY_OFFSET
		var source_b := b + offset_b * RAY_OFFSET
		var origin := (source_a + source_b) * 0.5
		# One buried light shines THROUGH the complete crack network. Shared
		# endpoints stay shared at the far end too, just like adjacent sections
		# of an open door slit. No independent sideways fans or random widening.
		var tip_a := _emitter_position + (source_a - _emitter_position) * _projection_scale
		var tip_b := _emitter_position + (source_b - _emitter_position) * _projection_scale
		var advance := (tip_a + tip_b) * 0.5 - origin
		_rays.append({
			"origin": origin,
			"direction": advance.normalized(),
			"length": advance.length(),
			"tip_a": tip_a,
			"tip_b": tip_b,
			"weight": SHEET_OPACITY * density_scale * (1.0 if bool(segment.fresh) else 0.85),
			"source_index": int(segment.source_index),
			"source_hit_id": int(segment.hit_id),
			"source_a": a,
			"source_b": b,
			"normal": normal,
			"offset_a": offset_a,
			"offset_b": offset_b,
			"source_impact": impact,
			"source_t": source_t,
			"fresh": bool(segment.fresh)
		})
	if _rays.is_empty():
		return
	for i in range(8):
		_dust.append({
			"ray": mini(int(float(i) * float(_rays.size()) / 8.0), _rays.size() - 1),
			"phase": _rng.randf_range(0.28, 0.61),
			"size": _rng.randf_range(0.045, 0.065),
			"offset": Vector2(_rng.randf_range(-0.34, 0.34), _rng.randf_range(-0.25, 0.25))
		})


func _update_visuals() -> void:
	var progress := clampf(_elapsed / _duration, 0.0, 1.0)
	var attack := lerpf(0.58, 1.0, smoothstep(0.0, 0.055, _elapsed))
	var tail := 1.0 - smoothstep(0.46, 1.0, progress)
	var energy := attack * tail * (1.0 + _damage * 0.20 + (0.15 if _broken else 0.0))
	_beam_material.set_shader_parameter("pulse_amount", energy)
	_dust_material.set_shader_parameter("pulse_amount", energy)
	_crack_material.set_shader_parameter("pulse_amount", energy * 1.10)
	_glow_material.set_shader_parameter("pulse_amount", energy)
	_source_material.set_shader_parameter("pulse_amount", energy)
	var expansion := smoothstep(0.0, 0.12, _elapsed)
	_beam_material.set_shader_parameter("beam_growth", expansion)
	_source_material.set_shader_parameter("beam_growth", expansion)
	_dust_material.set_shader_parameter("effect_progress", progress)
	var camera_basis := _view_basis()
	_dust_material.set_shader_parameter("camera_right", camera_basis.x.normalized())
	_dust_material.set_shader_parameter("camera_up", camera_basis.y.normalized())


func _draw_cracks() -> void:
	if _crack_segments.is_empty():
		_crack_mesh.mesh = null
		_glow_mesh.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_surface := SurfaceTool.new()
	glow_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in _crack_segments:
		var intensity := 1.0 if bool(segment.fresh) else 0.65
		if segment.has("ribbon") and segment.has("triangle"):
			_add_surface_ribbon(surface, segment, CRACK_CORE_RATIO, CRACK_OFFSET, intensity)
			_add_surface_ribbon(glow_surface, segment, CRACK_GLOW_RATIO, GLOW_OFFSET, intensity)
			continue
		var normal: Vector3 = segment.get("normal", _normal)
		var offset_a: Vector3 = segment.get("offset_a", normal)
		var offset_b: Vector3 = segment.get("offset_b", normal)
		var a: Vector3 = segment.a + offset_a * CRACK_OFFSET
		var b: Vector3 = segment.b + offset_b * CRACK_OFFSET
		# Width is the stone renderer's complete visible half-width, including
		# weight and growth. Applying either again would misalign the two ribbons.
		var side := normal.cross(Vector3(segment.b) - Vector3(segment.a)).normalized() * float(segment.width)
		var side_a: Vector3 = segment.get("side_a", side)
		var side_b: Vector3 = segment.get("side_b", side)
		_add_quad(surface, a - side_a * CRACK_CORE_RATIO, a + side_a * CRACK_CORE_RATIO, b - side_b * CRACK_CORE_RATIO, b + side_b * CRACK_CORE_RATIO, intensity)
		var glow_a: Vector3 = segment.a + offset_a * GLOW_OFFSET
		var glow_b: Vector3 = segment.b + offset_b * GLOW_OFFSET
		_add_quad(glow_surface, glow_a - side_a * CRACK_GLOW_RATIO, glow_a + side_a * CRACK_GLOW_RATIO, glow_b - side_b * CRACK_GLOW_RATIO, glow_b + side_b * CRACK_GLOW_RATIO, intensity)
	_crack_mesh.mesh = surface.commit()
	_glow_mesh.mesh = glow_surface.commit()


func _add_surface_ribbon(surface: SurfaceTool, segment: Dictionary, multiplier: float, depth: float, intensity: float) -> void:
	var ribbon: PackedVector3Array = segment["ribbon"]
	var triangle: PackedVector3Array = segment["triangle"]
	var normal: Vector3 = segment["normal"]
	var a: Vector3 = segment["ribbon_a"]
	var b: Vector3 = segment["ribbon_b"]
	var corners: Array[Dictionary] = []
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	if bool(segment.get("junction", false)):
		# The small shared opening joins the banks of three or more branches.
		# Scale it around their common root, without creating another light ray.
		var origin: Vector3 = segment["junction_center"]
		var x := normal.cross(Vector3.UP).normalized()
		if x.length_squared() < 0.1:
			x = normal.cross(Vector3.RIGHT).normalized()
		var y := normal.cross(x).normalized()
		var radius := 0.00001
		for point in ribbon:
			radius = maxf(radius, point.distance_to(origin))
		for point in ribbon:
			var delta := point - origin
			var uv := Vector2(0.5, 0.5) + Vector2(delta.dot(x), delta.dot(y)) / (radius * 2.0)
			corners.append({"point": origin + delta * multiplier, "uv": uv})
	else:
		for i in ribbon.size():
			var axis := a if i < 2 else b
			corners.append({"point": axis + (ribbon[i] - axis) * multiplier, "uv": uvs[i]})
	var center := Vector3.ZERO
	for point in triangle:
		center += point
	center /= float(triangle.size())
	for i in triangle.size():
		var start := triangle[i]
		var inward := normal.cross(triangle[(i + 1) % triangle.size()] - start).normalized()
		if inward.dot(center - start) < 0.0:
			inward = -inward
		var clipped: Array[Dictionary] = []
		for j in corners.size():
			var first: Dictionary = corners[j]
			var second: Dictionary = corners[(j + 1) % corners.size()]
			var first_distance := inward.dot(Vector3(first.point) - start)
			var second_distance := inward.dot(Vector3(second.point) - start)
			if first_distance >= -0.000001:
				clipped.append(first)
			if (first_distance < 0.0 and second_distance > 0.0) or (first_distance > 0.0 and second_distance < 0.0):
				var t := first_distance / (first_distance - second_distance)
				clipped.append({"point": Vector3(first.point).lerp(second.point, t), "uv": Vector2(first.uv).lerp(second.uv, t)})
		corners = clipped
	for i in range(1, corners.size() - 1):
		for index: int in [0, i, i + 1]:
			var point: Vector3 = corners[index].point
			surface.set_color(Color(1.0, 1.0, 1.0, intensity))
			surface.set_uv(corners[index].uv)
			surface.add_vertex(point + _surface_offset(point, segment, normal) * depth)


func _surface_offset(point: Vector3, segment: Dictionary, normal: Vector3) -> Vector3:
	if _surface_geometry != null and segment.has("face_id"):
		return _surface_geometry.surface_offset(point, int(segment["face_id"]))
	var polygon: PackedVector3Array = segment.get("polygon", PackedVector3Array())
	var offsets: PackedVector3Array = segment.get("polygon_offsets", PackedVector3Array())
	if offsets.size() != polygon.size():
		return normal
	for i in polygon.size():
		var next := (i + 1) % polygon.size()
		var edge := polygon[next] - polygon[i]
		var t := clampf((point - polygon[i]).dot(edge) / maxf(edge.length_squared(), 0.00000001), 0.0, 1.0)
		if point.distance_squared_to(polygon[i] + edge * t) < 0.00000001:
			return offsets[i].lerp(offsets[next], t)
	return normal


func _view_basis() -> Basis:
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if is_instance_valid(camera):
			return global_basis.inverse() * camera.global_basis
	return Basis(_tangent, _bitangent, _normal)


func _draw_beams() -> void:
	if _rays.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	surface.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for ray in _rays:
		var source_a: Vector3 = ray.source_a + Vector3(ray.offset_a) * RAY_OFFSET
		var source_b: Vector3 = ray.source_b + Vector3(ray.offset_b) * RAY_OFFSET
		# Both root vertices sit on the real crack endpoints. The whole line
		# projects outward; its edges continue the buried source-to-slit lines.
		_add_beam_quad(surface, source_a, source_b, ray.tip_a, ray.tip_b, float(ray.weight))
	_beam_mesh.mesh = surface.commit()
	# Reuse the exact shaft geometry so the hot source cannot drift off its
	# fracture or change direction independently of the wider colored beam.
	_source_mesh.mesh = _beam_mesh.mesh


func _draw_dust() -> void:
	if _rays.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	surface.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	for mote in _dust:
		var ray: Dictionary = _rays[int(mote.ray)]
		var origin: Vector3 = ray.origin
		var travel: Vector3 = Vector3(ray.direction) * float(ray.length)
		var offset: Vector2 = mote.offset
		var size := float(mote.size) * (0.82 + _damage * 0.20)
		for uv in uvs:
			surface.set_color(Color.WHITE)
			surface.set_uv(uv)
			surface.set_custom(0, Color(travel.x, travel.y, travel.z, float(mote.phase)))
			surface.set_custom(1, Color(offset.x, offset.y, size, 0.0))
			surface.add_vertex(origin)
	_dust_mesh.mesh = surface.commit()
	# The shader moves billboards away from their encoded origins. Include
	# the full travel and side offsets in CPU-side visibility bounds.
	_dust_mesh.custom_aabb = _beam_mesh.mesh.get_aabb().grow(0.75)


func _add_beam_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, alpha: float) -> void:
	var vertices := PackedVector3Array([a, b, d, a, d, c])
	var roots := PackedVector3Array([a, b, b, a, b, a])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	for i in range(6):
		var travel := vertices[i] - roots[i]
		surface.set_color(Color(1.0, 1.0, 1.0, alpha))
		surface.set_uv(uvs[i])
		surface.set_custom(0, Color(roots[i].x, roots[i].y, roots[i].z, 0.0))
		surface.set_custom(1, Color(travel.x, travel.y, travel.z, 0.0))
		surface.add_vertex(vertices[i])


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, alpha: float) -> void:
	var vertices := PackedVector3Array([a, b, d, a, d, c])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	for i in range(6):
		surface.set_color(Color(1.0, 1.0, 1.0, alpha))
		surface.set_uv(uvs[i])
		surface.add_vertex(vertices[i])
