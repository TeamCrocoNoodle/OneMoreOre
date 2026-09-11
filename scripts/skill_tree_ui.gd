extends CanvasLayer
## Skill graph presentation. Only the adjacent check button requests a purchase.

signal purchase_requested(id: String)
signal closed
signal cue(kind: String, tier: int)

const ToolDisplay = preload("res://scripts/tool_display.gd")
const ModelGallery = preload("res://scripts/ui_model_gallery.gd")
const GOLD := Color("dca75c")
const TEXT := Color("f4f4ef")
const MUTED := Color("a5a8a5")
const GRID_STEP := 132.0
const NODE_SIZE := 64.0
const CATEGORY_COLORS := {"health": Color("342c32"), "attack": Color("23303b"), "gold": Color("253932"), "ore": Color("352a23")}

class GraphCanvas extends Control:
	var presenter: Node
	func _draw() -> void:
		if is_instance_valid(presenter):
			presenter._draw_graph(self)

class HeaderCanvas extends Control:
	var presenter: Node
	func _draw() -> void:
		if is_instance_valid(presenter):
			presenter._draw_header(self)

var is_open := false
var model_gallery: Node
var selected_tab := "skills"
var tools_panel: Control
var selected_id := ""
var hovered_id := ""
var _focused_id := "origin"
var _model: RefCounted
var _gold := 0
var _canvas: GraphCanvas
var _header: HeaderCanvas
var _header_height := 82.0
var _tab_buttons: Dictionary = {}
var _font: SystemFont
var _bold: SystemFont
var _confirm: Button
var _close: Button
var _detail_blocker: Control
var _buttons: Dictionary = {}
var _nodes: Array[Dictionary] = []
var _node_rects: Dictionary = {}
var _visible_ids: Array[String] = []
var _known_owned: Dictionary = {}
var _pulses: Dictionary = {}
var _scale := 1.0
var _view := Vector2(1440, 1000)
var _graph_center := Vector2.ZERO
var _pan := Vector2.ZERO
var _zoom := 1.0
var _user_view := false
var _detail_id := ""
var _detail_rect := Rect2()
var _detail_lines: Array[String] = []
var _confirm_rect := Rect2()
var _dragging := false
var _drag_last := Vector2.ZERO
var _touch_id := -1
var _using_controller := false
var _purchase_pending := false
var _hover_pin := ""
var _pointer_position := Vector2.INF
var _hover_pin_position := Vector2.INF


func _ready() -> void:
	layer = 30
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "sans-serif"])
	_font.multichannel_signed_distance_field = true
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_bold.multichannel_signed_distance_field = true
	_canvas = GraphCanvas.new()
	_canvas.presenter = self
	_canvas.name = "SkillTree"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_background_input)
	add_child(_canvas)
	if model_gallery == null:
		model_gallery = ModelGallery.new()
		add_child(model_gallery)
	model_gallery.visuals_ready.connect(_redraw_model_icons)
	model_gallery.ensure_ready()
	tools_panel = ToolDisplay.new()
	tools_panel.name = "ToolsDisplay"
	tools_panel.model_gallery = model_gallery
	_canvas.add_child(tools_panel)
	_header = HeaderCanvas.new()
	_header.presenter = self
	_header.name = "UpgradeNavigation"
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(func(event: InputEvent):
		if _is_pointer_press(event):
			hovered_id = ""
			_hover_pin = ""
			_cancel_selection()
	)
	_canvas.add_child(_header)
	_detail_blocker = Control.new()
	_detail_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_blocker.gui_input.connect(func(event: InputEvent):
		if _is_pointer_press(event):
			_cancel_selection()
	)
	_canvas.add_child(_detail_blocker)
	_confirm = _button("✓")
	_confirm.name = "ConfirmSkillPurchase"
	_confirm.pressed.connect(_confirm_purchase)
	_close = _button("닫기 ×")
	_close.name = "CloseSkillTree"
	_close.pressed.connect(close_tree)
	_close.reparent(_header)
	for id in ["skills", "tools"]:
		var tab := _button("스킬 트리" if id == "skills" else "도구")
		tab.name = "UpgradeTab_" + id
		tab.reparent(_header)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			tab.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		tab.pressed.connect(select_tab.bind(id))
		tab.focus_entered.connect(_header.queue_redraw)
		tab.focus_exited.connect(_header.queue_redraw)
		_tab_buttons[id] = tab
	_refresh_tabs()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_canvas.hide()
	_confirm.hide()
	_detail_blocker.hide()
	tools_panel.set_display_open(false)
	set_process(false)
	set_process_input(false)


func _redraw_model_icons() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()
	if is_instance_valid(_header):
		_header.queue_redraw()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.03, 0.03, 0.94)
		style.border_color = Color(GOLD, 0.45)
		style.set_corner_radius_all(5)
		style.set_border_width_all(1)
		if state == "hover":
			style.bg_color = Color("34342b")
		if state == "pressed":
			style.bg_color = Color("494331")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = GOLD
			style.set_border_width_all(2)
		if state == "disabled":
			style.border_color = Color(0.5, 0.5, 0.5, 0.3)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("777b76"))
	_canvas.add_child(button)
	return button


func setup(model: RefCounted) -> void:
	_model = model
	_nodes = model.get_nodes()
	for node in _nodes:
		var id := str(node.id)
		if _buttons.has(id):
			continue
		var button := Button.new()
		button.name = "Skill_" + id
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_choose_node.bind(id))
		button.mouse_entered.connect(_hover_node.bind(id))
		button.mouse_exited.connect(_leave_node.bind(id))
		button.focus_entered.connect(_focus_node.bind(id))
		_canvas.add_child(button)
		_buttons[id] = button
	_canvas.move_child(_detail_blocker, -1)
	_canvas.move_child(_confirm, -1)
	_canvas.move_child(_header, -1)
	refresh(_gold)


func select_tab(id: String) -> void:
	if id not in ["skills", "tools"] or selected_tab == id:
		return
	selected_tab = id
	selected_id = ""
	hovered_id = ""
	_hover_pin = ""
	_purchase_pending = false
	_dragging = false
	_touch_id = -1
	for node_id in _buttons:
		_buttons[node_id].visible = selected_tab == "skills" and node_id in _visible_ids
	_refresh_detail()
	_refresh_tabs()
	tools_panel.set_display_open(is_open and selected_tab == "tools")
	if is_open:
		if _using_controller:
			if selected_tab == "tools":
				tools_panel.focus_first()
			elif _buttons.has(_focused_id):
				_buttons[_focused_id].grab_focus()
		else:
			_tab_buttons[selected_tab].grab_focus()
		cue.emit("confirm", 0)
	_canvas.queue_redraw()


func get_tab_rect(id: String) -> Rect2:
	return _tab_buttons[id].get_global_rect() if _tab_buttons.has(id) else Rect2()


func _refresh_tabs() -> void:
	for id in _tab_buttons:
		var color: Color = TEXT if selected_tab == id else MUTED
		_tab_buttons[id].add_theme_color_override("font_color", color)
		_tab_buttons[id].add_theme_color_override("font_hover_color", TEXT)
		_tab_buttons[id].add_theme_color_override("font_focus_color", TEXT)
	if is_instance_valid(_header):
		_header.queue_redraw()


func open_tree(gold: int) -> void:
	if _model == null:
		return
	is_open = true
	selected_id = ""
	hovered_id = ""
	_focused_id = "origin"
	_purchase_pending = false
	_using_controller = false
	_user_view = false
	_pan = Vector2.ZERO
	_canvas.show()
	set_process(true)
	set_process_input(true)
	refresh(gold)
	_fit_graph()
	_layout_nodes()
	tools_panel.set_display_open(selected_tab == "tools")
	if selected_tab == "skills" and _buttons.has("origin"):
		_buttons.origin.grab_focus()
	else:
		_tab_buttons[selected_tab].grab_focus()
	cue.emit("confirm", 0)


func close_tree() -> void:
	if not is_open:
		return
	is_open = false
	selected_id = ""
	hovered_id = ""
	_dragging = false
	_touch_id = -1
	_canvas.hide()
	_confirm.hide()
	tools_panel.set_display_open(false)
	set_process(false)
	set_process_input(false)
	closed.emit()


func refresh(gold: int) -> void:
	_gold = maxi(gold, 0)
	if _model == null:
		return
	var previous_visible := _visible_ids.duplicate()
	_visible_ids.clear()
	var purchased := false
	for node in _nodes:
		var id := str(node.id)
		var available: bool = _model.is_visible(id)
		_buttons[id].visible = available and selected_tab == "skills"
		_buttons[id].disabled = not available
		if available:
			_visible_ids.append(id)
			if is_open and not previous_visible.is_empty() and not id in previous_visible:
				_pulses[id] = 1.0
		if _model.is_unlocked(id):
			if not _known_owned.has(id) and id != "origin" and is_open:
				_pulses[id] = 1.0
				purchased = true
			_known_owned[id] = true
	if not selected_id.is_empty() and _model.is_unlocked(selected_id):
		selected_id = ""
	_purchase_pending = false
	if not _user_view:
		_fit_graph()
	_layout_nodes()
	_header.queue_redraw()
	if purchased:
		set_process(true)
		if selected_tab == "skills" and _using_controller and _buttons.has(_focused_id):
			_buttons[_focused_id].grab_focus()
		cue.emit("pickup", 3)


func get_node_screen(id: String) -> Vector2:
	# Hidden coordinates are stable for tests; they never create a hit target.
	var node: Dictionary = _model.get_node(id) if _model != null else {}
	if node.is_empty():
		return Vector2.INF
	return (_graph_center + _pan + Vector2(node.grid) * GRID_STEP * _zoom) * _scale


func get_confirmation_rect() -> Rect2:
	return Rect2(_confirm_rect.position * _scale, _confirm_rect.size * _scale) if is_instance_valid(_confirm) and _confirm.visible else Rect2()


func get_detail_rect() -> Rect2:
	return Rect2(_detail_rect.position * _scale, _detail_rect.size * _scale) if not _detail_id.is_empty() else Rect2()


func get_visible_node_ids() -> Array[String]:
	return _visible_ids.duplicate()


func _layout() -> void:
	if not is_instance_valid(_canvas):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var transform := get_viewport().get_final_transform()
	var screen_factor := maxf(minf(transform.x.length(), transform.y.length()), 0.001)
	var physical := viewport_size * screen_factor
	var physical_scale := clampf(minf(physical.x / 1200.0, physical.y / 850.0), 0.85, 1.25)
	_scale = physical_scale / screen_factor
	_view = viewport_size / _scale
	var narrow := _view.x < 760
	_header_height = 126 if narrow else 82
	_header.position = Vector2.ZERO
	_header.size = Vector2(_view.x, _header_height) * _scale
	_graph_center = Vector2(_view.x * 0.5, (_view.y - 70) * 0.5 + (22 if narrow else 0))
	_close.position = Vector2(_view.x - (80 if narrow else 120), 8 if narrow else 12) * _scale
	_close.size = Vector2(58 if narrow else 98, 58) * _scale
	_close.text = "×" if narrow else "닫기 ×"
	_close.add_theme_font_size_override("font_size", int((27 if narrow else 17) * _scale))
	var tab_y := 66.0 if narrow else 12.0
	var tab_width := 142.0 if narrow else 152.0
	var tab_gap := 18.0 if narrow else 24.0
	var tab_start := (_view.x - tab_width * 2 - tab_gap) * 0.5
	for index in 2:
		var id: String = ["skills", "tools"][index]
		_tab_buttons[id].position = Vector2(tab_start + index * (tab_width + tab_gap), tab_y) * _scale
		_tab_buttons[id].size = Vector2(tab_width, 58) * _scale
		_tab_buttons[id].add_theme_font_size_override("font_size", int(21 * _scale))
	var content_top := _header_height + 22
	tools_panel.set_layout(Rect2(Vector2(22, content_top) * _scale, Vector2(maxf(_view.x - 44, 1), maxf(_view.y - content_top - 22, 1)) * _scale), _scale)
	_header.queue_redraw()
	_confirm.add_theme_font_size_override("font_size", int(29 * _scale))
	if not _user_view:
		_fit_graph()
	_layout_nodes()


func _fit_graph() -> void:
	if _model == null or _visible_ids.is_empty():
		return
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	var first := true
	for id in _visible_ids:
		var node: Dictionary = _model.get_node(id)
		var point := Vector2(node.grid) * GRID_STEP
		if first:
			bounds = Rect2(point, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(point)
	var footprint := bounds.size + Vector2.ONE * (NODE_SIZE + 26)
	_zoom = clampf(minf((_view.x - 56) / maxf(footprint.x, 1), (_view.y - 256) / maxf(footprint.y, 1)), 0.55, 1.0)
	_pan = -bounds.get_center() * _zoom


func _layout_nodes() -> void:
	var inspected := selected_id if not selected_id.is_empty() else (hovered_id if not hovered_id.is_empty() else (_focused_id if _using_controller else ""))
	if selected_tab == "skills" and _model != null and not inspected.is_empty():
		_ensure_detail_space(inspected)
	for id in _buttons:
		var center := get_node_screen(id) / _scale
		var visual_size := maxf(52, NODE_SIZE * _zoom)
		_node_rects[id] = Rect2(center - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size)
		var hit_size := maxf(58, visual_size)
		_buttons[id].position = (center - Vector2.ONE * hit_size * 0.5) * _scale
		_buttons[id].size = Vector2.ONE * hit_size * _scale
	_refresh_detail()
	_canvas.queue_redraw()


func _choose_node(id: String) -> void:
	if not is_open or selected_tab != "skills" or not _model.is_visible(id):
		return
	if not selected_id.is_empty():
		_cancel_selection()
		return
	_focused_id = id
	hovered_id = "" if _using_controller else id
	if _ensure_detail_space(id):
		_layout_nodes()
	if _model.is_unlocked(id):
		_refresh_detail()
		return
	selected_id = id
	_purchase_pending = false
	if _ensure_detail_space(id):
		_layout_nodes()
	_refresh_detail()
	if not _confirm.disabled:
		_confirm.grab_focus()
	cue.emit("confirm", 0)


func _confirm_purchase() -> void:
	if not is_open or selected_tab != "skills" or selected_id.is_empty() or _purchase_pending or not _model.can_purchase(selected_id, _gold):
		return
	_purchase_pending = true
	_confirm.disabled = true
	purchase_requested.emit(selected_id)


func _cancel_selection() -> void:
	selected_id = ""
	_purchase_pending = false
	_refresh_detail()
	if selected_tab == "skills" and _using_controller and _buttons.has(_focused_id):
		_buttons[_focused_id].grab_focus()


func _hover_node(id: String) -> void:
	if not is_open or selected_tab != "skills" or _dragging:
		return
	_using_controller = false
	hovered_id = id
	if _ensure_detail_space(id):
		# Keep the inspected detail stable during a small automatic upward pan;
		# the next real pointer motion resumes ordinary hover hit testing.
		_hover_pin = id
		_hover_pin_position = _pointer_position
		_layout_nodes()
	_refresh_detail()


func _leave_node(id: String) -> void:
	if id == _hover_pin:
		return
	if hovered_id == id and _buttons[id].get_global_rect().has_point(_pointer_position):
		return
	if hovered_id == id:
		hovered_id = ""
		_refresh_detail()


func _focus_node(id: String) -> void:
	if selected_tab != "skills":
		return
	_focused_id = id
	_refresh_detail()


func _ensure_detail_space(id: String) -> bool:
	var node: Dictionary = _model.get_node(id)
	if node.is_empty():
		return false
	var width := minf(324, _view.x - 32)
	var height := 72 + _wrap_text(str(node.description), 15, width - 32).size() * 23
	var point := get_node_screen(id) / _scale
	var moved := false
	var top := _header_height + maxf(29, NODE_SIZE * _zoom * 0.5) + 44
	if point.y < top:
		_pan.y += top - point.y
		point.y = top
		moved = true
	var extra := 0.0
	if selected_id == id and bool(_confirmation_placement(id).below):
		extra = 66.0
	var bottom := point.y + maxf(29, NODE_SIZE * _zoom * 0.5) + 16 + extra + height + 18
	if bottom <= _view.y:
		return moved
	_pan.y -= bottom - _view.y
	return true


func _confirmation_placement(id: String) -> Dictionary:
	var point := get_node_screen(id) / _scale
	var half := maxf(29, NODE_SIZE * _zoom * 0.5)
	var allowed := Rect2(12, _header_height + 2, _view.x - 24, _view.y - _header_height - 14)
	for x: float in [point.x + half + 10, point.x - half - 68]:
		var candidate := Rect2(Vector2(x, point.y - 29), Vector2(58, 58))
		if not allowed.encloses(candidate):
			continue
		var blocked := false
		for other in _visible_ids:
			if other == id:
				continue
			var other_center := get_node_screen(other) / _scale
			var hit_size := maxf(58, NODE_SIZE * _zoom)
			var hit_rect := Rect2(other_center - Vector2.ONE * hit_size * 0.5, Vector2.ONE * hit_size)
			if candidate.intersects(hit_rect.grow(2)):
				blocked = true
				break
		if not blocked:
			return {"rect": candidate, "below": false}
	return {"rect": Rect2(Vector2(clampf(point.x - 29, 12, _view.x - 70), point.y + half + 10), Vector2(58, 58)), "below": true}


func _refresh_detail() -> void:
	_detail_id = selected_id if not selected_id.is_empty() else (hovered_id if not hovered_id.is_empty() else (_focused_id if _using_controller else ""))
	if selected_tab != "skills" or _detail_id.is_empty() or _model == null or not _model.is_visible(_detail_id):
		_detail_id = ""
		_confirm.hide()
		_detail_blocker.hide()
		_canvas.queue_redraw()
		return
	var node: Dictionary = _model.get_node(_detail_id)
	var width := minf(324, _view.x - 32)
	_detail_lines = _wrap_text(str(node.description), 15, width - 32)
	var height := 72 + _detail_lines.size() * 23
	var center := get_node_screen(_detail_id) / _scale
	var half := maxf(29, NODE_SIZE * _zoom * 0.5)
	var x := clampf(center.x - width * 0.5, 16, _view.x - width - 16)
	var y := center.y + half + 16
	var confirmation: Dictionary = _confirmation_placement(_detail_id) if not selected_id.is_empty() else {}
	if not confirmation.is_empty() and bool(confirmation.below):
		y = Rect2(confirmation.rect).end.y + 14
	_detail_rect = Rect2(x, y, width, height)
	_detail_blocker.position = _detail_rect.position * _scale
	_detail_blocker.size = _detail_rect.size * _scale
	_detail_blocker.show()
	if not selected_id.is_empty():
		_confirm_rect = confirmation.rect
		_confirm.position = _confirm_rect.position * _scale
		_confirm.size = _confirm_rect.size * _scale
		_confirm.disabled = _purchase_pending or not _model.can_purchase(selected_id, _gold)
		_confirm.show()
	else:
		_confirm.hide()
	_canvas.queue_redraw()


func _wrap_text(value: String, size: int, width: float) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var candidate := word if line.is_empty() else line + " " + word
			if not line.is_empty() and _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				lines.append(line)
				line = word
			else:
				line = candidate
		lines.append(line)
	return lines


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if _tab_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if selected_tab == "skills" and not selected_id.is_empty():
			_cancel_selection()
		else:
			close_tree()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("ui_cancel"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_using_controller = false
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		_using_controller = true
		if get_viewport().gui_get_focus_owner() == null:
			_tab_buttons["tools" if event.is_action_pressed("ui_focus_prev") else "skills"].grab_focus()
			get_viewport().set_input_as_handled()
			return
	if selected_tab == "tools":
		# The display owns scrolling and native item/button keyboard navigation.
		return
	if event is InputEventMouseMotion:
		_pointer_position = event.position
		var pinned := not _hover_pin.is_empty() and _pointer_position.distance_squared_to(_hover_pin_position) < 1.0
		if not pinned and not _dragging:
			_hover_pin = ""
			hovered_id = ""
			for id in _visible_ids:
				if event.position.y >= _header_height * _scale and _buttons[id].get_global_rect().has_point(event.position):
					hovered_id = id
					break
			if selected_id.is_empty() and not hovered_id.is_empty() and _ensure_detail_space(hovered_id):
				_hover_pin = hovered_id
				_hover_pin_position = _pointer_position
				_layout_nodes()
			_refresh_detail()
	if event.is_action_pressed("ui_accept"):
		_using_controller = true
		if _close.has_focus():
			close_tree()
		elif _tab_buttons.skills.has_focus() or _tab_buttons.tools.has_focus():
			select_tab("skills" if _tab_buttons.skills.has_focus() else "tools")
		elif not selected_id.is_empty():
			_confirm_purchase()
		else:
			_choose_node(_focused_id)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept") or event.is_action_released("ui_cancel"):
		get_viewport().set_input_as_handled()
	else:
		for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			if event.is_action_pressed(action):
				_using_controller = true
				if _close.has_focus() or _tab_buttons.skills.has_focus() or _tab_buttons.tools.has_focus():
					if action == "ui_down":
						_buttons[_focused_id].grab_focus()
						_refresh_detail()
						get_viewport().set_input_as_handled()
					return
				_move_focus(Vector2.LEFT if action == "ui_left" else (Vector2.RIGHT if action == "ui_right" else (Vector2.UP if action == "ui_up" else Vector2.DOWN)))
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(event.position / _scale, 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif event is InputEventPanGesture:
			_cancel_selection()
			_pan -= event.delta * 18.0
			_user_view = true
			_layout_nodes()
			get_viewport().set_input_as_handled()
		elif event is InputEventMagnifyGesture:
			_zoom_at(event.position / _scale, event.factor)
			get_viewport().set_input_as_handled()


func _tab_shortcut(event: InputEvent) -> bool:
	var cycle := false
	if event is InputEventKey and (event.keycode in [KEY_Q, KEY_E] or event.physical_keycode in [KEY_Q, KEY_E]):
		cycle = event.pressed and not event.echo
	elif event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		cycle = event.pressed
	else:
		return false
	if cycle:
		_using_controller = true
		select_tab("tools" if selected_tab == "skills" else "skills")
	return true


func _move_focus(direction: Vector2) -> void:
	if not selected_id.is_empty():
		_cancel_selection()
	var origin := get_node_screen(_focused_id) / _scale
	var best := ""
	var best_score := INF
	for id in _visible_ids:
		if id == _focused_id:
			continue
		var offset := get_node_screen(id) / _scale - origin
		if offset.dot(direction) <= 2:
			continue
		var score := offset.length() * (1.0 + (1.0 - offset.normalized().dot(direction)) * 1.5)
		if score < best_score:
			best = id
			best_score = score
	if not best.is_empty():
		_focused_id = best
		var point := get_node_screen(best) / _scale
		var safe := Rect2(64, _header_height + 46, maxf(_view.x - 128, 1), maxf(_view.y - _header_height - 244, 1))
		_pan += point.clamp(safe.position, safe.end) - point
		_layout_nodes()
		_buttons[best].grab_focus()
	_refresh_detail()


func _zoom_at(point: Vector2, factor: float) -> void:
	_cancel_selection()
	var next := clampf(_zoom * factor, 0.55, 1.55)
	_pan = point - _graph_center - (point - _graph_center - _pan) * next / _zoom
	_zoom = next
	_user_view = true
	_layout_nodes()


func _background_input(event: InputEvent) -> void:
	if not is_open or selected_tab != "skills":
		return
	if _is_pointer_press(event):
		if not selected_id.is_empty():
			_hover_pin = ""
			hovered_id = ""
			_cancel_selection()
			return
		hovered_id = ""
		_using_controller = false
		_dragging = true
		_drag_last = event.position / _scale
		_touch_id = event.index if event is InputEventScreenTouch else -1
		_refresh_detail()
	elif event is InputEventMouseButton and not event.pressed:
		_dragging = false
	elif event is InputEventScreenTouch and not event.pressed and event.index == _touch_id:
		_dragging = false
		_touch_id = -1
	elif _dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		var point: Vector2 = event.position / _scale
		_pan += point - _drag_last
		_drag_last = point
		_user_view = true
		_layout_nodes()


func _is_pointer_press(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]) or (event is InputEventScreenTouch and event.pressed)


func _process(delta: float) -> void:
	if not is_open or _pulses.is_empty():
		return
	for id in _pulses.keys():
		_pulses[id] = maxf(float(_pulses[id]) - delta * 1.8, 0)
		if _pulses[id] <= 0:
			_pulses.erase(id)
	if selected_tab == "skills":
		_canvas.queue_redraw()


func _draw_header(c: Control) -> void:
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _scale)
	c.draw_rect(Rect2(0, 0, _view.x, _header_height), Color("090d0e"))
	c.draw_line(Vector2(0, _header_height), Vector2(_view.x, _header_height), Color(1, 1, 1, 0.055), 1)
	var narrow := _view.x < 760
	_text(c, "업그레이드", Vector2(24, 45 if narrow else 49), 20 if narrow else 23, TEXT)
	var wallet_text := _number(_gold)
	var wallet_size := 20
	var wallet_width := _bold.get_string_size(wallet_text, HORIZONTAL_ALIGNMENT_LEFT, -1, wallet_size).x
	var wallet_right := _view.x - (99 if narrow else 142)
	var wallet_left: float = 156.0 if narrow else _tab_buttons.tools.get_rect().end.x / _scale + 40
	var wallet_available := maxf(wallet_right - wallet_left, 36)
	while wallet_size > 13 and wallet_width > wallet_available:
		wallet_size -= 1
		wallet_width = _bold.get_string_size(wallet_text, HORIZONTAL_ALIGNMENT_LEFT, -1, wallet_size).x
	var wallet_y := 38.0 if narrow else 42.0
	_coin(c, Vector2(wallet_right - wallet_width - 17, wallet_y), 11.5)
	_text(c, wallet_text, Vector2(wallet_right, wallet_y + 7), wallet_size, GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	if _tab_buttons.has(selected_tab):
		var tab_rect: Rect2 = _tab_buttons[selected_tab].get_rect()
		var center := tab_rect.get_center() / _scale
		var width := 88.0 if selected_tab == "skills" else 46.0
		c.draw_rect(Rect2(center.x - width * 0.5, tab_rect.end.y / _scale - 2, width, 2), GOLD)
	for id in _tab_buttons:
		if id == selected_tab or not _tab_buttons[id].has_focus():
			continue
		var tab_rect: Rect2 = _tab_buttons[id].get_rect()
		var center := tab_rect.get_center() / _scale
		var width := 88.0 if id == "skills" else 46.0
		c.draw_rect(Rect2(center.x - width * 0.5, tab_rect.end.y / _scale - 2, width, 1), Color(GOLD, 0.48))
	c.draw_set_transform(Vector2.ZERO)


func _draw_graph(c: Control) -> void:
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _scale)
	c.draw_rect(Rect2(Vector2.ZERO, _view), Color("101617"))
	if selected_tab != "skills":
		c.draw_set_transform(Vector2.ZERO)
		return
	_text(c, "끌어서 이동 · 스크롤로 확대", Vector2(28, _header_height + 27), 13, MUTED, false)
	if _model != null:
		for edge: Array in _model.get_edges():
			if not _model.is_visible(edge[0]) or not _model.is_visible(edge[1]):
				continue
			var a := get_node_screen(edge[0]) / _scale
			var b := get_node_screen(edge[1]) / _scale
			var owned: bool = _model.is_unlocked(edge[0]) and _model.is_unlocked(edge[1])
			c.draw_line(a, b, Color(GOLD, 0.92 if owned else 0.42), 2 if owned else 1.4, true)
		for id in _visible_ids:
			_draw_node(c, id)
	if not _detail_id.is_empty():
		_draw_detail(c)
	c.draw_set_transform(Vector2.ZERO)


func _draw_node(c: Control, id: String) -> void:
	var node: Dictionary = _model.get_node(id)
	var r: Rect2 = _node_rects[id]
	var owned: bool = _model.is_unlocked(id)
	var highlighted := id == _detail_id
	var pulse := float(_pulses.get(id, 0))
	var color: Color = CATEGORY_COLORS.get(str(node.category), Color("293238"))
	if owned:
		color = Color("192020")
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = GOLD if owned or highlighted else GOLD.darkened(0.45)
	style.set_border_width_all(2 if highlighted or owned else 1)
	style.set_corner_radius_all(5)
	c.draw_style_box(style, r)
	if pulse > 0:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(GOLD, pulse * 0.08)
		glow.border_color = Color(GOLD, pulse * 0.75)
		glow.set_border_width_all(2)
		glow.set_corner_radius_all(6)
		c.draw_style_box(glow, r.grow((1 - pulse) * 12 + 3))
	_draw_icon(c, str(node.icon), r.get_center(), r.size.x * 0.30, TEXT if owned or highlighted else GOLD.darkened(0.08))
	if owned and id != "origin":
		_text(c, "✓", r.end - Vector2(3, 3), 12, GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_detail(c: Control) -> void:
	var node: Dictionary = _model.get_node(_detail_id)
	var point := get_node_screen(_detail_id) / _scale
	var owned: bool = _model.is_unlocked(_detail_id)
	var affordable: bool = _model.can_purchase(_detail_id, _gold)
	var cost_y := point.y - Rect2(_node_rects[_detail_id]).size.y * 0.5 - 18
	var cost := "습득 완료" if owned else _number(int(node.cost))
	var cost_width := _bold.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var cost_color := GOLD if affordable or owned else Color("bf8073")
	var cost_r := Rect2(point.x - cost_width * 0.5 - 24, cost_y - 19, cost_width + 42, 29)
	c.draw_rect(cost_r, Color(0.025, 0.035, 0.035, 0.94))
	if not owned:
		_coin(c, Vector2(point.x - cost_width * 0.5 - 11, cost_y - 5), 10.5, Color.WHITE if affordable else Color(0.70, 0.70, 0.70))
	_text(c, cost, Vector2(point.x + (0 if owned else 6), cost_y + 1), 17, cost_color, true, HORIZONTAL_ALIGNMENT_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.045, 0.98)
	style.border_color = Color(GOLD, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	c.draw_style_box(style, _detail_rect)
	_text(c, str(node.title), _detail_rect.position + Vector2(16, 29), 19, TEXT)
	for i in _detail_lines.size():
		_text(c, _detail_lines[i], _detail_rect.position + Vector2(16, 56 + i * 23), 15, MUTED, false)
	var status := "습득 완료" if owned else ("확인 표시를 눌러 구매" if affordable else "Gold가 부족합니다")
	_text(c, status, Vector2(_detail_rect.position.x + 16, _detail_rect.end.y - 15), 13, GOLD if affordable or owned else Color("bf8073"), false)


func _draw_icon(c: Control, id: String, p: Vector2, radius: float, color: Color) -> void:
	match id:
		"vitality", "recovery":
			var heart := PackedVector2Array([Vector2(0, 0.76), Vector2(-0.85, -0.05), Vector2(-0.83, -0.52), Vector2(-0.48, -0.76), Vector2(-0.14, -0.65), Vector2(0, -0.40), Vector2(0.14, -0.65), Vector2(0.48, -0.76), Vector2(0.83, -0.52), Vector2(0.85, -0.05)])
			_polygon(c, heart, p + Vector2(-0.15, 0) * radius, radius * 0.85, color)
			if id == "vitality":
				_arrow(c, p + Vector2(0.70, 0.26) * radius, radius * 0.62, color)
			else:
				_diamond(c, p + Vector2(0.69, 0.30) * radius, radius * 0.38, TEXT)
				_line(c, [Vector2(0.6, -0.74), Vector2(0.6, -0.20)], p, radius, color, 2)
				_line(c, [Vector2(0.33, -0.47), Vector2(0.87, -0.47)], p, radius, color, 2)
		"power", "speed", "reach":
			_pickaxe(c, p, radius * 0.95, color)
			if id == "power":
				_arrow(c, p + Vector2(0.68, 0.44) * radius, radius * 0.55, color)
			elif id == "speed":
				for i in 3:
					_line(c, [Vector2(-1.00, -0.20 + i * 0.30), Vector2(-0.50 + i * 0.07, -0.20 + i * 0.30)], p, radius, color, 2)
			else:
				for i in 4:
					c.draw_arc(p, radius * 1.03, TAU * i / 4 + 0.15, TAU * i / 4 + 0.80, 6, color, 2, true)
		"appraisal":
			_coin(c, p + Vector2(-0.30, 0.35) * radius, maxf(10.5, radius * 0.58))
			_diamond(c, p + Vector2(-0.28, -0.39) * radius, radius * 0.64, color)
			_arrow(c, p + Vector2(0.64, 0.12) * radius, radius * 0.94, color)
		"rich_ore", "soft_ore", "origin":
			_polygon(c, PackedVector2Array([Vector2(-0.94, -0.30), Vector2(-0.34, -0.89), Vector2(0.59, -0.69), Vector2(0.98, 0.32), Vector2(0.29, 0.83), Vector2(-0.68, 0.61)]), p, radius, Color(color, 0.55))
			if id == "rich_ore":
				_diamond(c, p + Vector2(0.14, -0.03) * radius, radius * 0.70, color)
			elif id == "soft_ore":
				_line(c, [Vector2(-0.12, -0.87), Vector2(0.21, -0.30), Vector2(-0.32, 0.10), Vector2(0.12, 0.39), Vector2(-0.10, 0.84)], p, radius, TEXT, 2.5)
			else:
				_pickaxe(c, p + Vector2(0, -0.07) * radius, radius * 1.02, color)


func _pickaxe(c: Control, p: Vector2, r: float, color: Color) -> void:
	_line(c, [Vector2(-0.53, 0.78), Vector2(0.30, -0.34)], p, r, color, 4)
	_polygon(c, PackedVector2Array([Vector2(-0.69, -0.47), Vector2(-0.13, -0.76), Vector2(0.39, -0.58), Vector2(0.80, -0.02), Vector2(0.35, -0.30), Vector2(-0.15, -0.43)]), p, r, color)


func _arrow(c: Control, p: Vector2, r: float, color: Color) -> void:
	_line(c, [Vector2(0, 0.64), Vector2(0, -0.66)], p, r, color, 2.5)
	_line(c, [Vector2(-0.38, -0.26), Vector2(0, -0.66), Vector2(0.38, -0.26)], p, r, color, 2.5)


func _diamond(c: Control, p: Vector2, r: float, color: Color) -> void:
	# These three symbols identify actual gem rewards; sparkle drawings remain
	# procedural elsewhere, while the crystal matches the common in-world gem.
	model_gallery.draw_gem(c, p, maxf(10.5, r), 0, Color(1, 1, 1, color.a))


func _coin(c: Control, p: Vector2, r: float, tint: Color = Color.WHITE) -> void:
	model_gallery.draw_coin(c, p, r, tint)


func _line(c: Control, points: Array, center: Vector2, radius: float, color: Color, width: float) -> void:
	var transformed := PackedVector2Array()
	for point: Vector2 in points:
		transformed.append(center + point * radius)
	c.draw_polyline(transformed, color, width, true)


func _polygon(c: Control, points: PackedVector2Array, center: Vector2, radius: float, color: Color) -> void:
	var transformed := PackedVector2Array()
	for point in points:
		transformed.append(center + point * radius)
	c.draw_colored_polygon(transformed, color)


func _text(c: Control, value: String, baseline: Vector2, size: int, color: Color, bold: bool = true, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = _bold if bold else _font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = baseline.x - (width * 0.5 if alignment == HORIZONTAL_ALIGNMENT_CENTER else (width if alignment == HORIZONTAL_ALIGNMENT_RIGHT else 0))
	c.draw_string(font, Vector2(x, baseline.y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _number(value: int) -> String:
	var source := str(maxi(0, value))
	var output := ""
	for i in source.length():
		if i > 0 and (source.length() - i) % 3 == 0:
			output += ","
		output += source[i]
	return output
