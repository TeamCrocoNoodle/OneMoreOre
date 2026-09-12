extends Control
## Bids are presentation; the round ledger supplies one immutable result.

signal start_requested
signal presentation_finished
signal closed

const Auction = preload("res://scripts/ore_auction.gd")
const COLORS := [Color("cf8275"), Color("caa58a"), Color("8ec7ad"), Color("e7b965"), Color("ffe09b")]
const ROLL_SECONDS := 2.8
const COUNT_SECONDS := 0.85
enum Mode { PREVIEW, ROLLING, RESULT }

var host: Node
var is_open := false
var mode := Mode.PREVIEW
var result: Dictionary = {}
var _stake := 0
var _time := 0.0
var _result_age := 0.0
var _last_step := -1
var _outcome := -1
var _reveal_cued := false
var _paid_signal := false
var _amount := 0
var _view := Vector2(1200, 850)
var _scale := 1.0
var _panel := Rect2()
var _confirm: Button
var _cancel: Button


func _ready() -> void:
	name = "Auction"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm = host._button("경매 시작", true)
	_confirm.reparent(self)
	_confirm.name = "ConfirmAuction"
	_confirm.pressed.connect(_accept)
	_cancel = host._button("돌아가기", false)
	_cancel.reparent(self)
	_cancel.name = "CancelAuction"
	_cancel.pressed.connect(close)
	hide()
	set_process(false)
	set_process_unhandled_input(false)


func set_layout(view: Vector2, ui_scale: float) -> void:
	_view = view
	_scale = ui_scale
	size = view * _scale
	var width := minf(860, view.x - 40)
	var height := minf(550, view.y - 40)
	_panel = Rect2((view - Vector2(width, height)) * 0.5, Vector2(width, height))
	if is_instance_valid(_confirm):
		_layout_buttons()
	queue_redraw()


func _layout_buttons() -> void:
	var both := mode == Mode.PREVIEW
	var width := minf(270, (_panel.size.x - 36) * (0.5 if both else 1.0))
	var y := _panel.end.y - 66
	_confirm.position = Vector2(_panel.get_center().x + (9 if both else -width * 0.5), y) * _scale
	_confirm.size = Vector2(width, 56) * _scale
	_cancel.position = Vector2(_panel.get_center().x - width - 9, y) * _scale
	_cancel.size = Vector2(width, 56) * _scale
	for button in [_confirm, _cancel]:
		button.add_theme_font_size_override("font_size", int((18 if _panel.size.x < 440 else 20) * _scale))
		var other: Button = _cancel if button == _confirm and both else _confirm
		button.focus_neighbor_left = other.get_path()
		button.focus_neighbor_right = other.get_path()
		button.focus_neighbor_top = other.get_path()
		button.focus_neighbor_bottom = other.get_path()
		button.focus_next = other.get_path()
		button.focus_previous = other.get_path()


func show_offer(stake: int) -> void:
	if is_open or stake <= 0:
		return
	_stake = stake
	_amount = stake
	result.clear()
	mode = Mode.PREVIEW
	_outcome = -1
	_time = 0.0
	_result_age = 0.0
	_reveal_cued = false
	_paid_signal = false
	is_open = true
	show()
	_confirm.text = "경매 시작"
	_cancel.show()
	_layout_buttons()
	_confirm.grab_focus()
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func play_result(snapshot: Dictionary) -> void:
	if not is_open or mode != Mode.PREVIEW or snapshot.is_empty():
		return
	result = snapshot.duplicate(true)
	mode = Mode.ROLLING
	_time = 0.0
	_last_step = -1
	_cancel.hide()
	_confirm.text = "결과 바로 보기"
	_layout_buttons()
	_confirm.grab_focus()
	host.cue.emit("auction_open", 0)
	queue_redraw()


func _accept() -> void:
	if not is_open:
		return
	if mode == Mode.PREVIEW:
		start_requested.emit()
	elif mode == Mode.ROLLING:
		finish_reveal()
	else:
		close()


func finish_reveal() -> void:
	if mode != Mode.ROLLING or not is_open:
		return
	_time = ROLL_SECONDS + COUNT_SECONDS
	_process(0.0)


func close() -> void:
	# A committed draw has no cancel path. Skipping reveals that same result.
	if not is_open or mode == Mode.ROLLING:
		return
	is_open = false
	hide()
	_confirm.release_focus()
	_cancel.release_focus()
	set_process(false)
	set_process_unhandled_input(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	_time += maxf(delta, 0.0)
	if mode == Mode.ROLLING:
		var roll := clampf(_time / ROLL_SECONDS, 0.0, 1.0)
		var step := floori((1.0 - pow(1.0 - roll, 3)) * (25 + int(result.index)))
		_outcome = step % 5 if roll < 1.0 else int(result.index)
		if roll < 1.0:
			_amount = _payout_for(_outcome)
			if step != _last_step:
				_last_step = step
				host.cue.emit("auction_bid", mini(5, floori(roll * 6)))
		else:
			if not _reveal_cued:
				_reveal_cued = true
				var kind := "auction_jackpot" if _outcome == 4 else ("auction_win" if _outcome >= 2 else "auction_loss")
				host.cue.emit(kind, _outcome)
			var progress := clampf((_time - ROLL_SECONDS) / COUNT_SECONDS, 0.0, 1.0)
			_amount = roundi(lerpf(float(_stake), float(result.payout), 1.0 - pow(1.0 - progress, 3)))
			_result_age = _time - ROLL_SECONDS
			if progress >= 1.0:
				mode = Mode.RESULT
				_amount = int(result.payout)
				_confirm.text = "정산으로 돌아가기"
				if not _paid_signal:
					_paid_signal = true
					presentation_finished.emit()
	elif mode == Mode.RESULT:
		_result_age += maxf(delta, 0.0)
	queue_redraw()


func _payout_for(index: int) -> int:
	return _stake * (100 + int(Auction.CHANGES[index])) / 100


func _draw() -> void:
	if not is_open:
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _scale)
	draw_rect(Rect2(Vector2.ZERO, _view), Color(0.020, 0.026, 0.025, 0.97))
	var center := _panel.get_center().x
	var revealed := mode == Mode.RESULT or (mode == Mode.ROLLING and _time >= ROLL_SECONDS)
	var tint: Color = COLORS[_outcome] if _outcome >= 0 else host.GOLD
	var title := "원석 경매"
	if revealed:
		title = "최고가 낙찰!" if _outcome == 4 else ("낙찰!" if _outcome >= 2 else "경매 종료")
	_label(title, Vector2(center, _panel.position.y + 40), 32, tint if revealed else host.GOLD)
	_label("이번 정산  %s G" % host._number(_stake), Vector2(center, _panel.position.y + 71), 15, host.MUTED, false)
	var baseline := _panel.position.y + _panel.size.y * 0.445
	var pulse := maxf(0, 1 - _result_age * 2.8) if revealed else 0.0
	if revealed and _outcome >= 2:
		_draw_reward(Vector2(center, baseline - 24), tint)
	if _outcome >= 0:
		_label(_change(_outcome), Vector2(center, baseline - 66), int(35 + pulse * 7), tint)
	else:
		_label("경매에 올릴 GOLD", Vector2(center, baseline - 66), 16, host.TEXT)
	_money(_amount, Vector2(center, baseline), int((54 if _panel.size.x < 440 else 70) + pulse * 5), 27 + pulse * 3, host.TEXT if _outcome < 0 else tint, _panel.size.x - 36)
	var caption := "이번 정산 금액 전액으로 한 번 참여합니다"
	if mode == Mode.ROLLING and not revealed:
		caption = "입찰 진행 중" + ".".repeat(1 + int(_time * 3) % 3)
	elif revealed:
		caption = "최종 획득 GOLD" if _outcome != 0 else "이번 정산 금액을 모두 잃었습니다"
	_label(caption, Vector2(center, baseline + 40), 14, host.MUTED, false)
	var gap := 6.0
	var chip_width := (_panel.size.x - 12 - gap * 4) / 5.0
	var y := _panel.position.y + _panel.size.y * 0.64
	for index in 5:
		var rect := Rect2(_panel.position.x + 6 + index * (chip_width + gap), y, chip_width, 66)
		var selected := _outcome == index
		draw_rect(rect, Color(COLORS[index], 0.13 if selected else 0.035))
		if selected:
			draw_line(Vector2(rect.position.x, rect.end.y), rect.end, COLORS[index], 2)
		var alpha := 1.0 if not revealed or selected else 0.30
		_label(_change(index), Vector2(rect.get_center().x, rect.position.y + 27), 19 if chip_width < 85 else 23, Color(COLORS[index], alpha))
		_money(_payout_for(index), Vector2(rect.get_center().x, rect.position.y + 52), 14, 7, Color(host.TEXT, alpha), chip_width - 8, alpha)
	if mode == Mode.PREVIEW:
		_label("가능한 정산 결과", Vector2(center, y - 12), 13, host.MUTED, false)
	draw_set_transform(Vector2.ZERO)


func _draw_reward(center: Vector2, tint: Color) -> void:
	var fade := clampf(1.0 - _result_age / 2.2, 0, 1)
	if fade <= 0.0:
		return
	var count := 22 if _outcome == 4 else 12
	for index in count:
		var angle := float(index) * 2.39996
		var distance := 48.0 + _result_age * (70 + index % 4 * 19)
		var point := center + Vector2(cos(angle) * distance, sin(angle) * distance * 0.64 + _result_age * _result_age * 28)
		host._coin(self, point, (4 + index % 4) * fade, Color(1, 1, 1, fade * 0.9))
	if _outcome == 4:
		for index in 10:
			var angle := index * TAU / 10 + 0.2
			var near_point := center + Vector2.from_angle(angle) * 68
			var far_point := center + Vector2.from_angle(angle) * (142 + _result_age * 22)
			var side := Vector2.from_angle(angle + PI * 0.5) * 12
			draw_colored_polygon(PackedVector2Array([near_point, far_point - side, far_point + side]), Color(tint, fade * 0.08))


func _change(index: int) -> String:
	var value: int = Auction.CHANGES[index]
	return ("+" if value > 0 else "") + str(value) + "%"


func _label(text: String, baseline: Vector2, font_size: int, color: Color, bold: bool = true) -> void:
	host._text(self, text, baseline, font_size, color, bold, HORIZONTAL_ALIGNMENT_CENTER)


func _money(value: int, baseline: Vector2, font_size: int, radius: float, color: Color, max_width: float, alpha: float = 1.0) -> void:
	var text: String = host._number(value)
	var fitted: int = host._fit_text(text, font_size, max_width - radius * 2 - 9)
	var width: float = host._bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x
	var left := baseline.x - (width + radius * 2 + 9) * 0.5
	host._coin(self, Vector2(left + radius, baseline.y - fitted * 0.35), radius, Color(1, 1, 1, alpha))
	host._text(self, text, Vector2(left + radius * 2 + 9, baseline.y), fitted, color)
