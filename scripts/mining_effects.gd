extends Node3D
## Bounded CPU particle batches work in the Compatibility renderer on every target.

const CAPACITY := 300
var batches: Array[MultiMeshInstance3D] = []
var particles: Array[Dictionary] = []
var loose_chunks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

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

func impact(point: Vector3, normal: Vector3, broken: bool, stone_color: Color) -> void:
	var amount := 23 if broken else 10
	for i in range(amount):
		var direction := (normal * rng.randf_range(1.2, 2.6) + _random_direction() * 1.7).normalized()
		_spawn(0, point + normal * 0.04, direction * rng.randf_range(2.0, 6.8), stone_color.lightened(rng.randf_range(-0.15, 0.3)), rng.randf_range(0.035, 0.11), rng.randf_range(0.45, 1.1))
	for i in range(15 if broken else 8):
		var direction := (normal * 0.8 + _random_direction()).normalized()
		_spawn(1, point + normal * 0.07, direction * rng.randf_range(3.0, 7.6), Color(1.0, 0.8, 0.4) if i % 3 else Color(1.0, 0.97, 0.79), rng.randf_range(0.026, 0.054), rng.randf_range(0.12, 0.3))
	for i in range(9 if broken else 4):
		_spawn(2, point + _random_direction() * 0.12, normal * 0.6 + _random_direction() * 0.65, stone_color.lightened(0.22), rng.randf_range(0.07, 0.15), rng.randf_range(0.28, 0.55))
	_ring(point + normal * 0.06, normal, broken)

func shed_chunk(mesh: Mesh, material: Material, placement: Transform3D, outward: Vector3) -> void:
	if loose_chunks.size() >= 18:
		loose_chunks.pop_front().node.queue_free()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_transform = placement
	loose_chunks.append({"node": node, "velocity": outward * rng.randf_range(2.5, 4.5) + Vector3.UP * 2.3, "spin": _random_direction() * rng.randf_range(3.0, 6.0), "age": 0.0, "life": 1.2})

func gem_burst(point: Vector3, special: bool = true) -> void:
	for i in range(100 if special else 32):
		var direction := _random_direction()
		var palette := [Color("ffce64"), Color("fff1c0"), Color("f5a6ff")] if special else [Color("7ffff0"), Color("d7fff5"), Color("bdf7ea")]
		_spawn(1 if i % 2 else 0, point, direction * rng.randf_range(2.0, 8.0 if special else 4.5), palette[i % 3], rng.randf_range(0.025, 0.10), rng.randf_range(0.6, 1.6))
	_ring(point, Vector3.FORWARD, special)

func _spawn(kind: int, point: Vector3, velocity: Vector3, color: Color, size: float, life: float) -> void:
	if particles.size() >= 480:
		particles.pop_front()
	particles.append({"kind": kind, "position": point, "velocity": velocity, "color": color, "size": size, "age": 0.0, "life": life, "spin": rng.randf_range(-6.0, 6.0)})

func _ring(point: Vector3, normal: Vector3, broken: bool) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.88
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 4
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("fff2c9")
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = point
	node.quaternion = Quaternion(Vector3.UP, normal.normalized())
	node.scale = Vector3.ONE * 0.025
	rings.append({"node": node, "age": 0.0, "life": 0.22 if broken else 0.14, "size": 0.62 if broken else 0.32})

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
		p.age += delta
		if p.age >= p.life:
			p.node.queue_free()
			loose_chunks.remove_at(i)
			continue
		p.velocity.y -= 12.0 * delta
		p.node.position += p.velocity * delta
		p.node.rotate(p.spin.normalized(), p.spin.length() * delta)
		if p.node.position.y < -5.2:
			p.node.position.y = -5.2
			p.velocity *= Vector3(0.65, -0.35, 0.65)
		p.node.scale = Vector3.ONE * (1.0 - smoothstep(0.55, 1.2, p.age))
	for i in range(rings.size() - 1, -1, -1):
		var p: Dictionary = rings[i]
		p.age += delta
		if p.age >= p.life:
			p.node.queue_free()
			rings.remove_at(i)
			continue
		var t: float = p.age / p.life
		p.node.scale = Vector3.ONE * lerpf(0.06, p.size, t)
		p.node.visible = t < 0.82
