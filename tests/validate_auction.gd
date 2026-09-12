extends SceneTree
const Auction = preload("res://scripts/ore_auction.gd")
const Round = preload("res://scripts/mining_round.gd")
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_distribution()
	_check_ledger()
	root.size = Vector2i(1152, 800)
	root.content_scale_size = Vector2i(1440, 1000)
	AudioServer.set_bus_mute(0, true)
	game = Main.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pickaxe.set_process(false)
	game.hud.set_process(false)
	await process_frame
	await _check_flow()
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	print("AUCTION_VALIDATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_distribution() -> void:
	for protected in [false, true]:
		var counts := [0, 0, 0, 0, 0]
		for ticket in (77 if protected else 100):
			counts[Auction.outcome_for_ticket(ticket, protected)] += 1
		_check(counts == ([0, 25, 25, 25, 2] if protected else [23, 25, 25, 25, 2]), "Every equiprobable integer ticket yields the exact specified weight, with conditional protection")
	_check(Auction.outcome_for_ticket(-1, false) == -1 and Auction.outcome_for_ticket(77, true) == -1, "Out-of-range tickets cannot become a hidden extra outcome")
	var auction := Auction.new()
	auction.rng.seed = 39113
	var previous := -1
	var no_streak := true
	var seen := [false, false, false, false, false]
	for i in 5000:
		var result := auction.draw(101)
		no_streak = no_streak and not (previous == 0 and int(result.index) == 0)
		previous = int(result.index)
		seen[previous] = true
	_check(no_streak and not seen.has(false), "Real seeded draws produce every result and never consecutive total losses")
	var rng_state := auction.rng.state
	var protection := auction.previous_total_loss
	_check(auction.draw(0).is_empty() and auction.draw(-1).is_empty() and auction.rng.state == rng_state and auction.previous_total_loss == protection, "Empty stakes consume neither randomness nor loss protection")

func _paid_round(state: RefCounted, wallet: int = 777) -> void:
	state.wallet_gold = wallet
	state.start()
	for i in 21:
		state.record_stone()
	for i in 3:
		state.record_gem(0)
	state.record_gem(1)
	state.advance(30.0)
	state.begin_settlement()
	state.commit_settlement()

func _seed_for(index: int, protected: bool = false) -> int:
	var rng := RandomNumberGenerator.new()
	for seed_value in 10000:
		rng.seed = seed_value
		if Auction.outcome_for_ticket(rng.randi_range(0, 76 if protected else 99), protected) == index:
			return seed_value
	return -1

func _check_ledger() -> void:
	var payouts := [0, 50, 151, 202, 303]
	for index in 5:
		var state := Round.new()
		_check(not state.can_auction() and state.begin_auction().is_empty(), "Auction cannot run before settlement")
		_paid_round(state)
		_check(state.wallet_gold == 878 and state.can_auction(), "Only a paid nonempty settlement can be auctioned")
		state.auction.rng.seed = _seed_for(index)
		var result := state.begin_auction()
		_check(result.index == index and result.payout == payouts[index], "All five changes apply to 101 Gold, with integer half-Gold rounded down")
		result.payout = 9999999
		_check(state.wallet_gold == 878 and not state.new_round() and state.begin_auction().is_empty() and not state.commit_settlement(), "Drawing locks the round and neither pays early nor permits a reroll or duplicate settlement")
		_check(state.commit_auction() and state.wallet_gold == 777 + payouts[index], "Commit applies just the adjustment and preserves the older 777 Gold")
		_check(not state.commit_auction() and not state.can_auction() and state.begin_auction().is_empty() and state.wallet_gold == 777 + payouts[index], "Repeated signals cannot pay or stake this settlement twice")
		_check(state.last_report.total == 101 and state.last_report.final_total == payouts[index], "Report preserves both cargo valuation and auction payout")
		state.new_round()
		_check(state.auction.previous_total_loss == (index == 0), "Loss protection survives the next-round reset")
		if index == 0:
			state.start()
			state.advance(30)
			state.begin_settlement()
			state.commit_settlement()
			_check(not state.can_auction() and state.auction.previous_total_loss, "Passing an empty round cannot consume protection")
			state.new_round()
			_paid_round(state)
			state.auction.rng.seed = _seed_for(0)
			_check(state.begin_auction().index != 0, "A seed that lost previously is safely mapped to the protected draw")
	var spent := Round.new()
	_paid_round(spent)
	spent.wallet_gold = 100
	_check(not spent.can_auction() and spent.begin_auction().is_empty(), "Spending below the whole stake cannot create a negative wallet")

func _settle_game() -> void:
	game.round_state.wallet_gold = 777
	game.round_state.start()
	for i in 21:
		game.round_state.record_stone()
	for i in 3:
		game.round_state.record_gem(0)
	game.round_state.record_gem(1)
	game.round_state.advance(30)
	game._begin_settlement()
	game.hud.finish_settlement()

func _check_flow() -> void:
	var hud: Node = game.hud
	var ui: Control = hud.auction_ui
	var payouts := [0, 50, 151, 202, 303]
	for index in 5:
		_settle_game()
		game.round_state.auction.previous_total_loss = false
		game.round_state.auction.rng.seed = _seed_for(index)
		var before_rng: int = game.round_state.auction.rng.state
		await _click(hud._auction.get_global_rect().get_center())
		ui.set_process(false)
		_check(ui.is_open and ui.mode == ui.Mode.PREVIEW and game.round_state.auction.rng.state == before_rng, "Actual auction button opens an offer without spending or drawing")
		if index == 0:
			await _click(ui._cancel.get_global_rect().get_center())
			_check(not ui.is_open and game.round_state.wallet_gold == 878 and game.round_state.auction.rng.state == before_rng, "Cancel before starting preserves Gold and randomness")
			await _click(hud._auction.get_global_rect().get_center())
			ui.set_process(false)
			await _joy(JOY_BUTTON_B)
			_check(not ui.is_open and game.round_state.auction.rng.state == before_rng, "Controller back closes only the preview without drawing")
			await _click(hud._auction.get_global_rect().get_center())
			ui.set_process(false)
			for dimensions in [Vector2i(360, 800), Vector2i(800, 450)]:
				root.size = dimensions
				await process_frame
				_check(root.get_visible_rect().encloses(ui._confirm.get_global_rect()) and root.get_visible_rect().encloses(ui._cancel.get_global_rect()), "Both offer actions fit portrait and short landscape")
				_check(ui._confirm.size.y * root.get_final_transform().get_scale().y >= 47, "Auction actions retain physical touch size")
			root.size = Vector2i(1152, 800)
			await process_frame
		if index == 0:
			await _joy(JOY_BUTTON_A)
		else:
			await _tap(ui._confirm.get_global_rect().get_center())
		ui.set_process(false)
		_check(ui.mode == ui.Mode.ROLLING and game.round_state.phase == Round.Phase.AUCTION, "Actual touch/controller confirm starts one authoritative auction")
		var pending: Dictionary = game.round_state._pending_auction.duplicate(true)
		game._start_auction()
		game._next_round()
		game._open_upgrades()
		ui.close()
		_check(game.round_state._pending_auction == pending and not game.skill_ui.is_open and ui.is_open, "Retry, replay, upgrades, and cancel cannot bypass an in-progress draw")
		if index == 2:
			ui._process(4.0)
		else:
			ui.finish_reveal()
		ui.finish_reveal()
		game._finish_auction()
		_check(ui.mode == ui.Mode.RESULT and game.round_state.phase == Round.Phase.COMPLETE and hud.displayed_gold == payouts[index] and game.round_state.wallet_gold == 777 + payouts[index], "Natural and skipped reveal settle the exact outcome once through Main")
		await _click(ui._confirm.get_global_rect().get_center())
		_check(not ui.is_open and not hud._auction.visible and hud._replay.has_focus(), "Returning shows the adjusted settlement and restores safe replay focus")
		await _click(hud._replay.get_global_rect().get_center())
		_check(game.round_state.phase == Round.Phase.READY and not hud.settlement_visible, "Actual replay button starts a fresh round after each outcome")

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _tap(point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 6
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _joy(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		_stop_audio(child)
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AUCTION_CHECK_FAILED: " + description)
