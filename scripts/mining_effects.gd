extends Node3D
## Bounded CPU particle batches work in the Compatibility renderer on every target.

const CAPACITY := 300
const FRAGMENT_CAPACITY := 80
const FRAGMENT_LIFETIME := 1.05
const FRAGMENT_OPEN_TIME := 0.09
const FRAGMENT_FLOOR_Y := -5.2
const RING_POOL_CAPACITY := 8
var batches: Array[MultiMeshInstance3D] = []
var particles: Array[Dictionary] = []
var loose_chunks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _fragment_pool: Array[MeshInstance3D] = []
var _fragment_batch_id := 0
var _ring_mesh: TorusMesh
var _ring_material: StandardMaterial3D
var _ring_root: Node3D
var _ring_pool: Array[MeshInstance3D] = []

func _ready() -> void:
	rng.seed = 90421
	for kind in range(3):
		var instance := MultiMeshInstance3D.new()
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		var mesh := SphereMesh.new()
		mesh.radial_segments = 5 if kind == 0 else 8
		mesh.rings = 1 if kind == 0 else 3
		mesh.radius = 1.0
		mesh.height = 2.0
		batch.mesh = mesh
		batch.instance_count = CAPACITY
		batch.visible_instance_count = 0
		instance.multimesh = batch
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		if kind == 1:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.custom_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))
		add_child(instance)
		batches.append(instance)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.88
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = Color("fff2c9")
	_ring_root = Node3D.new()
	_ring_root.name = "ImpactRings"
	add_child(_ring_root)
	# Ordinary hits and a gem award can overlap. Prepare their small node pool
	# once, while all rings share the same immutable shape and material.
	for i in range(4):
		_ring_pool.append(_make_ring_node())
	set_process(false)

func append_render_warmup(parent: Node3D) -> void:
	if not is_node_ready() or not is_instance_valid(parent):
		return
	# These disposable proxies belong only to the caller's warmup viewport.
	# Share actual render resources without emitting particles or consuming RNG.
	var stone_color := Color("89959b")
	var colors: Array[Color] = [stone_color, Color(1.0, 0.8, 0.4), stone_color.lightened(0.22)]
	for kind in range(batches.size()):
		var source := batches[kind]
		var batch := MultiMesh.new()
		batch.transform_format = source.multimesh.transform_format
		batch.use_colors = source.multimesh.use_colors
		batch.use_custom_data = source.multimesh.use_custom_data
		batch.mesh = source.multimesh.mesh
		batch.instance_count = 1
		batch.visible_instance_count = 1
		var size := Vector3(0.07, 0.07 * 3.8, 0.07) if kind == 1 else Vector3.ONE * 0.16
		batch.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(size), Vector3.ZERO))
		batch.set_instance_color(0, colors[kind])
		var proxy := MultiMeshInstance3D.new()
		proxy.name = "WarmupParticle%d" % kind
		proxy.multimesh = batch
		proxy.material_override = source.material_override
		proxy.cast_shadow = source.cast_shadow
		proxy.layers = source.layers
		proxy.position = Vector3(float(kind - 1) * 0.8, 0.0, 0.0)
		parent.add_child(proxy)
	var ring := MeshInstance3D.new()
	ring.name = "WarmupImpactRing"
	ring.mesh = _ring_mesh
	ring.material_override = _ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, -0.65, 0.0)
	ring.quaternion = Quaternion(Vector3.UP, Vector3.BACK)
	ring.scale = Vector3.ONE * 0.28
	parent.add_child(ring)

func impact(point: Vector3, normal: Vector3, broken: bool, stone_color: Color, gem_cover: bool = false) -> void:
	set_process(true)
	var amount := 23 if broken else 10
	for i in range(amount):
		var direction := (normal * rng.randf_range(1.2, 2.6) + _random_direction() * 1.7).normalized()
		_spawn(0, point + normal * 0.04, direction * rng.randf_range(2.0, 6.8), stone_color.lightened(rng.randf_range(-0.15, 0.3)), rng.randf_range(0.035, 0.11), rng.randf_range(0.45, 1.1))
	for i in range(15 if broken else 8):
		var direction := (normal * 0.8 + _random_direction()).normalized()
		_spawn(1, point + normal * 0.07, direction * rng.randf_range(3.0, 7.6), Color(1.0, 0.8, 0.4) if i % 3 else Color(1.0, 0.97, 0.79), rng.randf_range(0.026, 0.054), rng.randf_range(0.12, 0.3))
	for i in range(4 if gem_cover and broken else 1 if gem_cover else 9 if broken else 4):
		var dust_size := rng.randf_range(0.035, 0.055) if gem_cover else rng.randf_range(0.07, 0.15)
		_spawn(2, point + _random_direction() * 0.12, normal * 0.6 + _random_direction() * 0.65, stone_color.lightened(0.08 if gem_cover else 0.22), dust_size, rng.randf_range(0.22, 0.42))
	_ring(point + normal * 0.06, normal, broken)

func shed_fragments(fragments: Array[Dictionary], material: Material, placement: Transform3D, outward: Vector3, impact_point: Vector3) -> void:
	if fragments.is_empty():
		return
	var valid_fragments: Array[Dictionary] = []
	var center_sum := Vector3.ZERO
	var area_sum := 0.0
	for fragment in fragments:
		if not (fragment.get("mesh") is Mesh) or not (fragment.get("center") is Vector3):
			continue
		var area := maxf(float(fragment.get("area", 0.0)), 0.0001)
		center_sum += (placement * Vector3(fragment.center)) * area
		area_sum += area
		valid_fragments.append(fragment)
	if valid_fragments.is_empty():
		return
	set_process(true)
	var plate_center := center_sum / area_sum
	var average_area := area_sum / float(valid_fragments.size())
	var normal := outward.normalized() if outward.length_squared() > 0.0001 else Vector3.UP
	var cut_material: Material = material.duplicate() if material != null else null
	if cut_material is ShaderMaterial:
		# The original plate may still carry its final-hit flash. Debris retains its
		# stone color and the geometry's pale cut faces, without a permanent flash.
		cut_material.set_shader_parameter("hit_flash", 0.0)
		cut_material.set_shader_parameter("hovered", 0.0)
	_fragment_batch_id += 1
	for i in range(mini(valid_fragments.size(), FRAGMENT_CAPACITY)):
		var fragment := valid_fragments[i]
		while loose_chunks.size() >= FRAGMENT_CAPACITY:
			_recycle_fragment(loose_chunks.pop_front())
		var node := _acquire_fragment_node()
		var center: Vector3 = fragment.center
		var area := maxf(float(fragment.get("area", 0.0)), 0.0001)
		var initial_transform := placement * Transform3D(Basis.IDENTITY, center)
		var world_center := initial_transform.origin
		var from_center := world_center - plate_center
		from_center -= normal * from_center.dot(normal)
		var from_impact := world_center - impact_point
		from_impact -= normal * from_impact.dot(normal)
		var radial := from_center.normalized() * 0.78 + from_impact.normalized() * 0.22
		if radial.length_squared() < 0.0001:
			radial = normal.cross(Vector3.UP)
			if radial.length_squared() < 0.1:
				radial = normal.cross(Vector3.RIGHT)
			radial = radial.rotated(normal, TAU * float(i) / float(valid_fragments.size()))
		radial = radial.normalized()
		var weight_factor := clampf(sqrt(average_area / area), 0.78, 1.35)
		var velocity := radial * rng.randf_range(2.8, 4.6) * weight_factor
		velocity += normal * rng.randf_range(1.7, 2.8) + Vector3.UP * rng.randf_range(0.55, 1.25)
		var spin_axis := (normal.cross(radial) + _random_direction() * 0.48).normalized()
		var polygon: PackedVector3Array = fragment.get("polygon", PackedVector3Array())
		node.mesh = fragment.mesh
		node.material_override = cut_material
		node.global_transform = initial_transform
		node.set_meta("fracture_fragment", true)
		node.set_meta("fracture_batch", _fragment_batch_id)
		node.set_meta("source_center", center)
		node.set_meta("source_area", area)
		node.set_meta("source_polygon", polygon)
		loose_chunks.append({
			"node": node,
			"velocity": velocity,
			"spin": spin_axis * rng.randf_range(3.4, 6.4),
			"rotation": Quaternion.IDENTITY,
			"age": 0.0,
			"life": FRAGMENT_LIFETIME * rng.randf_range(0.91, 1.08),
			"position": world_center,
			"base_basis": placement.basis,
			"initial_transform": initial_transform,
			"opening_vector": radial * rng.randf_range(0.10, 0.17) + normal * 0.024,
			"source_center": center,
			"source_area": area,
			"source_polygon": polygon,
			"impact_point": impact_point,
			"outward": normal,
			"batch_id": _fragment_batch_id,
			"floor_clearance": clampf(sqrt(area) * 0.18, 0.035, 0.24)
		})


func clear_fragments() -> void:
	for fragment in loose_chunks:
		var node: MeshInstance3D = fragment.node
		if is_instance_valid(node):
			node.hide()
			node.queue_free()
	loose_chunks.clear()
	for node in _fragment_pool:
		if is_instance_valid(node):
			node.queue_free()
	_fragment_pool.clear()
	_fragment_batch_id = 0
	if particles.is_empty() and rings.is_empty():
		set_process(false)


func _acquire_fragment_node() -> MeshInstance3D:
	while not _fragment_pool.is_empty():
		var pooled := _fragment_pool.pop_back() as MeshInstance3D
		if is_instance_valid(pooled) and not pooled.is_queued_for_deletion():
			pooled.show()
			return pooled
	var node := MeshInstance3D.new()
	node.name = "StoneFragment"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _recycle_fragment(fragment: Dictionary) -> void:
	var node: MeshInstance3D = fragment.node
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	node.hide()
	node.mesh = null
	node.material_override = null
	for key in node.get_meta_list():
		node.remove_meta(key)
	if _fragment_pool.size() < FRAGMENT_CAPACITY:
		_fragment_pool.append(node)
	else:
		node.queue_free()

func gem_burst(point: Vector3, special: bool = true, tier: int = -1) -> void:
	set_process(true)
	var palette := [Color("ffce64"), Color("fff1c0"), Color("f5a6ff")] if special else [Color("7ffff0"), Color("d7fff5"), Color("bdf7ea")]
	if tier >= 0:
		var tint: Color = preload("res://scripts/gem.gd").LIGHT_COLORS[clampi(tier, 0, 5)]
		palette = [tint, tint.lightened(0.40), tint.lightened(0.72)]
	for i in range(100 if special else 32):
		var direction := _random_direction()
		_spawn(1 if i % 2 else 0, point, direction * rng.randf_range(2.0, 8.0 if special else 4.5), palette[i % 3], rng.randf_range(0.025, 0.10), rng.randf_range(0.6, 1.6))
	_ring(point, Vector3.FORWARD, special)

func _spawn(kind: int, point: Vector3, velocity: Vector3, color: Color, size: float, life: float) -> void:
	if particles.size() >= 480:
		particles.pop_front()
	particles.append({"kind": kind, "position": point, "velocity": velocity, "color": color, "size": size, "age": 0.0, "life": life, "spin": rng.randf_range(-6.0, 6.0)})

func _ring(point: Vector3, normal: Vector3, broken: bool) -> void:
	set_process(true)
	var node: MeshInstance3D = _ring_pool.pop_back() if not _ring_pool.is_empty() else _make_ring_node()
	node.position = point
	node.quaternion = Quaternion(Vector3.UP, normal.normalized())
	node.scale = Vector3.ONE * 0.025
	node.show()
	rings.append({"node": node, "age": 0.0, "life": 0.22 if broken else 0.14, "size": 0.62 if broken else 0.32})

func _make_ring_node() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "ImpactRing"
	node.mesh = _ring_mesh
	node.material_override = _ring_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.hide()
	_ring_root.add_child(node)
	return node

func _recycle_ring(node: MeshInstance3D) -> void:
	node.hide()
	if _ring_pool.size() < RING_POOL_CAPACITY:
		_ring_pool.append(node)
	else:
		node.queue_free()

func _random_direction() -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()

func _process(delta: float) -> void:
	var counts := [0, 0, 0]
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.age += delta
		if p.age >= p.life:
			particles.remove_at(i)
			continue
		var kind: int = p.kind
		p.velocity.y -= delta * (9.0 if kind == 0 else 1.5 if kind == 1 else -0.45)
		p.position += p.velocity * delta
		if p.position.y < -5.4 and kind == 0:
			p.position.y = -5.4
			p.velocity = p.velocity * Vector3(0.6, -0.3, 0.6)
		var t: float = p.age / p.life
		var size: float = p.size * (1.0 - t * t)
		if kind == 2:
			size *= 1.0 + t * 3.0
		var basis := Basis(Vector3(0.6, 0.8, 0).normalized(), p.spin * p.age).scaled(Vector3.ONE * maxf(size, 0.001))
		if kind == 1:
			var axis: Vector3 = p.velocity.normalized()
			basis = Basis(Quaternion(Vector3.UP, axis)).scaled(Vector3(size, size * 3.8, size))
		var index: int = counts[kind]
		if index < CAPACITY:
			batches[kind].multimesh.set_instance_transform(index, Transform3D(basis, p.position))
			batches[kind].multimesh.set_instance_color(index, p.color)
			counts[kind] += 1
	for kind in range(3):
		batches[kind].multimesh.visible_instance_count = counts[kind]
	for i in range(loose_chunks.size() - 1, -1, -1):
		var p: Dictionary = loose_chunks[i]
		if not is_instance_valid(p.node):
			loose_chunks.remove_at(i)
			continue
		p.age += delta
		if p.age >= p.life:
			_recycle_fragment(p)
			loose_chunks.remove_at(i)
			continue
		p.velocity.y -= 13.5 * delta
		p.position += p.velocity * delta
		var opening := 1.0 - pow(1.0 - clampf(float(p.age) / FRAGMENT_OPEN_TIME, 0.0, 1.0), 3.0)
		var separation := Vector3(p.opening_vector) * opening
		var floor_height := FRAGMENT_FLOOR_Y + float(p.floor_clearance) - separation.y
		if p.position.y < floor_height:
			p.position.y = floor_height
			if p.velocity.y < 0.0:
				p.velocity *= Vector3(0.62, -0.32, 0.62)
				p.spin *= 0.64
		var spin: Vector3 = p.spin
		p.rotation = (Quaternion(spin.normalized(), spin.length() * delta) * Quaternion(p.rotation)).normalized()
		var size := 1.0 - smoothstep(float(p.life) * 0.61, float(p.life), float(p.age))
		var basis := (Basis(Quaternion(p.rotation)) * Basis(p.base_basis)).scaled(Vector3.ONE * maxf(size, 0.001))
		p.node.global_transform = Transform3D(basis, Vector3(p.position) + separation)
	for i in range(rings.size() - 1, -1, -1):
		var p: Dictionary = rings[i]
		p.age += delta
		if p.age >= p.life:
			_recycle_ring(p.node)
			rings.remove_at(i)
			continue
		var t: float = p.age / p.life
		p.node.scale = Vector3.ONE * lerpf(0.06, p.size, t)
		p.node.visible = t < 0.82
	if particles.is_empty() and loose_chunks.is_empty() and rings.is_empty():
		set_process(false)
