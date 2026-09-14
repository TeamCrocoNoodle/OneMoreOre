extends Control
## Main-tool cabinet with an explicit purchase/equip confirmation.
signal action_requested(id: String)

const DisplayModels = preload("res://scripts/tool_display_models.gd")
const Cabinet = preload("res://scripts/tool_cabinet.gd")
const ModelGallery = preload("res://scripts/ui_model_gallery.gd")
const MainTools = preload("res://scripts/main_tools.gd")
const AuxTools = preload("res://scripts/aux_tools.gd")
const ResponsiveUI = preload("res://scripts/responsive_ui.gd")
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
var _geometry_signature := ""
var _model_width := 1120.0
var _model_row_height := 202.0
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
var _shop: RefCounted = MainTools.new()
var _main_shop: RefCounted = _shop
var _aux_shop: RefCounted = AuxTools.new()
var selected_kind := "main"
var _kind_buttons: Dictionary = {}
var _kind_bar: ColorRect
var _wallet := 0
var _pending := false
var _inspector: Control
var _confirm: Button
var _detail_rect := Rect2()
var _hero_rect := Rect2()
var _text_origin := Vector2.ZERO
var _description: RichTextLabel
var _preview_viewport: SubViewport
var _preview_model: Node3D
var _preview_index := -1


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
	_catalog = _shop.get_catalog()
	_rebuild_buttons()
	_inspector = Control.new()
	_inspector.name = "ToolInspector"
	_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspector.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _detail_rect.has_point(event.position / _scale):
			cancel_selection()
	)
	add_child(_inspector)
	_description = RichTextLabel.new()
	_description.name = "ToolDescription"
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_override("normal_font", _font)
	_description.add_theme_color_override("default_color", Color("adb9ba"))
	_description.scroll_active = true
	_description.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspector.add_child(_description)
	_confirm = Button.new()
	_confirm.name = "ConfirmToolAction"
	_confirm.text = "✓"
	_confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_confirm.add_theme_font_override("font", _bold)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("263530") if state in ["hover","pressed"] else Color("101817")
		style.border_color = GOLD.darkened(0.50) if state == "disabled" else GOLD
		style.set_border_width_all(2 if state == "focus" else 1)
		style.set_corner_radius_all(4)
		_confirm.add_theme_stylebox_override(state,style)
	_confirm.add_theme_color_override("font_color",TEXT)
	_confirm.pressed.connect(_confirm_action)
	_inspector.add_child(_confirm)
	_inspector.hide()
	_kind_bar = ColorRect.new()
	_kind_bar.color = Color("0e1718")
	add_child(_kind_bar)
	for kind: String in ["main","aux"]:
		var button := Button.new()
		button.name = "ToolKind_"+kind
		button.text = "주 도구" if kind == "main" else "보조 도구"
		button.add_theme_font_override("font",_bold)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state: String in ["normal","hover","pressed","focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("25322d") if state in ["hover","focus"] else Color.TRANSPARENT
			button.add_theme_stylebox_override(state,style)
		button.pressed.connect(select_kind.bind(kind))
		_kind_bar.add_child(button)
		_kind_buttons[kind] = button
	gui_input.connect(_panel_input)
	hide()
	set_process(false)
	set_process_input(false)
	_arrange()


func set_shop_state(model: RefCounted, wallet: int) -> void:
	_main_shop = model
	_shop = _aux_shop if selected_kind == "aux" else _main_shop
	set_wallet(wallet)

func set_aux_shop(model: RefCounted) -> void:
	_aux_shop = model
	if selected_kind == "aux":
		_shop = model
		set_wallet(_wallet)

func set_wallet(wallet: int) -> void:
	_wallet = wallet
	_catalog = _shop.get_catalog()
	_pending = false
	if is_node_ready():
		_layout_inspector()
		queue_redraw()

func select_kind(kind: String) -> void:
	if kind not in ["main","aux"] or kind == selected_kind: return
	cancel_selection()
	selected_kind = kind
	_shop = _aux_shop if kind == "aux" else _main_shop
	_catalog = _shop.get_catalog()
	_hovered = -1
	_scroll = 0
	_preview_index = -1
	_rebuild_buttons()
	_arrange()
	_kind_buttons[kind].grab_focus()

func get_kind_rect(kind: String) -> Rect2:
	return _kind_buttons[kind].get_global_rect()

func _rebuild_buttons() -> void:
	for button in _buttons:
		remove_child(button)
		button.queue_free()
	_buttons.clear()
	for index in _catalog.size():
		var button := Button.new()
		button.name = "DisplayTool_"+str(_catalog[index].id)
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal","hover","pressed","focus","disabled"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		button.pressed.connect(_select_item.bind(index))
		button.mouse_entered.connect(_hover_item.bind(index))
		button.mouse_exited.connect(_leave_item.bind(index))
		button.focus_entered.connect(_focus_item.bind(index))
		add_child(button)
		_buttons.append(button)
	if is_instance_valid(_inspector): move_child(_inspector,-1)
	if is_instance_valid(_kind_bar): move_child(_kind_bar,-1)


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
		cancel_selection()
		_touch_index = -1
		_touch_dragged = false
		_hovered = -1
		_pulse = 0.0
		set_process(false)
		if is_instance_valid(cabinet_viewport):
			cabinet_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(_preview_viewport):
			_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


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
	if is_instance_valid(_kind_bar):
		_kind_bar.size = Vector2(size.x,38*_scale)
		for index in 2:
			var kind: String = ["main","aux"][index]
			var button: Button = _kind_buttons[kind]
			button.position = Vector2(_view.x*0.5-118+index*122,0)*_scale
			button.size = Vector2(114,36)*_scale
			button.add_theme_font_size_override("font_size",int(16*_scale))
			button.add_theme_color_override("font_color",GOLD if kind == selected_kind else Color("a4aeae"))
			button.focus_neighbor_bottom = _buttons[0].get_path()
		_kind_buttons.main.focus_neighbor_right = _kind_buttons.aux.get_path()
		_kind_buttons.aux.focus_neighbor_left = _kind_buttons.main.get_path()
	_columns = 2
	var rows := ceili(float(_catalog.size()) / float(_columns))
	# Cabinet profiles are authored proportions. Only a uniform fit changes
	# with the available space; resizing pixels never stretches the meshes.
	_model_width = 420.0 if _view.x < 660 else (760.0 if _view.x < 1000 else 1120.0)
	_model_row_height = 235.0 if _view.x < 660 else (220.0 if _view.x < 1000 else 202.0)
	var model_height := _model_row_height * rows + Cabinet.HEIGHT_PAD
	var width_fit := maxf(1, _view.x - 32) / _model_width
	var height_fit := maxf(1, _view.y - 76) / model_height
	# Keep the price tags and tools legible; overflow is browsed by scrolling.
	var fit := minf(width_fit, maxf(0.85, height_fit))
	var width := _model_width * fit
	var height := model_height * fit
	_row_height = _model_row_height * fit
	_scroll_limit = maxf(0.0, height + 76.0 - _view.y)
	_scroll = clampf(_scroll, 0.0, _scroll_limit)
	_cabinet = Rect2((_view.x - width) * 0.5, 40.0 - _scroll, width, height)
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
		button.focus_neighbor_top = _kind_buttons[selected_kind].get_path() if index < _columns else _buttons[index - _columns].get_path()
		button.focus_neighbor_bottom = _buttons[mini(_buttons.size() - 1, index + _columns)].get_path()
	_cabinet_render_rect = _cabinet.grow_individual(12 * fit, 20 * fit, 12 * fit, 12 * fit)
	if _open:
		_refresh_cabinet()
	_update_projected_tags()
	_layout_inspector()
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
	var geometry := selected_kind + ":" + str(_model_width) + ":" + str(_model_row_height)
	var pixels := ResponsiveUI.render_size(get_viewport(), _cabinet_render_rect.size, _scale)
	var signature := geometry + ":" + str(pixels)
	if signature == _cabinet_signature:
		return
	_cabinet_signature = signature
	if geometry != _geometry_signature:
		_geometry_signature = geometry
		cabinet_model.build(_model_width, _model_row_height, _columns, selected_kind)
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
		var ratio := maxf(projected.size.x / (viewport_size.x * 0.985), projected.size.y / (viewport_size.y * 0.985))
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
		if item.position.y < 42.0:
			scroll_by(item.position.y - 42.0)
		elif item.end.y > _view.y - 10.0:
			scroll_by(item.end.y - _view.y + 10.0)
	queue_redraw()


func _select_item(index: int) -> void:
	if not _open or _touch_dragged:
		return
	selected_index = index
	_pending = false
	for button in _buttons:
		button.focus_mode = Control.FOCUS_NONE
	_inspector.show()
	_layout_inspector()
	_refresh_preview(index)
	if not _confirm.disabled:
		_confirm.grab_focus()
	_pulse = 1.0
	set_process(true)
	queue_redraw()


func cancel_selection() -> bool:
	var had_selection := selected_index >= 0
	var previous := selected_index
	selected_index = -1
	_pending = false
	_touch_index = -1
	_touch_dragged = false
	for button in _buttons:
		button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(_inspector):
		_inspector.hide()
	if _open and previous >= 0:
		_buttons[previous].grab_focus()
	queue_redraw()
	return had_selection


func get_confirmation_rect() -> Rect2:
	return _confirm.get_global_rect() if selected_index >= 0 and _open else Rect2()


func _confirm_action() -> void:
	if not _open or selected_index < 0 or _pending or _confirm.disabled:
		return
	_pending = true
	_confirm.disabled = true
	action_requested.emit(str(_catalog[selected_index].id))


func _layout_inspector() -> void:
	if not is_instance_valid(_inspector):
		return
	_inspector.position = Vector2.ZERO
	_inspector.size = size
	var narrow := _view.x < 660
	var width := minf(_view.x-28, 820)
	var height := minf(_view.y-66, 570 if narrow else 350)
	_detail_rect = Rect2((_view.x-width)*0.5,42+(_view.y-42-height)*0.5,width,height)
	var r := _detail_rect
	if narrow:
		var hero_height := clampf(height-292, 126, 220)
		_hero_rect = Rect2(r.position+Vector2((width-hero_height)*0.5,38),Vector2.ONE*hero_height)
		_text_origin = Vector2(r.position.x+18,r.position.y+hero_height+73)
	else:
		var side := minf(width*0.42,height-66)
		_hero_rect = Rect2(r.position+Vector2(12,44),Vector2.ONE*side)
		_text_origin = r.position+Vector2(width*0.45,85)
	_confirm.add_theme_font_size_override("font_size",int(29*_scale))
	_confirm.position = Vector2(r.end.x-78,r.end.y-64)*_scale
	_confirm.size = Vector2(62,56)*_scale
	var description_top := _text_origin + Vector2(0, 47)
	_description.position = description_top * _scale
	_description.size = Vector2(r.end.x - description_top.x - 18, maxf(24, r.end.y - 78 - description_top.y)) * _scale
	_description.add_theme_font_size_override("normal_font_size", maxi(1, roundi(15 * _scale)))
	if selected_index >= 0:
		var data: Dictionary = _catalog[selected_index]
		if _description.text != str(data.description):
			_description.text = str(data.description)
			_description.scroll_to_line(0)
		_confirm.disabled = _pending or bool(data.equipped) or (not bool(data.owned) and _wallet < int(data.price))
		_confirm.text = "✓"
		_confirm.focus_neighbor_left = _confirm.get_path()
		_confirm.focus_neighbor_right = _confirm.get_path()
		_confirm.focus_neighbor_top = _confirm.get_path()
		_confirm.focus_neighbor_bottom = _confirm.get_path()
		if _open:
			_refresh_preview(selected_index)


func _refresh_preview(index: int) -> void:
	if not is_instance_valid(_preview_viewport):
		_preview_viewport = SubViewport.new()
		_preview_viewport.name = "InspectedToolViewport"
		_preview_viewport.transparent_bg = true
		_preview_viewport.msaa_3d = Viewport.MSAA_4X
		_preview_viewport.world_3d = World3D.new()
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_preview_viewport)
		var environment_node := WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0,0,0,0)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("c7d2dc")
		environment.ambient_light_energy = 0.68
		environment_node.environment = environment
		_preview_viewport.add_child(environment_node)
		var view_camera := Camera3D.new()
		view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		view_camera.size = 4.35
		view_camera.position = Vector3(0,0,6)
		view_camera.current = true
		_preview_viewport.add_child(view_camera)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-30,-25,-8)
		light.light_color = Color("fff0d8")
		light.light_energy = 1.0
		_preview_viewport.add_child(light)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(5,135,0)
		fill.light_color = Color("a8c8e0")
		fill.light_energy = 0.45
		_preview_viewport.add_child(fill)
	_preview_viewport.size = ResponsiveUI.render_size(get_viewport(), _hero_rect.size, _scale, 1536)
	if _preview_index == index:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if is_instance_valid(_preview_model):
		_preview_model.hide()
		_preview_model.queue_free()
	_preview_model = DisplayModels.create_preview(index,selected_kind)
	_preview_viewport.add_child(_preview_model)
	_preview_index = index
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(queue_redraw):
		RenderingServer.frame_post_draw.connect(queue_redraw,CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void:
	# Own an entire touch gesture so a scroll never leaves a native Button
	# pressed or accidentally selects a price tag when the finger lifts.
	if not _open:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if _kind_bar.get_global_rect().has_point(event.position):
			if event.pressed: cancel_selection()
			return
	if selected_index >= 0:
		var scroll_bar := _description.get_v_scroll_bar()
		if scroll_bar.max_value > scroll_bar.page and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
			scroll_bar.value += (-42 if event.is_action_pressed("ui_up") else 42) * _scale
			get_viewport().set_input_as_handled()
			return
		var pointer_press: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
		if pointer_press and not get_global_rect().has_point(event.position):
			# Leave header tabs / Close available to both mouse and touch.
			cancel_selection()
			return
		if event.is_action_pressed("ui_accept"):
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null and focus != _confirm:
				return
			_confirm_action()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			cancel_selection()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch:
			if event.pressed and _touch_index < 0:
				_touch_index = event.index
				_touch_start = event.position
				_touch_dragged = false
			elif not event.pressed and event.index == _touch_index:
				_touch_index = -1
				if not _touch_dragged:
					if get_confirmation_rect().has_point(event.position) and get_confirmation_rect().has_point(_touch_start):
						_confirm_action()
					elif not _detail_rect.has_point((event.position-global_position)/_scale):
						cancel_selection()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and event.index == _touch_index:
			_touch_dragged = _touch_dragged or event.position.distance_to(_touch_start) > 8.0
			if _description.get_global_rect().has_point(_touch_start):
				_description.get_v_scroll_bar().value -= event.relative.y
			get_viewport().set_input_as_handled()
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
	if selected_index >= 0:
		_draw_inspector()
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
	var transform := get_viewport().get_final_transform()
	var pixels_per_unit := maxf(0.01, _scale * minf(transform.x.length(), transform.y.length()))
	var title_size := _fit_label(str(data.title), maxi(roundi(13 * text_scale), ceili(9 / pixels_per_unit)), tag.size.x - 10)
	_text(str(data.title), Vector2(tag.get_center().x, tag.position.y + tag.size.y * 0.40), title_size, Color("c7cdd0"))
	if bool(data.owned):
		var title := "✓ 사용 중" if bool(data.equipped) else "보유 중"
		_text(title, Vector2(tag.get_center().x, tag.position.y + tag.size.y * 0.85), _fit_label(title,maxi(roundi(17 * text_scale),ceili(11 / pixels_per_unit)),tag.size.x-10), Color("d4d9d5"))
	else:
		var price := preload("res://scripts/game_balance.gd").gold_label(int(data.price))
		var price_size := _fit_label(price,maxi(roundi(18*text_scale),ceili(11 / pixels_per_unit)),tag.size.x-28*text_scale)
		var price_width := _bold.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, price_size).x
		var center := tag.get_center().x + 3 * text_scale
		var baseline := tag.position.y + tag.size.y * 0.85
		_coin(Vector2(center - price_width * 0.5 - 10 * text_scale, baseline - 6 * text_scale), 7 * text_scale)
		_text(price, Vector2(center + 3 * text_scale, baseline), price_size, GOLD)
	if active:
		draw_line(Vector2(tag.position.x, tag.end.y), tag.end, Color("dfb978"), 1.5, true)


func _draw_inspector() -> void:
	draw_rect(Rect2(Vector2.ZERO,_view),Color(0.02,0.03,0.03,0.95))
	var data: Dictionary = _catalog[selected_index]
	var r := _detail_rect
	_text(str(data.title),Vector2(r.get_center().x,r.position.y+27),_fit_label(str(data.title),26,r.size.x-32),GOLD)
	if is_instance_valid(_preview_viewport):
		draw_texture_rect(_preview_viewport.get_texture(),_hero_rect,false)
	var p := _text_origin
	var headline: String = data.headline if selected_kind == "aux" else "공격력 ×%s" % data.power
	var subtitle: String = data.subtitle if selected_kind == "aux" else "공격 속도 ×%s" % data.speed
	var text_width := r.end.x-p.x-16
	draw_string(_bold,p,headline,HORIZONTAL_ALIGNMENT_LEFT,-1,_fit_label(headline,19 if selected_kind == "aux" else 22,text_width),TEXT)
	draw_string(_font,p+Vector2(0,30),subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,_fit_label(subtitle,14 if selected_kind == "aux" else 17,text_width),Color("c2ccd0"))
	var footer := Vector2(p.x,r.end.y-30)
	if bool(data.equipped):
		draw_string(_bold,footer,"사용 중",HORIZONTAL_ALIGNMENT_LEFT,-1,19,GOLD)
	elif bool(data.owned):
		draw_string(_bold,footer,"장착",HORIZONTAL_ALIGNMENT_LEFT,-1,19,TEXT)
	else:
		_coin(footer+Vector2(10,-7),12)
		var price := preload("res://scripts/game_balance.gd").gold_label(int(data.price))
		draw_string(_bold,footer+Vector2(30,0),price,HORIZONTAL_ALIGNMENT_LEFT,-1,_fit_label(price,23,r.end.x-footer.x-88),GOLD)
		if _wallet < int(data.price):
			draw_string(_font,footer+Vector2(0,21),"Gold 부족",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("cb957e"))


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
