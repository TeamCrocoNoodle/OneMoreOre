extends Node
## Shared cached views of actual models. Every icon keeps the game's geometry.

signal visuals_ready

const Gem = preload("res://scripts/gem.gd")
const GoldCoin = preload("res://scripts/gold_coin.gd")
const COIN_RESOLUTION := 256
const GEM_RESOLUTION := 512
const CROP_PADDING := 2.0

var is_ready := false
var build_count := 0
var viewports: Array[SubViewport] = []
var _built := false
var _coin_texture: AtlasTexture
var _gem_textures: Array[AtlasTexture] = []
var _coin_span := Vector2.ONE
var _gem_spans: Array[Vector2] = []


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	ensure_ready()


func ensure_ready() -> void:
	if _built or not is_inside_tree():
		return
	_built = true
	build_count += 1
	var coin_scene := _create_viewport("CoinViewport", COIN_RESOLUTION, -1)
	var coin := GoldCoin.new()
	coin.name = "GoldCoin"
	coin.process_mode = Node.PROCESS_MODE_DISABLED
	coin_scene.stage.add_child(coin)
	coin.rotation = Vector3(-0.08, -0.48, 0.10)
	var coin_crop := _frame_model(coin_scene, coin)
	_coin_texture = coin_crop.texture
	_coin_span = coin_crop.span
	for tier in 6:
		var gem_scene := _create_viewport("GemViewport%d" % tier, GEM_RESOLUTION, tier)
		var jewel := Gem.new()
		jewel.name = "PreviewGem%d" % tier
		jewel.configure(tier, 0)
		jewel.collected = true
		jewel.collision_layer = 0
		jewel.collision_mask = 0
		jewel.process_mode = Node.PROCESS_MODE_DISABLED
		gem_scene.stage.add_child(jewel)
		jewel.show()
		jewel.rotation = Vector3(-0.06, -0.28, -0.08)
		var gem_crop := _frame_model(gem_scene, jewel)
		_gem_textures.append(gem_crop.texture)
		_gem_spans.append(gem_crop.span)
	# The dummy renderer does not issue frame_post_draw. Model/lifecycle tests
	# still finish their one-shot setup; pixel validation uses the real renderer.
	if DisplayServer.get_name() == "headless":
		get_tree().process_frame.connect(_finish_render, CONNECT_ONE_SHOT)
	else:
		RenderingServer.frame_post_draw.connect(_finish_render, CONNECT_ONE_SHOT)


func get_coin_texture() -> Texture2D:
	ensure_ready()
	return _coin_texture


func get_gem_texture(tier: int) -> Texture2D:
	ensure_ready()
	return _gem_textures[clampi(tier, 0, 5)] if _gem_textures.size() == 6 else null


func draw_coin(canvas: CanvasItem, center: Vector2, radius: float, tint: Color = Color.WHITE) -> void:
	ensure_ready()
	_draw_model(canvas, center, radius, _coin_texture, _coin_span, tint)


func draw_gem(canvas: CanvasItem, center: Vector2, radius: float, tier: int, tint: Color = Color.WHITE) -> void:
	ensure_ready()
	if _gem_textures.size() != 6:
		return
	var grade := clampi(tier, 0, 5)
	_draw_model(canvas, center, radius, _gem_textures[grade], _gem_spans[grade], tint)


func _draw_model(canvas: CanvasItem, center: Vector2, radius: float, texture: Texture2D, span: Vector2, tint: Color) -> void:
	if not is_instance_valid(canvas) or texture == null or radius <= 0.0:
		return
	# The texture includes only a two-pixel antialiasing guard around the exact
	# projected mesh. Compensate that guard: visible maximum diameter = 2r.
	var size := texture.get_size() * (radius * 2.0 / maxf(span.x, span.y))
	canvas.draw_texture_rect(texture, Rect2(center - size * 0.5, size), false, tint)


func _create_viewport(viewport_name: String, resolution: int, tier: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2i(resolution, resolution)
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = World3D.new()
	viewport.set_meta("model_kind", "coin" if tier < 0 else "gem")
	viewport.set_meta("tier", tier)
	add_child(viewport)
	viewports.append(viewport)
	var stage := Node3D.new()
	stage.name = "PreviewStage"
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.TRANSPARENT
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("bad6e0")
	settings.ambient_light_energy = 0.30 if tier < 0 else 0.40
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	stage.add_child(environment)
	# The gem shader's internal facets use the original stage illumination.
	# The coin's conventional toon material needs a gentler key to retain
	# its gold hue and a readable step between field, rim and raised emblem.
	_add_light(stage, Vector3(-42, -32, 0), Color("fff1d9"), 1.20 if tier < 0 else 2.2)
	_add_light(stage, Vector3(-18, 142, 0), Color("a1daef"), 0.17 if tier < 0 else 0.30)
	_add_light(stage, Vector3(35, 30, 0), Color("7394b0"), 0.10 if tier < 0 else 0.18)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0, 0, 8)
	camera.near = 0.05
	camera.far = 20.0
	camera.current = true
	stage.add_child(camera)
	return {"viewport": viewport, "stage": stage, "camera": camera, "resolution": resolution}


func _add_light(stage: Node3D, angles: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = false
	stage.add_child(light)


func _frame_model(scene: Dictionary, model: Node3D) -> Dictionary:
	var points: Array[Vector3] = []
	_collect_vertices(model, model.transform, points)
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	model.position = -bounds.get_center()
	var camera: Camera3D = scene.camera
	camera.size = maxf(bounds.size.x, bounds.size.y) * 1.08
	var span := Vector2(bounds.size.x, bounds.size.y) / camera.size * float(scene.resolution)
	var region := Rect2((Vector2.ONE * float(scene.resolution) - span) * 0.5 - Vector2.ONE * CROP_PADDING, span + Vector2.ONE * CROP_PADDING * 2.0)
	var texture := AtlasTexture.new()
	texture.atlas = scene.viewport.get_texture()
	texture.region = region
	texture.filter_clip = true
	scene.viewport.set_meta("model_bounds", AABB(bounds.position - bounds.get_center(), bounds.size))
	scene.viewport.set_meta("projected_span", span)
	scene.viewport.set_meta("crop_region", region)
	return {"texture": texture, "span": span}


func _collect_vertices(node: Node, placement: Transform3D, result: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point in vertices:
				result.append(placement * point)
	for child in node.get_children():
		var child_placement := placement
		if child is Node3D:
			child_placement *= child.transform
		_collect_vertices(child, child_placement, result)


func _finish_render() -> void:
	if is_ready:
		return
	for viewport in viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	is_ready = true
	visuals_ready.emit()
