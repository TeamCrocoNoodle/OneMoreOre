extends SceneTree
## Presentation contract: landing counts, ordered settlement, one completion,
## responsive landing targets, and an operable empty result.
const HUD = preload("res://scripts/mining_hud.gd")
var checks := 0
var failures := 0
var completions := 0
var next_requests := 0
var cues: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var hud := HUD.new()
	root.add_child(hud)
	hud.set_process(false)
	hud.settlement_animation_finished.connect(func(): completions += 1)
	hud.next_round_requested.connect(func(): next_requests += 1)
	hud.cue.connect(func(kind: String, tier: int): cues.append({"kind": kind, "tier": tier}))
	hud.begin_round(1, 100)
	hud.set_timer(30, 30, false)
	_check(hud.displayed_counts == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "New round starts with empty displayed tray")
	for tier in HUD.Rarity.COUNT:
		hud.pulse_gem(tier, tier + 1)
		_check(hud.displayed_counts[tier] == tier + 1, "Landing uses absolute confirmed quantity")
	var copy: PackedInt32Array = hud.displayed_counts
	copy[0] = 500
	_check(hud.displayed_counts[0] == 1, "Presentation snapshot cannot mutate tray")
	hud.set_stones(17)
	_check(hud.displayed_stones == 17, "Stone display follows confirmed ordinary stone count")
	for dimensions in [Vector2i(1440, 1000), Vector2i(600, 1000), Vector2i(360, 800)]:
		root.size = dimensions
		root.content_scale_size = Vector2i(1440, 1000)
		await process_frame
		var viewport_rect := root.get_visible_rect()
		var screen_scale: Vector2 = root.get_final_transform().get_scale()
		var expected_portrait: bool = dimensions.x < dimensions.y
		_check(hud._portrait == expected_portrait, "Orientation follows physical window under production expand stretch")
		var physical_font_size: float = 21.0 * hud._scale * screen_scale.y
		_check(physical_font_size >= 17.0, "Production stretch preserves readable counter size")
		if expected_portrait:
			_check(hud.playfield_bottom_screen() < viewport_rect.size.y * 0.90, "Portrait reports tray boundary for pickaxe clearance")
		else:
			_check(is_equal_approx(hud.playfield_bottom_screen(), viewport_rect.size.y), "Landscape keeps full playfield height")
		for tier in HUD.Rarity.COUNT:
			var point: Vector2 = hud.gem_target_screen(tier)
			_check(viewport_rect.has_point(point), "Gem landing target remains visible after resize")
			_check(hud.is_pointer_blocked(point), "Landing tray shields gameplay clicks")
		_check(not hud.is_pointer_blocked(viewport_rect.size * Vector2(0.50, 0.40)), "Open playfield accepts mining clicks")
	var report := {"rows": [{"kind": "stone", "tier": -1, "label": "돌 조각", "count": 17, "unit_gold": 1, "gold": 17}, {"kind": "gem", "tier": 0, "label": "일반", "count": 3, "unit_gold": 10, "gold": 30}, {"kind": "gem", "tier": 1, "label": "특별", "count": 1, "unit_gold": 50, "gold": 50}, {"kind": "gem", "tier": 2, "label": "희귀", "count": 0, "unit_gold": 200, "gold": 0}], "total": 97, "wallet_before": 100, "wallet_after": 197, "round_index": 1}
	hud.show_settlement(report)
	_check(hud.displayed_rows.size() == 3, "Only earned grades have settlement rows")
	_check(hud.is_pointer_blocked(Vector2.ZERO), "Modal shields entire viewport")
	_check(hud._skip.has_focus(), "Skip is keyboard/controller accessible immediately")
	_check(hud._skip.size.y >= 48, "Skip meets touch target height")
	_check(hud._skip.size.y * root.get_final_transform().get_scale().y >= 48, "Skip meets physical touch target height under production stretch")
	report["total"] = 999
	report["rows"][0]["gold"] = 999
	_check(hud.displayed_rows[0]["gold"] == 17, "Result uses immutable report snapshot")
	var previous := 0
	for frame in 300:
		hud._process(1.0 / 60.0)
		_check(hud.displayed_gold >= previous and hud.displayed_gold <= 97, "Count-up is monotonic and bounded by earned total")
		previous = hud.displayed_gold
	_check(hud.settlement_complete and hud.displayed_gold == 97, "Automatic settlement completes with exact amount")
	_check(completions == 1, "Automatic finish emits one completion")
	_check(hud._replay.has_focus(), "Replay receives keyboard/controller focus")
	_check(hud._replay.size.y >= 48, "Replay meets touch target height")
	var order: Array[int] = []
	for event in cues:
		if event.kind == "row":
			order.append(event.tier)
	_check(order == [-1, 0, 1], "Audio announces stone then earned grades in result order")
	hud.finish_settlement()
	hud.finish_settlement()
	_check(completions == 1, "Repeated skip cannot duplicate completion")
	hud._request_next()
	hud._request_next()
	_check(next_requests == 1, "Repeated replay cannot request two rounds")
	hud.begin_round(2, 197)
	_check(not hud.settlement_visible and not hud.settlement_complete, "Next round clears modal state")
	_check(hud.displayed_stones == 0 and hud.displayed_counts == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "Next round clears both resource displays")
	hud.show_settlement({"rows": [], "total": 0, "wallet_before": 197, "wallet_after": 197})
	hud.finish_settlement()
	_check(completions == 2 and hud.displayed_gold == 0 and hud.settlement_complete, "Empty result can finish and proceed")
	_check(hud._replay.has_focus() and hud._replay.visible, "Empty result retains accessible replay")
	for dimensions in [Vector2i(900, 600), Vector2i(800, 450), Vector2i(600, 1000), Vector2i(360, 800)]:
		root.size = dimensions
		await process_frame
		for row_count in [3, 8, 10]:
			var rows: Array[Dictionary] = []
			for i in row_count:
				rows.append({"kind": "stone" if i == 0 else "boss" if i == 9 else "bonus" if i == 8 else "gem", "tier": i - 1 if i < 8 else -1, "label": "돌 조각" if i == 0 else "보스 처치 보상" if i == 9 else "채굴 보너스" if i == 8 else HUD.RARITY_NAMES[i - 1], "count": 10, "unit_gold": 100, "gold": 1000})
			hud.show_settlement({"rows": rows, "total": row_count * 1000, "wallet_before": 0, "wallet_after": row_count * 1000})
			hud.finish_settlement()
			var bounds := root.get_visible_rect()
			var panel_bounds := Rect2(hud._modal_rect.position * hud._scale, hud._modal_rect.size * hud._scale)
			_check(bounds.encloses(panel_bounds), "Result including seven ranks, stone, skill bonus and boss bounty fits physical viewport")
			_check(bounds.encloses(hud._replay.get_global_rect()), "Replay remains inside short landscape and portrait")
			_check(hud._replay.size.y * root.get_final_transform().get_scale().y >= 48, "Compact result preserves physical touch height")
		_check(not hud._wallet_rect.intersects(hud._timer_rect), "Wallet and timer remain distinct on narrow windows")
	print("MINING_HUD_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
