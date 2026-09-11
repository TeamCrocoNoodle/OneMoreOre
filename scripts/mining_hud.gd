extends CanvasLayer
## Presentation only. The round ledger owns collection, prices, and payment.

signal next_round_requested
signal cue(kind: String, tier: int)
signal settlement_animation_finished

const RARITY_NAMES := ["일반", "특별", "희귀", "전설", "신화", "고대"]
const GEM_COLORS := [Color("edf8ff"), Color("64ff86"), Color("4896ff"), Color("ffe15b"), Color("be65ff"), Color("ff4c61")]
const INK := Color("11272f")
const PANEL := Color("19343e")
const EDGE := Color("48626a")
const TEXT := Color("eef6ed")
const MUTED := Color("9db3b6")
const GOLD := Color("ffd367")
const GOLD_DARK := Color("916b2c")

class HudCanvas extends Control:
	var presenter: Node
	func _draw() -> void:
		if is_instance_valid(presenter):
			presenter._draw_hud(self)

var _canvas: HudCanvas
var _font: SystemFont
var _bold: SystemFont
var _replay: Button
var _skip: Button
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
var _remaining := 30.0
var _duration := 30.0
var _active := true
var _wallet := 0
var _stones := 0
var _counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _round_index := 1
var _gem_pulses := PackedFloat32Array([0, 0, 0, 0, 0, 0])
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
	_replay = _button("다시 채굴하기", true)
	_replay.pressed.connect(_request_next)
	_skip = _button("결과 바로 보기", false)
	_skip.pressed.connect(finish_settlement)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_replay.hide()
	_skip.hide()


func _button(title: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_focus_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK if primary else GOLD)
	button.add_theme_color_override("font_pressed_color", INK if primary else GOLD)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = GOLD if primary else Color("213d47")
		style.border_color = Color("fff0af") if primary else EDGE
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		style.shadow_color = Color(0.02, 0.08, 0.10, 0.55)
		style.shadow_size = 0
		style.shadow_offset = Vector2(0, 5)
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.10)
		if state == "pressed":
			style.bg_color = style.bg_color.darkened(0.12)
			style.shadow_offset = Vector2.ZERO
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("fff5cf")
			style.set_border_width_all(3)
			style.expand_margin_left = 4
			style.expand_margin_right = 4
			style.expand_margin_top = 4
			style.expand_margin_bottom = 4
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
	_wallet_rect = Rect2(24, 24, 208, 68)
	_timer_rect = Rect2((_view.x - 402) * 0.5, 110 if _portrait or physical.x < 740 else 24, 402, 104)
	var width := 302.0 if not _portrait else minf(_view.x - 32, 640)
	var height := 286.0 if not _portrait else 228.0
	_satchel_rect = Rect2(_view.x - width - (24 if not _portrait else 16), _view.y - height - 24, width, height)
	_gem_cards.clear()
	var columns := 2 if not _portrait else 3
	var card_width := (width - 32.0 - float(columns - 1) * 8.0) / float(columns)
	for tier in 6:
		_gem_cards.append(Rect2(_satchel_rect.position + Vector2(16 + (tier % columns) * (card_width + 8), 61 + (tier / columns) * 58), Vector2(card_width, 50)))
	_layout_modal()
	_canvas.queue_redraw()


func _layout_modal() -> void:
	var count := maxi(_rows.size(), 1)
	var width := minf(640, _view.x - 32)
	var height := 354.0 + count * 61.0
	_compact_settlement = height > _view.y - 32
	if _compact_settlement:
		height = 226.0 + count * 38.0
	_modal_rect = Rect2(Vector2((_view.x - width) * 0.5, maxf(16, (_view.y - height) * 0.5)), Vector2(width, height))
	_row_rects.clear()
	for row in _rows.size():
		var row_y := 64 + row * 38 if _compact_settlement else 132 + row * 61
		_row_rects.append(Rect2(_modal_rect.position + Vector2(28, row_y), Vector2(width - 56, 34 if _compact_settlement else 53)))
	_total_rect = Rect2(_modal_rect.position + Vector2(28, 74 + count * 38 if _compact_settlement else 147 + count * 61), Vector2(width - 56, 68 if _compact_settlement else 100))
	if is_instance_valid(_replay):
		var button_width := width - 64
		_replay.position = (_modal_rect.position + Vector2(32, height - (72 if _compact_settlement else 82))) * _scale
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


func begin_round(round_index: int, wallet: int) -> void:
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
	if is_instance_valid(_replay):
		_replay.hide()
		_skip.hide()
		_replay.release_focus()
		_skip.release_focus()
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


func set_stones(count: int) -> void:
	if count > _stones:
		_stone_pulse = 1
	_stones = maxi(count, 0)


func set_gem_counts(counts: PackedInt32Array) -> void:
	for tier in 6:
		_counts[tier] = maxi(counts[tier], 0) if tier < counts.size() else 0


func gem_target_screen(tier: int) -> Vector2:
	if _gem_cards.size() != 6:
		return get_viewport().get_visible_rect().size - Vector2(90, 100)
	return (_gem_cards[clampi(tier, 0, 5)].position + Vector2(24, 25)) * _scale


func playfield_bottom_screen() -> float:
	# Logical viewport coordinates, matching Camera3D.project_position().
	return _satchel_rect.position.y * _scale if _portrait else get_viewport().get_visible_rect().size.y


func gem_target_diameter_screen() -> float:
	return 38.0 * _scale


func pulse_gem(tier: int, count: int) -> void:
	if tier < 0 or tier > 5:
		return
	_counts[tier] = maxi(count, 0)
	_gem_pulses[tier] = 1
	cue.emit("pickup", tier)


func is_pointer_blocked(position: Vector2) -> bool:
	# The visible tray also protects a landing gem from a stray mining click.
	return _modal or _satchel_rect.has_point(position / _scale)


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
	_replay.show()
	_replay.grab_focus()
	cue.emit("total", -1)
	if not _completion_emitted:
		_completion_emitted = true
		settlement_animation_finished.emit()
	_canvas.queue_redraw()


func _request_next() -> void:
	if not _modal or not _settlement_done:
		return
	# Close immediately, so repeated controller presses cannot request twice.
	_modal = false
	_replay.hide()
	_skip.hide()
	cue.emit("confirm", -1)
	next_round_requested.emit()


func _process(delta: float) -> void:
	_clock += delta
	_entry = minf(_entry + delta * 3.5, 1)
	_countdown_pulse = maxf(_countdown_pulse - delta * 2.8, 0)
	_stone_pulse = maxf(_stone_pulse - delta * 4, 0)
	_total_punch = maxf(_total_punch - delta * 1.8, 0)
	for tier in 6:
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
	_draw_satchel(c)
	if _modal:
		_draw_settlement(c)
	c.draw_set_transform(Vector2.ZERO)


func _draw_wallet(c: Control) -> void:
	_panel(c, _wallet_rect, PANEL, EDGE, 10)
	_coin(c, _wallet_rect.position + Vector2(30, 35), 17)
	_text(c, "보유 GOLD", _wallet_rect.position + Vector2(58, 23), 12, MUTED, false)
	var amount := _number(_wallet)
	_text(c, amount, _wallet_rect.position + Vector2(58, 51), _fit_text(amount, 25, _wallet_rect.size.x - 73), GOLD)


func _draw_timer(c: Control) -> void:
	var urgent := _remaining <= 5 and _active
	var accent := Color("ff8c71") if urgent else GOLD
	var r := _timer_rect
	_panel(c, r, PANEL, accent.darkened(0.4), 12)
	var title := "채굴 시간"
	if not _active and not _modal:
		title = "채굴하면 시작" if _remaining >= _duration - 0.01 else ("정산 준비 중" if _remaining <= 0 else "잠시 쉬는 중")
	_text(c, title, r.position + Vector2(24, 33), 17, MUTED)
	var time_text := "%02d" % int(ceil(_remaining))
	_text(c, time_text, r.position + Vector2(r.size.x - 63, 45), 36 + int(_countdown_pulse * 3), accent, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, "초", r.position + Vector2(r.size.x - 43, 42), 16, MUTED)
	var bar := Rect2(r.position + Vector2(23, 64), Vector2(r.size.x - 46, 17))
	c.draw_style_box(_flat(INK, 5), bar)
	var ratio := clampf(_remaining / _duration, 0, 1)
	if ratio > 0:
		var fill := Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * ratio, 13))
		c.draw_style_box(_flat(accent, 4), fill)
		c.draw_rect(Rect2(fill.position + Vector2(2, 2), Vector2(maxf(fill.size.x - 4, 0), 3)), accent.lightened(0.3))
		for i in range(1, 6):
			var x := bar.position.x + i * bar.size.x / 6.0
			c.draw_line(Vector2(x, bar.position.y + 3), Vector2(x, bar.end.y - 3), Color(0.04, 0.15, 0.18, 0.32), 2)
	if urgent:
		c.draw_style_box(_outline(Color(1, 0.51, 0.32, 0.35 * _countdown_pulse), 12, 3), r.grow(3))


func _draw_satchel(c: Control) -> void:
	var r := _satchel_rect
	_panel(c, r, PANEL, EDGE, 12)
	_text(c, "이번 채굴", r.position + Vector2(19, 34), 20, TEXT)
	_text(c, "%02d" % _round_index, r.position + Vector2(r.size.x - 20, 33), 15, MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	for tier in 6:
		var card := _gem_cards[tier]
		var pulse := _gem_pulses[tier]
		var color: Color = GEM_COLORS[tier]
		c.draw_style_box(_flat(Color("102a34").lerp(color.darkened(0.77), pulse * 0.5), 7), card)
		if pulse > 0:
			c.draw_style_box(_outline(Color(color, pulse * 0.8), 7, 2), card)
		_gem(c, card.position + Vector2(24, 25), 14 * (1 + pulse * 0.2), color if _counts[tier] > 0 else color.darkened(0.44))
		_text(c, RARITY_NAMES[tier], card.position + Vector2(47, 20), 12, MUTED if _counts[tier] == 0 else color, false)
		_text(c, str(_counts[tier]), card.position + Vector2(47, 41), 21, TEXT if _counts[tier] > 0 else Color("647f88"))
		if pulse > 0:
			for spark in 4:
				var angle := spark * TAU / 4 + 0.4
				var point := card.position + Vector2(24, 25) + Vector2.from_angle(angle) * (20 + (1 - pulse) * 22)
				_diamond(c, point, 3.5 * pulse, Color(color, pulse))
	var stone_y := r.end.y - 27
	c.draw_line(Vector2(r.position.x + 18, stone_y - 20), Vector2(r.end.x - 18, stone_y - 20), Color("35535c"), 1)
	_stone(c, Vector2(r.position.x + 28, stone_y + 1), 12)
	_text(c, "돌 조각", Vector2(r.position.x + 50, stone_y + 7), 14, MUTED, false)
	_text(c, str(_stones), Vector2(r.end.x - 21, stone_y + 8), 21, TEXT.lerp(GOLD, _stone_pulse), true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_settlement(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, _view), Color(0.025, 0.072, 0.093, 0.79))
	var r := _modal_rect
	_panel(c, r, Color("183540"), GOLD_DARK, 20)
	# Broad angular facets keep the result card close to the rock's materials.
	c.draw_colored_polygon(PackedVector2Array([r.position + Vector2(20, 2), r.position + Vector2(r.size.x * 0.72, 2), r.position + Vector2(r.size.x * 0.48, 102), r.position + Vector2(2, 79), r.position + Vector2(2, 20)]), Color("213e48"))
	_text(c, "채굴 완료", r.position + Vector2(r.size.x * 0.5, 35 if _compact_settlement else 58), 28 if _compact_settlement else 33, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	_text(c, "발견한 보물이 골드로!", r.position + Vector2(r.size.x * 0.5, 54 if _compact_settlement else 90), 13 if _compact_settlement else 16, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	for i in _rows.size():
		_draw_result_row(c, i)
	if _rows.is_empty():
		_text(c, "아직 담은 보물이 없어요", r.position + Vector2(r.size.x * 0.5, 86 if _compact_settlement else 161), 17 if _compact_settlement else 19, TEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
		if not _compact_settlement:
			_text(c, "다음 원석에서 다시 도전해요", r.position + Vector2(r.size.x * 0.5, 187), 14, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	var total := _total_rect
	c.draw_style_box(_flat(Color("102730"), 10), total)
	c.draw_line(total.position + Vector2(17, 1), Vector2(total.end.x - 17, total.position.y + 1), GOLD_DARK, 2)
	_text(c, "획득 GOLD" if _settlement_done else "골드 정산 중", total.position + Vector2(21, 22 if _compact_settlement else 29), 13 if _compact_settlement else 15, MUTED, false)
	var gold_text := "+ " + _number(_shown_total)
	var total_size := _fit_text(gold_text, (34 if _compact_settlement else 45) + int(_total_punch * 6), total.size.x - 104)
	var number_width := _bold.get_string_size(gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1, total_size).x
	var center_x := total.get_center().x
	_coin(c, Vector2(center_x - number_width * 0.5 - 27, total.position.y + (43 if _compact_settlement else 66)), 15 if _compact_settlement else 18)
	_text(c, gold_text, Vector2(center_x + 12, total.position.y + (57 if _compact_settlement else 82)), total_size, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	if _settlement_done:
		_draw_celebration(c)


func _draw_result_row(c: Control, index: int) -> void:
	var r := _row_rects[index]
	var row := _rows[index]
	var progress := _row_progress[index]
	var revealed := progress > 0
	var finished := progress >= 1
	var tier := int(row.get("tier", -1))
	var color: Color = GEM_COLORS[clampi(tier, 0, 5)] if tier >= 0 else Color("a2b7bd")
	var alpha := 1.0 if revealed else 0.25
	var flash := sin(clampf(progress * 2.0, 0, 1) * PI)
	c.draw_style_box(_flat(Color("102c37").lerp(color.darkened(0.70), flash * 0.55), 8), r)
	if revealed:
		c.draw_line(r.position + Vector2(2, 10), r.position + Vector2(2, r.size.y - 10), Color(color, 0.7), 3)
	if tier >= 0:
		_gem(c, r.position + Vector2(26, 17 if _compact_settlement else 27), (11 if _compact_settlement else 14) * (1 + flash * 0.15), Color(color, alpha))
	else:
		_stone(c, r.position + Vector2(26, 17 if _compact_settlement else 27), 11 if _compact_settlement else 14, alpha)
	var label := str(row.get("label", RARITY_NAMES[tier] if tier >= 0 else "돌 조각"))
	_text(c, label, r.position + Vector2(52, 23), 16, Color(TEXT, alpha))
	var formula := "%s개 × %s G" % [_number(int(row.get("count", 0))), _number(int(row.get("unit_gold", 0)))]
	_text(c, formula, r.position + (Vector2(118, 23) if _compact_settlement else Vector2(52, 43)), 13 if _compact_settlement else 14, Color(MUTED, alpha), false)
	var eased := 1.0 - pow(1.0 - clampf(progress / 0.84, 0, 1), 3)
	var amount := int(round(int(row.get("gold", 0)) * eased))
	_text(c, "+ %s G" % _number(amount), r.position + Vector2(r.size.x - 17, 24 if _compact_settlement else 35), 19 if _compact_settlement else 23, Color(GOLD if finished else TEXT, alpha), true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_celebration(c: Control) -> void:
	var elapsed := _clock - _complete_clock
	if elapsed < 0 or elapsed > 1.5:
		return
	var center := _total_rect.get_center()
	var fade := pow(1 - elapsed / 1.5, 1.4)
	for i in 20:
		var angle := float(i) * 2.39996
		var distance := 54 + elapsed * (70 + (i % 5) * 19)
		var point := center + Vector2(cos(angle) * distance * 1.5, sin(angle) * distance * 0.85 + elapsed * elapsed * 28)
		var color: Color = GOLD if i % 3 != 0 else GEM_COLORS[i % 6]
		_diamond(c, point, (3 + i % 3) * fade, Color(color, fade))


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


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := _flat(Color.TRANSPARENT, radius)
	style.border_color = color
	style.set_border_width_all(width)
	return style


func _panel(c: Control, r: Rect2, color: Color, border: Color, cut: float) -> void:
	var points := PackedVector2Array([r.position + Vector2(cut, 0), r.position + Vector2(r.size.x - cut, 0), r.position + Vector2(r.size.x, cut), r.end - Vector2(0, cut), r.end - Vector2(cut, 0), r.position + Vector2(cut, r.size.y), r.position + Vector2(0, r.size.y - cut), r.position + Vector2(0, cut)])
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(0, 7))
	c.draw_colored_polygon(shadow, Color(0.01, 0.06, 0.075, 0.48))
	c.draw_colored_polygon(points, color)
	var line := points.duplicate()
	line.append(points[0])
	c.draw_polyline(line, border, 2, true)
	c.draw_line(points[0] + Vector2(0, 2), points[1] + Vector2(0, 2), border.lightened(0.14), 1)


func _gem(c: Control, center: Vector2, radius: float, color: Color) -> void:
	# A substantial, asymmetric crystal with a flat crown and broad facets.
	var p := PackedVector2Array([Vector2(-0.28, -1.1), Vector2(0.35, -1.0), Vector2(0.75, -0.36), Vector2(0.68, 0.50), Vector2(0.03, 1.12), Vector2(-0.72, 0.51), Vector2(-0.80, -0.14)])
	for i in p.size():
		p[i] = center + p[i] * radius
	var crown := center + Vector2(-0.05, -0.34) * radius
	var lower := center + Vector2(-0.10, 0.39) * radius
	var facets := [[p[0], p[1], crown], [p[1], p[2], crown], [p[2], p[3], lower, crown], [p[3], p[4], lower], [p[4], p[5], lower], [p[5], p[6], crown, lower], [p[6], p[0], crown]]
	var shades := [1.25, 0.90, 0.64, 0.40, 0.69, 0.96, 1.07]
	for i in facets.size():
		var shade: float = shades[i]
		var tint := color.lightened(shade - 1) if shade > 1 else color.darkened(1 - shade)
		tint.a = color.a
		c.draw_colored_polygon(PackedVector2Array(facets[i]), tint)
	c.draw_line(p[6], p[0], Color(color.lightened(0.6), color.a), 1, true)
	c.draw_line(p[0], p[1], Color(color.lightened(0.7), color.a), 1, true)


func _stone(c: Control, center: Vector2, radius: float, alpha: float = 1) -> void:
	var p := PackedVector2Array([Vector2(-0.84, -0.25), Vector2(-0.37, -0.88), Vector2(0.54, -0.72), Vector2(0.94, 0.18), Vector2(0.45, 0.72), Vector2(-0.65, 0.61)])
	for i in p.size():
		p[i] = center + p[i] * radius
	c.draw_colored_polygon(p, Color(Color("637981"), alpha))
	c.draw_colored_polygon(PackedVector2Array([p[0], p[1], p[2], center]), Color(Color("a4b5b7"), alpha))
	c.draw_colored_polygon(PackedVector2Array([center, p[2], p[3], p[4]]), Color(Color("4d636e"), alpha))
	c.draw_colored_polygon(PackedVector2Array([center, p[4], p[5]]), Color(Color("83959c"), alpha))


func _coin(c: Control, center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in 8:
		points.append(center + Vector2.from_angle(TAU * i / 8.0 + PI / 8) * radius)
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(0, 3))
	c.draw_colored_polygon(shadow, GOLD_DARK)
	c.draw_colored_polygon(points, GOLD)
	c.draw_arc(center, radius * 0.65, -PI * 0.95, PI * 0.65, 12, Color("e5a842"), 2, true)
	c.draw_line(center + Vector2(-3, -radius * 0.48), center + Vector2(-3, radius * 0.43), Color("fff0b0"), 2, true)
	c.draw_line(center + Vector2(3, -radius * 0.48), center + Vector2(3, radius * 0.43), Color("b7802a"), 2, true)


func _diamond(c: Control, center: Vector2, radius: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius * 1.5), center + Vector2(radius, 0), center + Vector2(0, radius * 1.5), center + Vector2(-radius, 0)]), color)
