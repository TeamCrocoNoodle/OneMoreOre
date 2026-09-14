extends CanvasLayer
## Small model-backed actions and range-independent detector readout.
const Models = preload("res://scripts/tool_display_models.gd")
const Aux = preload("res://scripts/aux_tools.gd")
const GOLD := Color("dca75c")
class Canvas extends Control:
	var presenter: Node
	func _draw() -> void: presenter.draw_hud(self)

var game: Node3D
var runtime: Node3D
var canvas: Control
var buttons: Dictionary = {}
var icons: Dictionary = {}
var atlas: SubViewport
var font: SystemFont
var scale_factor := 1.0
var view := Vector2(1200,850)
var xray_rect := Rect2()
var detector_level := 0
var detector_point := Vector2.ZERO
var remaining_gems := 0
var _layout_signature := ""
var _draw_signature := ""

func _ready() -> void:
	layer = 16
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic","Apple SD Gothic Neo","Noto Sans CJK KR","sans-serif"])
	font.multichannel_signed_distance_field = true
	canvas = Canvas.new()
	canvas.presenter = self
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	for id: String in ["crusher","detonator"]:
		var button := Button.new()
		button.name = "AuxAction_"+id
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_override("font",font)
		for state: String in ["normal","hover","pressed","focus","disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.035,0.065,0.068,0.92) if state not in ["hover","pressed"] else Color("293b35")
			style.border_color = Color(GOLD,0.22 if state == "disabled" else 0.7)
			style.set_border_width_all(1)
			style.set_corner_radius_all(4)
			button.add_theme_stylebox_override(state,style)
		button.pressed.connect(func():
			if runtime.activate(id): button.release_focus()
		)
		canvas.add_child(button)
		var picture := TextureRect.new()
		picture.name = "EquipmentModel"
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(picture)
		var label := Label.new()
		label.name = "ActionLabel"
		label.add_theme_font_override("font",font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		buttons[id] = button
	get_viewport().size_changed.connect(_layout)

func setup(owner_game: Node3D, owner_runtime: Node3D) -> void:
	game = owner_game
	runtime = owner_runtime
	refresh()

func refresh() -> void:
	if not is_instance_valid(game): return
	var owned: bool = not game.aux_tools._owned.is_empty()
	if owned and not is_instance_valid(atlas): _build_atlas()
	visible = owned and game._round_allows_mining()
	if not visible: return
	for id: String in buttons:
		buttons[id].visible = game.aux_tools.is_owned(id)
		buttons[id].disabled = not runtime.can_activate(id)
		var label: Label = buttons[id].get_node("ActionLabel")
		label.text = ("분쇄  X" if game.using_controller else "분쇄  R") if id == "crusher" else (("사용 완료" if runtime.detonator_used else ("폭파  L3" if game.using_controller else "폭파  Space")))
		if id == "crusher" and runtime.crusher_remaining > 0:
			label.text = "분쇄 %ds" % ceili(runtime.crusher_remaining)
	_layout()
	remaining_gems = game.gems.size()
	detector_level = runtime.detector_level
	detector_point = game.aim_position/scale_factor+Vector2(-30,-32)
	var signature := "%s:%s:%s:%s:%s" % [remaining_gems,detector_level,detector_point,runtime.detector_valid,_layout_signature]
	if signature != _draw_signature:
		_draw_signature = signature
		canvas.queue_redraw()

func _layout() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.hud): return
	scale_factor = game.hud._scale
	view = game.hud._view
	var portrait: bool = game.hud._portrait
	var signature := "%s:%s:%s:%s:%s:%s:%s" % [scale_factor,view,portrait,game.hud._satchel_rect,buttons.crusher.disabled,buttons.detonator.disabled,icons.size()]
	if signature == _layout_signature: return
	_layout_signature = signature
	var base_y: float = game.hud._satchel_rect.position.y-82 if portrait else view.y-176
	var base_x := view.x-188 if portrait else 24.0
	for index in 2:
		var id: String = ["crusher","detonator"][index]
		var button: Button = buttons[id]
		button.position = Vector2(base_x+index*84,base_y)*scale_factor
		button.size = Vector2(78,70)*scale_factor
		var picture: TextureRect = button.get_node("EquipmentModel")
		picture.position = Vector2(16,2)*scale_factor
		picture.size = Vector2(46,46)*scale_factor
		if icons.has(id): picture.texture = icons[id]
		picture.modulate = Color(1,1,1,0.38 if button.disabled else 1.0)
		var label: Label = button.get_node("ActionLabel")
		label.position = Vector2(0,47)*scale_factor
		label.size = Vector2(78,20)*scale_factor
		label.add_theme_font_size_override("font_size",int(11*scale_factor))
		label.add_theme_color_override("font_color",Color("8b9290") if button.disabled else Color("ecdfc7"))
	xray_rect = Rect2(24,base_y-56,154,46)
	if not portrait and view.y < 640:
		# The left column already holds boss/combo status in short windows.
		xray_rect = Rect2(view.x-186,game.hud._satchel_rect.position.y-58,166,46)
	canvas.queue_redraw()

func action_rect(id: String) -> Rect2:
	return buttons[id].get_global_rect()

func is_pointer_blocked(point: Vector2) -> bool:
	if not visible: return false
	for button: Button in buttons.values():
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return true
	return game.aux_tools.is_owned("xray") and Rect2(xray_rect.position*scale_factor,xray_rect.size*scale_factor).has_point(point)

func draw_hud(c: Control) -> void:
	if not is_instance_valid(game) or not visible: return
	c.draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale_factor)
	if game.aux_tools.is_owned("xray"):
		c.draw_rect(xray_rect,Color(0.025,0.05,0.06,0.88))
		if icons.has("xray"): c.draw_texture_rect(icons.xray,Rect2(xray_rect.position,Vector2(46,46)),false)
		c.draw_string(font,xray_rect.position+Vector2(51,17),"원석 속",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("a5b6b7"))
		c.draw_string(font,xray_rect.position+Vector2(51,39),"%d  보석" % remaining_gems,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("d7efea"))
	if game.aux_tools.is_owned("detector") and runtime.detector_valid:
		var point := detector_point.clamp(Vector2(30,114),view-Vector2(30,42))
		c.draw_circle(point,2.5,Color("92e3b3") if detector_level > 0 else Color("758b8c"))
		for ring in 3:
			var color := Color("92e3b3") if ring < detector_level else Color(0.35,0.45,0.46,0.62)
			c.draw_arc(point,9+ring*7,-PI*0.79,-PI*0.21,13,color,3.0,true)
	c.draw_set_transform(Vector2.ZERO)

func _build_atlas() -> void:
	atlas = SubViewport.new()
	atlas.name = "AuxModelIconAtlas"
	atlas.size = Vector2i(1120,160)
	atlas.transparent_bg = true
	atlas.world_3d = World3D.new()
	atlas.msaa_3d = Viewport.MSAA_2X
	atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(atlas)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0,0,0,0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6dce2")
	env.ambient_light_energy = 0.72
	env_node.environment = env
	atlas.add_child(env_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 30.8
	camera.position = Vector3(0,0,8)
	camera.current = true
	atlas.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-30,0)
	light.light_energy = 1.0
	atlas.add_child(light)
	for index in Aux.CATALOG.size():
		var model := Models.create_preview(index,"aux")
		model.position.x = (index-3)*4.4
		atlas.add_child(model)
		var icon := AtlasTexture.new()
		icon.atlas = atlas.get_texture()
		icon.region = Rect2(index*160,0,160,160)
		icons[Aux.CATALOG[index].id] = icon
	RenderingServer.frame_post_draw.connect(canvas.queue_redraw,CONNECT_ONE_SHOT)
