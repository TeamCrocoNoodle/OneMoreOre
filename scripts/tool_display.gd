extends Control
## A display cabinet. Stock and prices are previews until tool rules are defined.

const DisplayModels = preload("res://scripts/tool_display_models.gd")
const Cabinet = preload("res://scripts/tool_cabinet.gd")
const ModelGallery = preload("res://scripts/ui_model_gallery.gd")
const GOLD := Color("dca75c")
const TEXT := Color("eee4d3")

var selected_index := -1
var _catalog: Array[Dictionary] = []
var _buttons: Array[Button] = []
var model_gallery: Node
var cabinet_model: Node3D
var cabinet_viewport: SubViewport
var _cabinet_camera: Camera3D
var _cabinet_render_rect := Rect2()
var _cabinet_signature := ""
var _cabinet_rendered := false
var _items: Array[Rect2] = []
var _tags: Array[Rect2] = []
var _font: SystemFont
var _bold: SystemFont
var _scale := 1.0
var _view := Vector2(1200, 680)
var _cabinet := Rect2()
var _columns := 2
var _row_height := 260.0
var _scroll := 0.0
var _scroll_limit := 0.0
var _hovered := -1
var _open := false
var _pulse := 0.0
var _touch_index := -1
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _touch_dragged := false


func _ready() -> void:
	name = "ToolDisplay"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "sans-serif"])
	_font.multichannel_signed_distance_field = true
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_bold.multichannel_signed_distance_field = true
	if not is_instance_valid(model_gallery):
		model_gallery = ModelGallery.new()
		add_child(model_gallery)
	model_gallery.visuals_ready.connect(queue_redraw)
	_catalog = DisplayModels.get_catalog()
	for index in _catalog.size():
		var button := Button.new()
		button.name = "DisplayTool_" + str(_catalog[index].id)
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_select_item.bind(index))
		button.mouse_entered.connect(_hover_item.bind(index))
		button.mouse_exited.connect(_leave_item.bind(index))
		button.focus_entered.connect(_focus_item.bind(index))
		add_child(button)
		_buttons.append(button)
	gui_input.connect(_panel_input)
	hide()
	set_process(false)
	set_process_input(false)
	_arrange()


func set_layout(rect: Rect2, ui_scale: float) -> void:
	position = rect.position
	size = rect.size
	_scale = maxf(ui_scale, 0.001)
	_view = size / _scale
	if is_node_ready():
		_arrange()


func set_display_open(value: bool) -> void:
	_open = value
	visible = value
	set_process_input(value)
	if value:
		_refresh_cabinet()
		if not _cabinet_rendered:
			cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			if not RenderingServer.frame_post_draw.is_connected(_cabinet_frame_finished):
				RenderingServer.frame_post_draw.connect(_cabinet_frame_finished, CONNECT_ONE_SHOT)
		queue_redraw()
	else:
		_touch_index = -1
		_touch_dragged = false
		_hovered = -1
		_pulse = 0.0
		set_process(false)
		if is_instance_valid(cabinet_viewport):
			cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func get_catalog() -> Array[Dictionary]:
	return _catalog.duplicate(true)


func get_item_rect(index: int) -> Rect2:
	if index < 0 or index >= _items.size():
		return Rect2()
	return _buttons[index].get_global_rect()


func get_price_tag_rect(index: int) -> Rect2:
	if index < 0 or index >= _tags.size():
		return Rect2()
	return Rect2(global_position + _tags[index].position * _scale, _tags[index].size * _scale)


func get_scroll_offset() -> float:
	return _scroll


func get_scroll_limit() -> float:
	return _scroll_limit


func scroll_by(delta: float) -> void:
	var next := clampf(_scroll + delta, 0.0, _scroll_limit)
	if is_equal_approx(next, _scroll):
		return
	_scroll = next
	_arrange()


func focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _arrange() -> void:
	_columns = 2
	var rows := ceili(float(_catalog.size()) / float(_columns))
	var width := minf(1120.0, _view.x - 32.0)
	var desired_height := minf(width / 1.88, _view.y - 28.0) if _view.x >= 680 else _view.y - 28.0
	_row_height = clampf((desired_height - Cabinet.HEIGHT_PAD) / rows, 160.0 if _view.x >= 680 else 190.0, 202.0 if _view.x >= 680 else 235.0)
	var height := _row_height * rows + Cabinet.HEIGHT_PAD
	_scroll_limit = maxf(0.0, height + 28.0 - _view.y)
	_scroll = clampf(_scroll, 0.0, _scroll_limit)
	_cabinet = Rect2((_view.x - width) * 0.5, -8.0 - _scroll, width, height)
	var cell_width := (width - 48.0) / float(_columns)
	_items.clear()
	_tags.clear()
	for index in _catalog.size():
		var column := index % _columns
		var row := index / _columns
		var item := Rect2(_cabinet.position + Vector2(24.0 + column * cell_width, 18.0 + row * _row_height), Vector2(cell_width, _row_height))
		_items.append(item)
		var tag_width := minf(158.0, cell_width - 18.0)
		_tags.append(Rect2(item.get_center().x - tag_width * 0.5, item.end.y - 57.0, tag_width, 57.0))
		var button := _buttons[index]
		button.position = item.position * _scale
		button.size = item.size * _scale
		button.focus_neighbor_left = _buttons[maxi(0, index - 1)].get_path()
		button.focus_neighbor_right = _buttons[mini(_buttons.size() - 1, index + 1)].get_path()
		button.focus_neighbor_top = _buttons[maxi(0, index - _columns)].get_path()
		button.focus_neighbor_bottom = _buttons[mini(_buttons.size() - 1, index + _columns)].get_path()
	_cabinet_render_rect = _cabinet.grow_individual(12, 20, 12, 12)
	if _open:
		_refresh_cabinet()
	_update_projected_tags()
	queue_redraw()


func _build_cabinet_renderer() -> void:
	cabinet_viewport = SubViewport.new()
	cabinet_viewport.name = "CabinetModelViewport"
	cabinet_viewport.transparent_bg = true
	cabinet_viewport.world_3d = World3D.new()
	cabinet_viewport.msaa_3d = Viewport.MSAA_2X
	cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(cabinet_viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7d2dc")
	environment.ambient_light_energy = 0.60
	environment_node.environment = environment
	cabinet_viewport.add_child(environment_node)
	_cabinet_camera = Camera3D.new()
	_cabinet_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cabinet_camera.fov = 34.0
	_cabinet_camera.near = 0.1
	_cabinet_camera.far = 40.0
	_cabinet_camera.position = Vector3(0, 2, 12)
	_cabinet_camera.current = true
	cabinet_viewport.add_child(_cabinet_camera)
	_cabinet_camera.look_at(Vector3.ZERO)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-22, -12, -3)
	key.light_color = Color("f4ecdf")
	key.light_energy = 0.95
	key.shadow_enabled = true
	key.shadow_opacity = 0.70
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 25.0
	key.shadow_bias = 0.25
	key.shadow_normal_bias = 0.65
	cabinet_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(10, 135, 0)
	fill.light_color = Color("a6bdd0")
	fill.light_energy = 0.30
	cabinet_viewport.add_child(fill)
	cabinet_model = Cabinet.new()
	cabinet_viewport.add_child(cabinet_model)


func _refresh_cabinet() -> void:
	if not is_instance_valid(cabinet_viewport):
		_build_cabinet_renderer()
	var screen_transform := get_viewport().get_final_transform()
	var physical_scale := _scale * minf(screen_transform.x.length(), screen_transform.y.length())
	var target_pixels := _cabinet_render_rect.size * physical_scale
	var resolution_scale := minf(1.2, 1536.0 / maxf(target_pixels.x, target_pixels.y))
	var pixels := Vector2i((target_pixels * resolution_scale).ceil())
	var signature := str(_cabinet.size) + ":" + str(_row_height) + ":" + str(_columns) + ":" + str(pixels)
	if signature == _cabinet_signature:
		return
	_cabinet_signature = signature
	cabinet_model.build(_cabinet.size.x, _row_height, _columns)
	cabinet_viewport.size = pixels
	_frame_cabinet_camera()
	_cabinet_rendered = false
	cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(_cabinet_frame_finished):
		RenderingServer.frame_post_draw.connect(_cabinet_frame_finished, CONNECT_ONE_SHOT)
	_update_projected_tags()


func _update_projected_tags() -> void:
	if not is_instance_valid(cabinet_model) or not is_instance_valid(_cabinet_camera):
		return
	for index in mini(_tags.size(), cabinet_model.tag_corners.size()):
		_tags[index] = _project_model_rect(cabinet_model.tag_corners[index])
		_items[index] = _project_model_rect(cabinet_model.item_corners[index]).merge(_tags[index])
		_buttons[index].position = _items[index].position * _scale
		_buttons[index].size = _items[index].size * _scale


func _frame_cabinet_camera() -> void:
	# A centred perspective view reproduces the reference's converging posts
	# and the larger visible shelf surfaces toward the bottom of the cabinet.
	var bounds: AABB = cabinet_model.get_meta("framing_bounds")
	var aspect := float(cabinet_viewport.size.x) / cabinet_viewport.size.y
	var tilt := deg_to_rad(9.0)
	var tangent := tan(deg_to_rad(_cabinet_camera.fov * 0.5))
	var direction := Vector3(0, sin(tilt), cos(tilt))
	var projected_height := bounds.size.y * cos(tilt) + bounds.size.z * sin(tilt)
	var distance := maxf(bounds.size.x / aspect, projected_height) / (2.0 * tangent) + bounds.size.z * 0.5
	var target := bounds.get_center()
	var viewport_size := Vector2(cabinet_viewport.size)
	for iteration in 3:
		_cabinet_camera.position = target + direction * distance
		_cabinet_camera.look_at(target)
		var projected := Rect2(_cabinet_camera.unproject_position(bounds.get_endpoint(0)), Vector2.ZERO)
		for point in range(1, 8):
			projected = projected.expand(_cabinet_camera.unproject_position(bounds.get_endpoint(point)))
		var ratio := maxf(projected.size.x / (viewport_size.x - 12), projected.size.y / (viewport_size.y - 12))
		var dy := projected.get_center().y - viewport_size.y * 0.5
		target -= _cabinet_camera.basis.y * dy * (2.0 * distance * tangent / viewport_size.y)
		distance *= ratio
	_cabinet_camera.position = target + direction * distance
	_cabinet_camera.look_at(target)
	# Tight bounds also keep the iron plates free of self-shadow striping.
	_cabinet_camera.near = maxf(0.1, distance - 4.0)
	_cabinet_camera.far = distance + 4.0


func _project_model_rect(points: PackedVector3Array) -> Rect2:
	var projected := Rect2()
	for index in points.size():
		var uv := _cabinet_camera.unproject_position(cabinet_model.to_global(points[index])) / Vector2(cabinet_viewport.size)
		var point := _cabinet_render_rect.position + uv * _cabinet_render_rect.size
		projected = Rect2(point, Vector2.ZERO) if index == 0 else projected.expand(point)
	return projected


func _cabinet_frame_finished() -> void:
	if _open:
		_cabinet_rendered = true
		cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()


func _hover_item(index: int) -> void:
	_hovered = index
	queue_redraw()


func _leave_item(index: int) -> void:
	if _hovered == index:
		_hovered = -1
		queue_redraw()


func _focus_item(index: int) -> void:
	_hovered = index
	if index < _items.size():
		var item := _items[index].merge(_tags[index])
		if item.position.y < 8.0:
			scroll_by(item.position.y - 8.0)
		elif item.end.y > _view.y - 10.0:
			scroll_by(item.end.y - _view.y + 10.0)
	queue_redraw()


func _select_item(index: int) -> void:
	if not _open or _touch_dragged:
		return
	selected_index = index
	_pulse = 1.0
	set_process(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	# Own an entire touch gesture so a scroll never leaves a native Button
	# pressed or accidentally selects a price tag when the finger lifts.
	if not _open:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0 and get_global_rect().has_point(event.position):
			_touch_index = event.index
			_touch_start = event.position
			_touch_last = event.position
			_touch_dragged = false
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			if not _touch_dragged and get_global_rect().has_point(event.position):
				for index in _items.size():
					if get_item_rect(index).has_point(event.position) and get_item_rect(index).has_point(_touch_start):
						_select_item(index)
						break
			_touch_dragged = false
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		if event.position.distance_to(_touch_start) > 8.0:
			_touch_dragged = true
		if _touch_dragged:
			scroll_by((_touch_last.y - event.position.y) / _scale)
			get_viewport().set_input_as_handled()
		_touch_last = event.position
		get_viewport().set_input_as_handled()


func _panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			scroll_by(76.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -76.0)
			accept_event()
	elif event is InputEventPanGesture:
		scroll_by(event.delta.y * 28.0)
		accept_event()


func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 3.5)
	queue_redraw()
	if _pulse <= 0.0:
		set_process(false)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _scale)
	_draw_cabinet()
	for index in _items.size():
		_draw_item(index)
	if _scroll_limit > 0.0:
		var track := Rect2(_view.x - 7.0, 14.0, 3.0, _view.y - 28.0)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var thumb_height := maxf(26.0, track.size.y * _view.y / (_view.y + _scroll_limit))
		var thumb_y := track.position.y + (track.size.y - thumb_height) * _scroll / _scroll_limit
		draw_rect(Rect2(track.position.x, thumb_y, 3.0, thumb_height), Color(GOLD, 0.55))
	draw_set_transform(Vector2.ZERO)


func _draw_cabinet() -> void:
	if is_instance_valid(cabinet_viewport):
		draw_texture_rect(cabinet_viewport.get_texture(), _cabinet_render_rect, false)


func _draw_item(index: int) -> void:
	var tag := _tags[index]
	var data: Dictionary = _catalog[index]
	var active := index == _hovered or index == selected_index
	# The backing and bolts are real iron meshes. Project only their lettering.
	var text_scale := clampf(tag.size.y / 43.0, 0.70, 1.10)
	var title_size := _fit_label(str(data.title), roundi(13 * text_scale), tag.size.x - 16)
	_text(str(data.title), Vector2(tag.get_center().x, tag.position.y + tag.size.y * 0.40), title_size, Color("c7cdd0"))
	if bool(data.owned):
		_text("✓ 사용 중", Vector2(tag.get_center().x, tag.position.y + tag.size.y * 0.85), roundi(17 * text_scale), Color("d4d9d5"))
	else:
		var price := str(int(data.price))
		var price_size := roundi(18 * text_scale)
		var price_width := _bold.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, price_size).x
		var center := tag.get_center().x - 18 * text_scale
		var baseline := tag.position.y + tag.size.y * 0.85
		_coin(Vector2(center - price_width * 0.5 - 10 * text_scale, baseline - 6 * text_scale), 7 * text_scale)
		_text(price, Vector2(center + 3 * text_scale, baseline), price_size, GOLD)
		_text("준비 중", Vector2(tag.end.x - 23 * text_scale, baseline - text_scale), roundi(10 * text_scale), Color("94a0a5"), false)
	if active:
		draw_line(Vector2(tag.position.x, tag.end.y), tag.end, Color("dfb978"), 1.5, true)


func _fit_label(value: String, preferred: int, width: float) -> int:
	var font_size := preferred
	while font_size > 8 and _bold.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	return font_size


func _text(value: String, baseline: Vector2, font_size: int, color: Color, bold: bool = true) -> void:
	var font: Font = _bold if bold else _font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _coin(center: Vector2, radius: float) -> void:
	if is_instance_valid(model_gallery):
		model_gallery.draw_coin(self, center, maxf(radius, 9.0))
