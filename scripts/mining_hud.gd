extends CanvasLayer
## Presentation only. The round ledger owns collection, prices, and payment.

signal next_round_requested
signal cue(kind: String, tier: int)
signal settlement_animation_finished
signal upgrades_requested
signal auction_requested
signal auction_animation_finished

const Rarity = preload("res://scripts/gem_rarity.gd")
const RARITY_NAMES := Rarity.LABELS
const GEM_COLORS := Rarity.COLORS
const TEXT := Color("f4f4ef")
const MUTED := Color("a5a8a5")
const GOLD := Color("dca75c")
const BAR_COLOR := Color("df9b41")
const ModelGallery = preload("res://scripts/ui_model_gallery.gd")
const AuctionUI = preload("res://scripts/auction_ui.gd")

class HudCanvas extends Control:
	var presenter: Node
	func _draw() -> void:
		if is_instance_valid(presenter):
			presenter._draw_hud(self)

var model_gallery: Node
var _canvas: HudCanvas
var _font: SystemFont
var _bold: SystemFont
var _replay: Button
var _skip: Button
var _upgrades: Button
var _auction: Button
var auction_ui: Control
var _auction_available := false
var _upgrades_available := false
var _scale := 1.0
var _view := Vector2(1440, 1000)
var _portrait := false
var _timer_rect := Rect2()
var _wallet_rect := Rect2()
var _satchel_rect := Rect2()
var _gem_cards: Array[Rect2] = []
var _modal_rect := Rect2()
var _compact_settlement := false
var _row_rects: Array[Rect2] = []
var _total_rect := Rect2()
var _info_rect := Rect2()
var _hero_center := Vector2.ZERO
var _hero_radius := 68.0
var _hero_caption_y := 0.0
var _remaining := 30.0
var _duration := 30.0
var _active := true
var _wallet := 0
var _stones := 0
var _counts := Rarity.empty_counts()
var _round_index := 1
var _gem_pulses := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
var _stone_pulse := 0.0
var _clock := 0.0
var _countdown_second := -1
var _countdown_pulse := 0.0
var _modal := false
var _report: Dictionary = {}
var _rows: Array[Dictionary] = []
var _settlement_time := 0.0
var _row_progress := PackedFloat32Array()
var _shown_total := 0
var _row_cued := -1
var _last_tick := -1
var _settlement_done := false
var _complete_clock := -1.0
var _completion_emitted := false
var _total_punch := 0.0
var _entry := 1.0
var _ore_progress: Dictionary = {}
var _ore_unlock := ""
var _ore_building := false
var _ore_build_progress := 0.0
var _boss_info: Dictionary = {}
var _boss_result := ""
var _boss_unlock_grade := -1
var _campaign_won := false

var displayed_counts: PackedInt32Array:
	get:
		return _counts.duplicate()
var displayed_stones: int:
	get:
		return _stones
var displayed_gold: int:
	get:
		return _shown_total
var settlement_visible: bool:
	get:
		return _modal
var settlement_complete: bool:
	get:
		return _settlement_done
var displayed_rows: Array[Dictionary]:
	get:
		return _rows.duplicate(true)


func _ready() -> void:
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "sans-serif"])
	_font.multichannel_signed_distance_field = true
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_bold.multichannel_signed_distance_field = true
	_canvas = HudCanvas.new()
	_canvas.name = "MiningHUD"
	_canvas.presenter = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	if model_gallery == null:
		model_gallery = ModelGallery.new()
		add_child(model_gallery)
	model_gallery.visuals_ready.connect(_redraw_model_icons)
	model_gallery.ensure_ready()
	_replay = _button("다시 채굴하기", true)
	_replay.pressed.connect(_request_next)
	_skip = _button("결과 바로 보기", false)
	_skip.pressed.connect(finish_settlement)
	_upgrades = _button("업그레이드", false)
	_upgrades.name = "OpenUpgrades"
	_upgrades.pressed.connect(func():
		if _upgrades_available:
			upgrades_requested.emit()
	)
	_auction = _button("경매", true)
	_auction.name = "OpenAuction"
	_auction.pressed.connect(_open_auction)
	auction_ui = AuctionUI.new()
	auction_ui.host = self
	_canvas.add_child(auction_ui)
	auction_ui.start_requested.connect(func(): auction_requested.emit())
	auction_ui.presentation_finished.connect(func(): auction_animation_finished.emit())
	auction_ui.closed.connect(_auction_closed)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_replay.hide()
	_skip.hide()
	_upgrades.hide()
	_auction.hide()


func _redraw_model_icons() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func _button(title: String, _primary: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_hover_color", GOLD.lightened(0.15))
	button.add_theme_color_override("font_pressed_color", GOLD)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.22)
		style.set_corner_radius_all(2)
		if state == "hover":
			style.bg_color = Color(1, 1, 1, 0.06)
		if state == "pressed":
			style.bg_color = Color(1, 1, 1, 0.10)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = GOLD
			style.border_width_bottom = 2
		button.add_theme_stylebox_override(state, style)
	_canvas.add_child(button)
	return button


func _layout() -> void:
	var logical := get_viewport().get_visible_rect().size
	# canvas_items + expand keeps the project's 1440 logical width in a
	# portrait window. Compensate its final screen transform rather than
	# shrinking a desktop HUD into that much larger logical viewport.
	var screen_transform := get_viewport().get_final_transform()
	var pixels_per_unit := maxf(minf(screen_transform.x.length(), screen_transform.y.length()), 0.001)
	var physical := logical * pixels_per_unit
	var screen_scale := clampf(minf(physical.x / 1200.0, physical.y / 850.0), 0.85, 1.25)
	_scale = screen_scale / pixels_per_unit
	_view = logical / _scale
	_portrait = physical.x < physical.y
	_wallet_rect = Rect2(_view.x - 144, 32, 112, 60)
	_timer_rect = Rect2(32, 32, minf(370, _view.x - 208), 74)
	var width := 288.0 if not _portrait else minf(_view.x - 40, 540)
	var height := 258.0 if not _portrait else 208.0
	_satchel_rect = Rect2(_view.x - width - 20, _view.y - height - 24, width, height)
	_gem_cards.clear()
	var columns := 2 if not _portrait else 3
	var card_width := (width - 24.0 - float(columns - 1) * 8.0) / float(columns)
	for tier in Rarity.COUNT:
		_gem_cards.append(Rect2(_satchel_rect.position + Vector2(12 + (tier % columns) * (card_width + 8), 8 + (tier / columns) * 52), Vector2(card_width, 50)))
	_layout_modal()
	_canvas.queue_redraw()


func _layout_modal() -> void:
	var count := maxi(_rows.size(), 1)
	var width := minf(620 if _portrait else 1000, _view.x - (40 if _portrait else 64))
	var header := 80.0 if _portrait else 92.0
	var row_step := 54.0
	var body_height := maxf(136, count * row_step + 28) if _portrait else maxf(350, count * row_step + 32)
	var height := header + (142 if _portrait else 0) + body_height + 82
	_compact_settlement = height > _view.y - 32
	if _compact_settlement:
		header = 64
		var row_room := _view.y - 32 - header - (116 if _portrait else 0) - 76 - (24 if _portrait else 28)
		row_step = clampf(row_room / count, 30, 46 if _portrait else 44)
		body_height = maxf(112, count * row_step + 24) if _portrait else maxf(250, count * row_step + 28)
		height = header + (116 if _portrait else 0) + body_height + 76
	_modal_rect = Rect2(Vector2((_view.x - width) * 0.5, maxf(16, (_view.y - height) * 0.5)), Vector2(width, height))
	var p := _modal_rect.position
	if _portrait:
		_info_rect = Rect2(p + Vector2(0, header + (116 if _compact_settlement else 142)), Vector2(width, body_height))
		_total_rect = Rect2(p + Vector2(width * 0.40, header + 8), Vector2(width * 0.60, 96))
		_hero_center = p + Vector2(width * 0.20, header + 50)
		_hero_radius = 38 if _compact_settlement else 44
		_hero_caption_y = p.y + header + (105 if _compact_settlement else 116)
	else:
		var list_height := maxf(112 if _compact_settlement else 136, count * row_step + 28)
		_info_rect = Rect2(p + Vector2(width * 0.44, header + (body_height - list_height) * 0.5), Vector2(width * 0.56, list_height))
		_total_rect = Rect2(p + Vector2(0, header + body_height - 106), Vector2(width * 0.40, 98))
		var hero_height := body_height - 132
		_hero_center = p + Vector2(width * 0.20, header + hero_height * 0.45)
		_hero_radius = minf(76, hero_height * 0.34)
		_hero_caption_y = _hero_center.y + _hero_radius * 1.35 + 17
	_row_rects.clear()
	for row in _rows.size():
		_row_rects.append(Rect2(_info_rect.position + Vector2(18, 14 + row * row_step), Vector2(_info_rect.size.x - 36, row_step)))
	if is_instance_valid(_replay):
		var button_width := minf(280, width - 40)
		_replay.position = (p + Vector2((width - button_width) * 0.5, height - 60)) * _scale
		_replay.size = Vector2(button_width, 60) * _scale
		_skip.position = _replay.position
		_skip.size = _replay.size
		_replay.add_theme_font_size_override("font_size", int(21 * _scale))
		_skip.add_theme_font_size_override("font_size", int(19 * _scale))
		_replay.focus_neighbor_left = _replay.get_path()
		_replay.focus_neighbor_right = _replay.get_path()
		_replay.focus_neighbor_top = _replay.get_path()
		_replay.focus_neighbor_bottom = _replay.get_path()
		_skip.focus_neighbor_left = _skip.get_path()
		_skip.focus_neighbor_right = _skip.get_path()
		_skip.focus_neighbor_top = _skip.get_path()
		_skip.focus_neighbor_bottom = _skip.get_path()
		_upgrades.position = Vector2(24, (_satchel_rect.position.y - 68) if _portrait and not _modal else (_view.y - 84)) * _scale
		_upgrades.size = Vector2(164, 60) * _scale
		_upgrades.add_theme_font_size_override("font_size", int(18 * _scale))
		_upgrades.focus_neighbor_right = _replay.get_path()
		_upgrades.focus_neighbor_top = _replay.get_path()
		_replay.focus_neighbor_left = _upgrades.get_path() if _upgrades_available else _replay.get_path()
		_replay.focus_previous = _upgrades.get_path() if _upgrades_available else _replay.get_path()
		_replay.focus_next = _upgrades.get_path() if _upgrades_available else _replay.get_path()
		_upgrades.focus_next = _replay.get_path()
		_layout_auction_action()
	if is_instance_valid(auction_ui):
		auction_ui.set_layout(_view, _scale)


func _layout_auction_action() -> void:
	if not is_instance_valid(_auction):
		return
	var show_auction: bool = _modal and _settlement_done and _auction_available and not auction_ui.is_open
	_auction.visible = show_auction
	if not show_auction:
		return
	var width := minf(240, (_modal_rect.size.x - 18) * 0.5)
	var center := _modal_rect.get_center().x
	var y := _modal_rect.end.y - 60
	_replay.position = Vector2(center - width - 9, y) * _scale
	_replay.size = Vector2(width, 60) * _scale
	_auction.position = Vector2(center + 9, y) * _scale
	_auction.size = Vector2(width, 60) * _scale
	_replay.add_theme_font_size_override("font_size", int(18 * _scale))
	_auction.add_theme_font_size_override("font_size", int(20 * _scale))
	_replay.focus_neighbor_right = _auction.get_path()
	_replay.focus_next = _auction.get_path()
	_auction.focus_neighbor_left = _replay.get_path()
	_auction.focus_neighbor_right = _upgrades.get_path() if _upgrades_available else _replay.get_path()
	_auction.focus_neighbor_top = _replay.get_path()
	_auction.focus_neighbor_bottom = _replay.get_path()
	_auction.focus_previous = _replay.get_path()
	_auction.focus_next = _upgrades.get_path() if _upgrades_available else _replay.get_path()


func begin_round(round_index: int, wallet: int) -> void:
	_ore_unlock = ""
	_boss_result = ""
	_boss_unlock_grade = -1
	_campaign_won = false
	_round_index = round_index
	_wallet = wallet
	_stones = 0
	_counts.fill(0)
	_gem_pulses.fill(0)
	_modal = false
	_report.clear()
	_rows.clear()
	_settlement_done = false
	_completion_emitted = false
	_complete_clock = -1
	_shown_total = 0
	_countdown_second = -1
	_countdown_pulse = 0
	_remaining = _duration
	_active = true
	_entry = 0.0
	_skill_notices.clear()
	_skill_status.clear()
	_auction_available = false
	if is_instance_valid(_replay):
		_replay.hide()
		_skip.hide()
		_auction.hide()
		_replay.release_focus()
		_skip.release_focus()
		_upgrades.position = Vector2(24, (_satchel_rect.position.y - 68) if _portrait else (_view.y - 84)) * _scale
		_canvas.queue_redraw()


func set_timer(remaining: float, duration: float, active: bool) -> void:
	_remaining = maxf(remaining, 0)
	_duration = maxf(duration, 0.001)
	_active = active
	var second := int(ceil(_remaining))
	if active and second > 0 and second <= 5 and second != _countdown_second:
		_countdown_second = second
		_countdown_pulse = 1


func set_wallet(gold: int) -> void:
	_wallet = maxi(gold, 0)
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func set_upgrades_available(available: bool) -> void:
	available = available and not _campaign_won
	if _upgrades_available == available and is_instance_valid(_upgrades) and _upgrades.visible == available:
		return
	_upgrades_available = available
	if not is_instance_valid(_upgrades):
		return
	_upgrades.visible = available
	_upgrades.disabled = not available
	_layout_modal()


func restore_round_focus() -> void:
	if _modal and _settlement_done and is_instance_valid(_replay) and _replay.visible:
		_replay.grab_focus()
	elif is_instance_valid(_upgrades):
		_upgrades.release_focus()


func set_auction_available(available: bool) -> void:
	available = available and not _campaign_won
	if _auction_available == available:
		return
	_auction_available = available
	_layout_modal()


func _open_auction() -> void:
	if not _modal or not _settlement_done or not _auction_available or auction_ui.is_open:
		return
	auction_ui.show_offer(int(_report.get("total", 0)))
	_replay.hide()
	_auction.hide()
	set_upgrades_available(false)
	cue.emit("confirm", 0)


func _auction_closed() -> void:
	_replay.visible = not _campaign_won
	_layout_modal()
	if _auction.visible:
		_auction.grab_focus()
	else:
		_replay.grab_focus()
	_canvas.queue_redraw()


func apply_auction_result(report: Dictionary) -> void:
	_report = report.duplicate(true)
	_shown_total = int(_report.get("final_total", _report.get("total", 0)))
	_wallet = int(_report.get("wallet_after", _wallet))
	_total_punch = 1.0
	_complete_clock = _clock if int(_report.auction.change_percent) > 0 else _clock - 2.0
	set_auction_available(false)
	_canvas.queue_redraw()


func set_stones(count: int) -> void:
	if count > _stones:
		_stone_pulse = 1
	_stones = maxi(count, 0)


func set_gem_counts(counts: PackedInt32Array) -> void:
	for tier in Rarity.COUNT:
		_counts[tier] = maxi(counts[tier], 0) if tier < counts.size() else 0


func gem_target_screen(tier: int) -> Vector2:
	if _gem_cards.size() != Rarity.COUNT:
		return get_viewport().get_visible_rect().size - Vector2(90, 100)
	return (_gem_cards[clampi(tier, 0, Rarity.COUNT-1)].position + Vector2(24, 25)) * _scale


func playfield_bottom_screen() -> float:
	# Logical viewport coordinates, matching Camera3D.project_position().
	return _satchel_rect.position.y * _scale if _portrait else get_viewport().get_visible_rect().size.y


func gem_target_diameter_screen() -> float:
	return 38.0 * _scale


func pulse_gem(tier: int, count: int) -> void:
	if tier < 0 or tier >= Rarity.COUNT:
		return
	_counts[tier] = maxi(count, 0)
	_gem_pulses[tier] = 1
	cue.emit("pickup", tier)


func is_pointer_blocked(position: Vector2) -> bool:
	# The visible tray also protects a landing gem from a stray mining click.
	return _modal or _satchel_rect.has_point(position / _scale) or (is_instance_valid(_upgrades) and _upgrades.visible and _upgrades.get_global_rect().has_point(position))


func show_settlement(report: Dictionary) -> void:
	# Snapshot only; displaying or skipping the count-up never awards Gold.
	_report = report.duplicate(true)
	_rows.clear()
	for row: Dictionary in _report.get("rows", []):
		if int(row.get("count", 0)) > 0:
			_rows.append(row.duplicate())
	_row_progress.resize(_rows.size())
	_row_progress.fill(0)
	_settlement_time = 0
	_row_cued = -1
	_last_tick = -1
	_shown_total = 0
	_complete_clock = -1
	_total_punch = 0
	_settlement_done = false
	_auction_available = false
	_completion_emitted = false
	_modal = true
	_active = false
	_remaining = 0
	_wallet = int(_report.get("wallet_before", _wallet))
	_layout_modal()
	_replay.hide()
	_skip.show()
	_skip.grab_focus()


func finish_settlement() -> void:
	if not _modal or _settlement_done:
		return
	_row_progress.fill(1)
	_shown_total = int(_report.get("total", 0))
	_settlement_done = true
	_complete_clock = _clock
	_total_punch = 1
	_wallet = int(_report.get("wallet_after", _wallet))
	_skip.hide()
	_replay.visible = not _campaign_won
	if _replay.visible: _replay.grab_focus()
	cue.emit("auction_jackpot" if bool(_report.get("golden_day", false)) else "total", -1)
	if not _completion_emitted:
		_completion_emitted = true
		settlement_animation_finished.emit()
	_layout_modal()
	_canvas.queue_redraw()


func _request_next() -> void:
	if _campaign_won or not _modal or not _settlement_done or auction_ui.is_open:
		return
	# Close immediately, so repeated controller presses cannot request twice.
	_modal = false
	_replay.hide()
	_skip.hide()
	_auction.hide()
	cue.emit("confirm", -1)
	next_round_requested.emit()


var _skill_notices: Array[Dictionary] = []
var _skill_status: Array[String] = []

func skill_notice(screen: Vector2, message: String, color: Color) -> void:
	if _modal:
		return
	for entry in _skill_notices:
		if entry.age < 0.08 and Vector2(entry.point).distance_to(screen / _scale) < 22:
			if not str(entry.message).contains(message):
				entry.message += " · " + message
			return
	if _skill_notices.size() >= 18:
		_skill_notices.pop_front()
	_skill_notices.append({"point": screen / _scale, "message": message, "color": color, "age": 0.0})

func set_skill_status(combo: int, combo_time: float, charges: int, buff: int, buff_time: float, bonus_gold: int) -> void:
	_skill_status.clear()
	if combo > 0:
		_skill_status.append("콤보 ×%d  %.1f" % [combo, combo_time])
	if charges > 0:
		_skill_status.append("추가타격 ×%d" % charges)
	if buff >= 0:
		_skill_status.append("%s %.1f" % [["힘의 축복", "가속의 축복", "범위의 축복"][buff], buff_time])
	if bonus_gold > 0:
		_skill_status.append("추가 Gold +%d" % bonus_gold)

func _process(delta: float) -> void:
	for i in range(_skill_notices.size() - 1, -1, -1):
		_skill_notices[i].age += delta
		if _skill_notices[i].age >= 0.80:
			_skill_notices.remove_at(i)
	_clock += delta
	_entry = minf(_entry + delta * 3.5, 1)
	_countdown_pulse = maxf(_countdown_pulse - delta * 2.8, 0)
	_stone_pulse = maxf(_stone_pulse - delta * 4, 0)
	_total_punch = maxf(_total_punch - delta * 1.8, 0)
	for tier in Rarity.COUNT:
		_gem_pulses[tier] = maxf(_gem_pulses[tier] - delta * 2.3, 0)
	if _modal and not _settlement_done:
		_animate_settlement(delta)
	_canvas.queue_redraw()


func _animate_settlement(delta: float) -> void:
	_settlement_time += delta
	var lead := 0.55
	var row_duration := minf(0.67, 3.4 / maxf(_rows.size(), 1))
	var total := 0
	for i in _rows.size():
		var local := (_settlement_time - lead - i * row_duration) / row_duration
		_row_progress[i] = clampf(local, 0, 1)
		if local > 0 and _row_cued < i:
			_row_cued = i
			cue.emit("row", int(_rows[i].get("tier", -1)))
		var eased := 1.0 - pow(1.0 - clampf(local / 0.84, 0, 1), 3)
		total += int(round(int(_rows[i].get("gold", 0)) * eased))
	_shown_total = total
	var tick := int(_settlement_time * 12)
	if total > 0 and _row_cued >= 0 and _row_progress[_row_cued] < 0.85 and tick != _last_tick:
		_last_tick = tick
		cue.emit("tick", int(_rows[_row_cued].get("tier", -1)))
	if _settlement_time > lead + maxf(_rows.size(), 1) * row_duration + 0.35:
		finish_settlement()


func _draw_hud(c: Control) -> void:
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _scale)
	_draw_wallet(c)
	_draw_timer(c)
	if _boss_info.is_empty(): _draw_ore_progress(c)
	else: _draw_boss(c)
	_draw_satchel(c)
	if not _modal:
		for i in _skill_status.size():
			_text(c, _skill_status[i], Vector2(32, (220 if not _boss_info.is_empty() else 156 if not _ore_progress.is_empty() else 101) + i * 20), 13, MUTED, false)
		for entry in _skill_notices:
			var point: Vector2 = entry.point - Vector2(0, 26 + float(entry.age) * 46)
			var alpha := minf(1.0, (0.80 - float(entry.age)) / 0.22)
			var size := _fit_text(str(entry.message), 19, _view.x - 48)
			var half_width := _bold.get_string_size(str(entry.message), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
			point = point.clamp(Vector2(half_width + 16, 110), _view - Vector2(half_width + 16, 40))
			_text(c, str(entry.message), point + Vector2(1, 2), size, Color(0.03, 0.05, 0.05, alpha), true, HORIZONTAL_ALIGNMENT_CENTER)
			_text(c, str(entry.message), point, size, Color(entry.color, alpha), true, HORIZONTAL_ALIGNMENT_CENTER)
	if _modal and not auction_ui.is_open:
		_draw_settlement(c)
	c.draw_set_transform(Vector2.ZERO)


func _draw_wallet(c: Control) -> void:
	_text(c, "GOLD", _wallet_rect.position + Vector2(_wallet_rect.size.x, 13), 12, MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	var amount := _number(_wallet)
	var number_size := _fit_text(amount, 26, _wallet_rect.size.x - 30)
	var number_width := _bold.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x
	_coin(c, Vector2(_wallet_rect.end.x - number_width - 18, _wallet_rect.position.y + 33), 12)
	_text(c, amount, _wallet_rect.position + Vector2(_wallet_rect.size.x, 43), number_size, GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)

func set_ore_progress(info: Dictionary, unlocked: bool = false) -> void:
	_ore_progress = info.duplicate(true)
	if unlocked and _boss_result.is_empty(): _ore_unlock = "새 광맥 발견 · "+str(info.title)
	_canvas.queue_redraw()

func set_ore_building(building: bool, progress: float) -> void:
	if _ore_building == building and is_equal_approx(_ore_build_progress,progress): return
	_ore_building = building
	_ore_build_progress = progress
	_canvas.queue_redraw()

func _draw_ore_progress(c: Control) -> void:
	if _ore_progress.is_empty(): return
	var r := Rect2(32,92,_ore_progress_width(),48)
	var color: Color = _ore_progress.accent
	_text(c,"%02d  %s" % [int(_ore_progress.index)+1,_ore_progress.title],r.position+Vector2(0,11),14,color)
	_text(c,"%d조각 · %d겹" % [_ore_progress.pieces,_ore_progress.layers.size()],r.position+Vector2(r.size.x,11),11,MUTED,false,HORIZONTAL_ALIGNMENT_RIGHT)
	var width := r.size.x
	c.draw_rect(Rect2(r.position+Vector2(0,19),Vector2(width,3)),Color(0.25,0.3,0.3,0.55))
	var fill := _ore_build_progress if _ore_building else float(_ore_progress.progress)
	if not _ore_building and bool(_ore_progress.get("boss_gate",false)):
		fill = minf(1.0,float(_ore_progress.boss_count)/maxi(1,int(_ore_progress.boss_goal)))
	c.draw_rect(Rect2(r.position+Vector2(0,19),Vector2(width*fill,3)),color)
	var caption := "최상위 광맥 · 누적 %s G" % _number(_ore_progress.earned) if bool(_ore_progress.maxed) else "다음 광맥까지 %s G" % _number(_ore_progress.remaining)
	if _ore_building: caption = "원석 준비 중 · %d%%" % mini(99,int(_ore_build_progress*100))
	elif bool(_ore_progress.get("boss_gate",false)):
		caption = "보스까지 원석 %d / %d" % [mini(int(_ore_progress.boss_count),int(_ore_progress.boss_goal)),int(_ore_progress.boss_goal)]
	_text(c,caption,r.position+Vector2(0,39),11,MUTED,false)

func set_boss_info(info: Dictionary) -> void:
	_boss_info = info.duplicate()
	_canvas.queue_redraw()

func set_boss_result(title: String, victory: bool, final_victory: bool, grade: int) -> void:
	_campaign_won = final_victory
	_boss_unlock_grade = clampi(grade,0,Rarity.COUNT-1) if victory else -1
	_boss_result = "승리 · 모든 광맥 정복" if final_victory else title+" 격파!" if victory else title+" · 도전 종료"
	_ore_unlock = RARITY_NAMES[clampi(grade,0,Rarity.COUNT-1)]+" 보석 해금" if victory and not final_victory else "다음 채굴에서 원석을 깨고 다시 도전하세요" if not victory else "이형의 심장까지 모두 정복했습니다"
	_canvas.queue_redraw()

func _draw_boss(c: Control) -> void:
	var r := Rect2(24,88,_ore_progress_width()+16,114)
	var accent: Color = Color("ff947e") if bool(_boss_info.danger) else _boss_info.accent
	c.draw_rect(r,Color(.01,.015,.025,.60))
	_text(c,"BOSS %02d  %s" % [int(_boss_info.stage)+1,_boss_info.title],r.position+Vector2(8,22),17,accent)
	var bar := Rect2(r.position+Vector2(8,34),Vector2(r.size.x-16,5))
	c.draw_rect(bar,Color(1,1,1,.13))
	c.draw_rect(Rect2(bar.position,Vector2(bar.size.x*clampf(float(_boss_info.ratio),0,1),5)),accent)
	_text(c,_boss_info.status,r.position+Vector2(8,62),13,TEXT)
	var hint: String = _boss_info.hint
	c.draw_multiline_string(_font,r.position+Vector2(8,82),hint,HORIZONTAL_ALIGNMENT_LEFT,r.size.x-16,12,2,MUTED)

func _ore_progress_width() -> float:
	var compact := _view.y < 640 and _view.x > _view.y
	return minf(280 if compact else 370,_view.x-64)


func _draw_timer(c: Control) -> void:
	var urgent := _remaining <= 5 and _active
	var accent := Color("ed865f") if urgent else BAR_COLOR
	var r := _timer_rect
	var bar := Rect2(r.position, Vector2(r.size.x, 6))
	c.draw_rect(bar, Color(0, 0, 0, 0.33))
	var ratio := clampf(_remaining / _duration, 0, 1)
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), accent)
	var title := "남은 시간"
	if not _active and not _modal:
		title = "채굴하면 시작" if _remaining >= _duration - 0.01 else ("정산 준비 중" if _remaining <= 0 else "잠시 쉬는 중")
	if _ore_building: title = "원석 준비 중"
	elif not _boss_info.is_empty(): title = "체력"
	var title_size := 23 if r.size.x > 280 else 19
	_text(c, title, r.position + Vector2(0, 41), title_size, TEXT)
	var label_width := _bold.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var time_text := "%02d초" % int(ceil(_remaining))
	if not _boss_info.is_empty(): time_text = "%d%%" % ceili(ratio*100)
	_text(c, time_text, r.position + Vector2(label_width + 14, 41), title_size + 2 + int(_countdown_pulse * 2), GOLD if not urgent else accent)


func _draw_satchel(c: Control) -> void:
	var r := _satchel_rect
	# One faint backing preserves contrast over a moving rock. No frame or
	# individual cards compete with the crystal silhouettes and quantities.
	c.draw_rect(r, Color(0, 0, 0, 0.14))
	for tier in Rarity.COUNT:
		var card := _gem_cards[tier]
		var pulse := _gem_pulses[tier]
		var color: Color = GEM_COLORS[tier]
		_gem(c, card.position + Vector2(24, 25), 15 * (1 + pulse * 0.2), tier, Color.WHITE if _counts[tier] > 0 else Color(0.62, 0.62, 0.62))
		_text(c, RARITY_NAMES[tier], card.position + Vector2(49, 16), 11, MUTED, false)
		_text(c, str(_counts[tier]), card.position + Vector2(48, 41), 27 + int(pulse * 3), TEXT if _counts[tier] > 0 else Color("8a9698"))
		if pulse > 0:
			for spark in 4:
				var angle := spark * TAU / 4 + 0.4
				var point := card.position + Vector2(24, 25) + Vector2.from_angle(angle) * (20 + (1 - pulse) * 22)
				_diamond(c, point, 3.5 * pulse, Color(color, pulse))
	var stone_y := r.end.y - 19
	c.draw_line(Vector2(r.position.x + 20, stone_y - 16), Vector2(r.end.x - 20, stone_y - 16), Color(1, 1, 1, 0.12), 1)
	_stone(c, Vector2(r.position.x + 36, stone_y + 1), 10)
	_text(c, "돌 조각", Vector2(r.position.x + 59, stone_y + 7), 13, MUTED, false)
	_text(c, str(_stones), Vector2(r.end.x - 23, stone_y + 8), 22, TEXT.lerp(GOLD, _stone_pulse), true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_settlement(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, _view), Color(0.015, 0.020, 0.021, 0.84))
	var r := _modal_rect
	var heading := "채굴 완료" if _boss_result.is_empty() else _boss_result
	_text(c, heading, r.position + Vector2(r.size.x * 0.5, 32 if _compact_settlement else 40), _fit_text(heading,31 if _compact_settlement else 38,r.size.x-32), GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	var subtitle := "이번 채굴의 수확"
	if not _ore_unlock.is_empty(): subtitle = _ore_unlock
	if _report.has("auction"):
		var change := int(_report.auction.change_percent)
		subtitle = "경매 %s%d%% · 기본 정산 %s G" % ["+" if change > 0 else "", change, _number(int(_report.total))]
	_text(c, subtitle, r.position + Vector2(r.size.x * 0.5, 56 if _compact_settlement else 68), 14, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	c.draw_rect(_info_rect, Color(0, 0, 0, 0.22))
	var best := -1
	for row in _rows:
		best = maxi(best, int(row.get("tier", -1)))
	if _boss_unlock_grade >= 0: best = _boss_unlock_grade
	var hero_radius := _hero_radius * (1 + _total_punch * 0.055)
	if best >= 0:
		_gem(c, _hero_center, hero_radius, best)
		var caption: String = "광맥 정복" if _campaign_won else RARITY_NAMES[best]+(" 보석 해금" if _boss_unlock_grade >= 0 else " 보석")
		_text(c, caption, Vector2(_hero_center.x, _hero_caption_y), 14, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_stone(c, _hero_center, hero_radius * 0.90, 0.75 if _rows.is_empty() else 1)
		_text(c, "다음 발견을 향해" if _rows.is_empty() else "캔 돌 조각", Vector2(_hero_center.x, _hero_caption_y), 14, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	for i in _rows.size():
		_draw_result_row(c, i)
	if _rows.is_empty():
		_text(c, "이번에는 수확이 없어요", _info_rect.get_center() + Vector2(0, -4), 18, TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
		_text(c, "새 원석에서 다시 도전해요", _info_rect.get_center() + Vector2(0, 23), 14, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	var total := _total_rect
	var total_title := "경매 정산 GOLD" if _report.has("auction") else ("황금의 날 ×2" if bool(_report.get("golden_day", false)) else ("획득 GOLD" if _settlement_done else "정산 중"))
	_text(c, total_title, Vector2(total.get_center().x, total.position.y + 21), 15, TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	var gold_text := "+ " + _number(_shown_total)
	var coin_radius := 14.0 if _compact_settlement else 16.0
	var total_size := _fit_text(gold_text, (44 if _portrait else 54) + int(_total_punch * 4), total.size.x - coin_radius * 2 - 24)
	var total_width := _bold.get_string_size(gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1, total_size).x
	var group_left := total.get_center().x - (total_width + coin_radius * 2 + 12) * 0.5
	_coin(c, Vector2(group_left + coin_radius, total.position.y + 78 - total_size * 0.34), coin_radius)
	_text(c, gold_text, Vector2(group_left + coin_radius * 2 + 12, total.position.y + 78), total_size, GOLD)
	if _settlement_done:
		_draw_celebration(c)


func _draw_result_row(c: Control, index: int) -> void:
	var r := _row_rects[index]
	var row := _rows[index]
	var progress := _row_progress[index]
	var revealed := progress > 0
	var finished := progress >= 1
	var tier := int(row.get("tier", -1))
	var alpha := 1.0 if revealed else 0.24
	var flash := sin(clampf(progress * 2.0, 0, 1) * PI)
	if index < _rows.size() - 1:
		c.draw_line(Vector2(r.position.x, r.end.y - 1), Vector2(r.end.x, r.end.y - 1), Color(1, 1, 1, 0.075 + flash * 0.12), 1)
	var dense := r.size.y < 38
	var center_y := 16.0 if dense else 22.0 if _compact_settlement else 26.0
	var icon_radius := 10.0 if dense else 13.0
	if tier >= 0:
		_gem(c, r.position + Vector2(16, center_y), icon_radius * (1 + flash * 0.15), tier, Color(1, 1, 1, alpha))
	elif row.get("kind") in ["bonus","boss"]:
		_coin(c, r.position + Vector2(16, center_y), icon_radius, Color(1, 1, 1, alpha))
	else:
		_stone(c, r.position + Vector2(16, center_y), icon_radius, alpha)
	var label := str(row.get("label", RARITY_NAMES[tier] if tier >= 0 else "돌 조각"))
	_text(c, label, r.position + Vector2(40, 15 if dense else 19 if _compact_settlement else 22), 14 if dense else 16, Color(TEXT, alpha))
	var formula := _result_formula(row,r.size.x-44)
	_text(c, formula.text, r.position + Vector2(40, 28 if dense else 36 if _compact_settlement else 43), mini(10,formula.size) if dense else formula.size, Color(MUTED, alpha), false)
	var eased := 1.0 - pow(1.0 - clampf(progress / 0.84, 0, 1), 3)
	var amount := int(round(int(row.get("gold", 0)) * eased))
	var amount_baseline := 29.0 if _compact_settlement else 34.0
	if row.has("discount"): amount_baseline = 19.0 if _compact_settlement else 22.0
	if dense: amount_baseline = 21.0
	_coin(c, r.position + Vector2(r.size.x - 11, amount_baseline - 7), 11, Color(1, 1, 1, alpha))
	_text(c, "+ %s" % _number(amount), r.position + Vector2(r.size.x - 28, amount_baseline), 18 if dense else 20 if _compact_settlement else 22, Color(GOLD if finished else TEXT, alpha), true, HORIZONTAL_ALIGNMENT_RIGHT)

func _result_formula(row: Dictionary, width: float) -> Dictionary:
	var value := str(row.get("formula","%s개 × %s G" % [_number(int(row.get("count",0))),_number(int(row.get("unit_gold",0)))]))
	var font_size := 12 if _compact_settlement else 13
	if row.has("discount"):
		while font_size > 11 and _font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width: font_size -= 1
		if _font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
			# Preserve every operand on small screens; the full named formula
			# remains in the report and is shown whenever there is room.
			var premium := " +%d" % int(row.get("premium",0)) if int(row.get("premium",0)) > 0 else ""
			value = "%d×%d%s −%d G · 분쇄" % [row.count,row.unit_gold,premium,row.discount]
		while font_size > 9 and _font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width: font_size -= 1
	return {"text":value,"size":font_size}


func _draw_celebration(c: Control) -> void:
	var elapsed := _clock - _complete_clock
	if elapsed < 0 or elapsed > 1.5:
		return
	var center := _total_rect.get_center()
	var fade := pow(1 - elapsed / 1.5, 1.4)
	for i in 8:
		var angle := float(i) * 2.39996
		var distance := 52 + elapsed * (35 + (i % 4) * 10)
		var point := center + Vector2(cos(angle) * distance * 1.15, sin(angle) * distance * 0.65 + elapsed * elapsed * 16)
		_diamond(c, point, (2 + i % 2) * fade, Color(GOLD, fade * 0.75))


func _text(c: Control, value: String, baseline: Vector2, size: int, color: Color = TEXT, bold: bool = true, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = _bold if bold else _font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := baseline.x
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	c.draw_string(font, Vector2(x, baseline.y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _number(value: int) -> String:
	var source := str(maxi(value, 0))
	var output := ""
	for i in source.length():
		if i > 0 and (source.length() - i) % 3 == 0:
			output += ","
		output += source[i]
	return output


func _fit_text(value: String, preferred_size: int, max_width: float) -> int:
	var size := preferred_size
	while size > 15 and _bold.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
		size -= 1
	return size


func _gem(c: Control, center: Vector2, radius: float, tier: int, tint: Color = Color.WHITE) -> void:
	model_gallery.draw_gem(c, center, radius, tier, tint)


func _coin(c: Control, center: Vector2, radius: float, tint: Color = Color.WHITE) -> void:
	model_gallery.draw_coin(c, center, radius, tint)


func _stone(c: Control, center: Vector2, radius: float, alpha: float = 1) -> void:
	var p := PackedVector2Array([Vector2(-0.84, -0.25), Vector2(-0.37, -0.88), Vector2(0.54, -0.72), Vector2(0.94, 0.18), Vector2(0.45, 0.72), Vector2(-0.65, 0.61)])
	for i in p.size():
		p[i] = center + p[i] * radius
	c.draw_colored_polygon(p, Color(Color("637981"), alpha))
	c.draw_colored_polygon(PackedVector2Array([p[0], p[1], p[2], center]), Color(Color("a4b5b7"), alpha))
	c.draw_colored_polygon(PackedVector2Array([center, p[2], p[3], p[4]]), Color(Color("4d636e"), alpha))
	c.draw_colored_polygon(PackedVector2Array([center, p[4], p[5]]), Color(Color("83959c"), alpha))


func _diamond(c: Control, center: Vector2, radius: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius * 1.5), center + Vector2(radius, 0), center + Vector2(0, radius * 1.5), center + Vector2(-radius, 0)]), color)
