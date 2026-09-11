extends CanvasLayer
## Draw the actual collected crystal above the HUD during its short flight.
## Geometry, materials, and ownership are preserved; no image/proxy replaces it.

var _source_camera: Camera3D
var _viewport: SubViewport
var _camera: Camera3D
var _scene: Node3D
var _display: TextureRect
var _flights: Dictionary = {}
var _warm_frames := 0
var _initialized := false

var active_count: int:
	get:
		return _flights.size()


func _ready() -> void:
	layer = 21
	set_process(false)


func setup(source_camera: Camera3D) -> void:
	if _initialized or not is_instance_valid(source_camera):
		return
	_initialized = true
	_source_camera = source_camera
	_viewport = SubViewport.new()
	_viewport.name = "CollectedCrystalViewport"
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = source_camera.get_viewport().msaa_3d
	_viewport.world_3d = World3D.new()
	var source_environment := source_camera.get_world_3d().environment
	if source_environment != null:
		var environment: Environment = source_environment.duplicate()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.TRANSPARENT
		_viewport.world_3d.environment = environment
	add_child(_viewport)
	_scene = Node3D.new()
	_scene.name = "FlyingCrystals"
	_viewport.add_child(_scene)
	_camera = Camera3D.new()
	_camera.name = "FlightCamera"
	_camera.current = true
	_scene.add_child(_camera)
	for child in source_camera.get_parent().get_children():
		if child is DirectionalLight3D:
			var light: DirectionalLight3D = child.duplicate(0)
			_scene.add_child(light)
			light.global_transform = child.global_transform
			light.shadow_enabled = false
	_display = TextureRect.new()
	_display.name = "CrystalFlightOverlay"
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.texture = _viewport.get_texture()
	add_child(_display)
	_display.hide()
	get_viewport().size_changed.connect(_resize)
	_resize()
	_sync_camera()
	# Allocate the transparent target once during setup, before timed mining.
	_warm_frames = 2
	set_process(true)


func adopt(jewel: Node3D) -> void:
	if not _initialized or not is_instance_valid(jewel):
		return
	var key := jewel.get_instance_id()
	if _flights.has(key):
		return
	_sync_camera()
	_reparent_crystal(jewel)
	jewel.show()
	_flights[key] = weakref(jewel)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_display.show()
	set_process(true)


func _reparent_crystal(jewel: Node3D) -> void:
	# Reparenting across worlds must not reset the emergence's final transform.
	var transform := jewel.global_transform
	jewel.reparent(_scene, true)
	jewel.global_transform = transform


func release(jewel: Node3D) -> void:
	if is_instance_valid(jewel):
		_flights.erase(jewel.get_instance_id())
		jewel.hide()
	if _flights.is_empty():
		_stop_rendering()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	for key in _flights.keys():
		var jewel: Node3D = _flights[key].get_ref()
		if not is_instance_valid(jewel) or jewel.is_queued_for_deletion():
			_flights.erase(key)
	if _flights.is_empty():
		if _warm_frames > 0:
			_warm_frames -= 1
			return
		_stop_rendering()
		return
	_sync_camera()


func _stop_rendering() -> void:
	# Hide the retained texture immediately: a disabled viewport still contains
	# its last image, which otherwise leaves a gem ghost over the destination.
	_display.hide()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_warm_frames = 0
	set_process(false)


func _resize() -> void:
	if not _initialized:
		return
	var source_viewport := _source_camera.get_viewport()
	var stretch := source_viewport.get_final_transform()
	var dimensions := source_viewport.get_visible_rect().size * Vector2(stretch.x.length(), stretch.y.length())
	# Only a handful of small crystals render here. Bound a 4K window's
	# transient target while keeping its exact display aspect/projection.
	var factor := minf(1.0, 1920.0 / maxf(dimensions.x, dimensions.y))
	_viewport.size = Vector2i(maxi(2, int(round(dimensions.x * factor))), maxi(2, int(round(dimensions.y * factor))))
	_sync_camera()


func _sync_camera() -> void:
	if not is_instance_valid(_source_camera) or not is_instance_valid(_camera):
		return
	_camera.global_transform = _source_camera.global_transform
	_camera.projection = _source_camera.projection
	_camera.keep_aspect = _source_camera.keep_aspect
	_camera.size = _source_camera.size
	_camera.fov = _source_camera.fov
	_camera.frustum_offset = _source_camera.frustum_offset
	_camera.h_offset = _source_camera.h_offset
	_camera.v_offset = _source_camera.v_offset
	_camera.near = _source_camera.near
	_camera.far = _source_camera.far
	_camera.cull_mask = _source_camera.cull_mask
	_camera.attributes = _source_camera.attributes
