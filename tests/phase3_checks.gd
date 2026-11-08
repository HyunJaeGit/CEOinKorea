## Phase 3 시간·출장·뉴스·비용·저장 및 Phase 2 거래 회귀를 격리 검사한다.
extends Node

const Clock = preload("res://game/core/game_clock.gd")
var failure_count := 0

func _ready() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	GameSession.save_path = "user://phase3_checks/session.json"
	_check_clock_and_calendar()
	_check_pause_tokens()
	_check_research_and_cargo()
	_check_news_and_daily_economy()
	_check_invoice_once()
	_check_save_restore_and_trade_regression()
	if failure_count == 0:
		print("PHASE3_CHECKS_OK: 6 groups")
	else:
		printerr("PHASE3_CHECKS_FAILED: %d checks" % failure_count)
	get_tree().quit(0 if failure_count == 0 else 1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failure_count += 1
		printerr("CHECK_FAILED: %s" % description)

func _same_state(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(left), float(right))
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _same_state(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _same_state(left[index], right[index]):
				return false
		return true
	return left == right

func _fresh() -> void:
	GameSession._reset_new_game_state()
	GameSession.save_path = "user://phase3_checks/session.json"

func _check_clock_and_calendar() -> void:
	var clock = Clock.new()
	clock.advance(600.0)
	_expect(clock.get_date_string() == "2025-02-20", "600 active seconds reach the next monthly anniversary")
	clock = Clock.new()
	clock.start_date = {"year": 2023, "month": 1, "day": 31, "hour": 0, "minute": 0, "second": 0}
	_expect(clock.get_date_string(clock.anniversary_timestamp(1)) == "2023-02-28", "Jan 31 anniversary clamps to February")
	_expect(clock.get_date_string(clock.anniversary_timestamp(2)) == "2023-03-31", "original contract day is preserved after clamp")
	clock.start_date = {"year": 2024, "month": 1, "day": 31, "hour": 0, "minute": 0, "second": 0}
	_expect(clock.get_date_string(clock.anniversary_timestamp(1)) == "2024-02-29", "leap February is respected")

func _check_pause_tokens() -> void:
	_fresh()
	GameSession.set_pause_reason("dialog", true)
	GameSession.set_pause_reason("archive", true)
	GameSession.set_pause_reason("dialog", false)
	_expect(GameSession.pause_reasons.has("archive"), "closing one overlay preserves the other pause token")
	GameSession.set_pause_reason("archive", false)
	_expect(GameSession.pause_reasons.is_empty(), "all active pause tokens can resume time")

func _check_research_and_cargo() -> void:
	_fresh()
	var no_confirmation := GameSession.assign_research("survey-a", "incheon", false, true)
	_expect(no_confirmation.get("reason") == "companion_confirmation_required", "companion departure confirmation required")
	var started := GameSession.assign_research("survey-a", "incheon", true, true)
	_expect(started.ok and started.cost == 5000 and started.duration_days == 2, "survey uses confirmed cost and duration")
	_expect(GameSession.assign_research("survey-a", "incheon", true, true).get("reason") == "duplicate_order", "duplicate trip command is rejected")
	_expect(not GameSession.party_ids.has("staff_01"), "survey employee leaves companion party")
	_expect(GameSession.cancel_research("survey-a").ok, "active trip can be cancelled")
	_expect(GameSession.accounts.corporate == 995000, "cancellation does not refund departure cost")
	_fresh()
	GameSession.inventories.staff_01["seafood"] = 1
	GameSession.inventory_costs.staff_01["seafood"] = [100]
	_expect(GameSession.assign_research("survey-cargo", "incheon", true, true).get("reason") == "cargo_not_transferred", "employee cargo must be transferred before departure")
	_expect(GameSession.transfer_goods("staff_01", "player", "seafood", 1).ok, "employee cargo can be transferred while co-located")
	var after_transfer := GameSession.assign_research("survey-after-transfer", "incheon", true, true)
	_expect(after_transfer.ok, "trip can begin after cargo transfer")
	GameSession._complete_research_tasks(int(after_transfer.completion_day))
	_expect(GameSession.market_reports.size() == 1 and GameSession.staff_tasks["survey-after-transfer"].status == "completed", "arrival creates one dated report snapshot")
	var observed_stock: int = GameSession.market_reports[0].snapshots[0].stock
	GameSession.market_states["incheon_seafood:seafood"].stock += 1
	_expect(GameSession.market_reports[0].snapshots[0].stock == observed_stock, "report remains a frozen observation")
	GameSession._complete_research_tasks(int(after_transfer.completion_day))
	_expect(GameSession.market_reports.size() == 1, "completed survey does not report twice")

func _check_news_and_daily_economy() -> void:
	_fresh()
	var event: Dictionary = GameSession.event_definitions["logistics_disruption_202502"]
	var start_day := GameSession._date_to_timestamp(str(event.start_date))
	var before_stock := GameSession.get_market_stock("seoul_electronics", "electronics")
	GameSession.game_clock.mark_day_processed(start_day - 86400)
	GameSession._process_game_day(start_day)
	_expect(GameSession.pending_news_ids.count(event.id) == 1, "scheduled news queues exactly once")
	_expect(GameSession.event_states[event.id].active, "news factor activates on start date")
	_expect(is_equal_approx(GameSession._event_factor("seoul", "electronics", "supply_factor"), 0.5), "news factor changes market supply")
	GameSession._update_event_schedule(start_day)
	_expect(GameSession.pending_news_ids.count(event.id) == 1, "reprocessing the event date does not queue duplicate news")
	_expect(GameSession.get_market_stock("seoul_electronics", "electronics") != before_stock, "daily supply/consumption updates market stock")
	var end_day := start_day + int(event.duration_days) * 86400
	GameSession._process_game_day(end_day)
	_expect(not GameSession.event_states[event.id].active and GameSession.event_states[event.id].ended, "news factor ends after configured duration")
	_expect(is_equal_approx(GameSession._event_factor("seoul", "electronics", "supply_factor"), 1.0), "event effect returns to normal after end date")

func _check_invoice_once() -> void:
	_fresh()
	var due := GameSession.contract_start_timestamp + 31 * 86400
	GameSession._process_office_invoice(due)
	var expected := 1000000 - 180000
	_expect(GameSession.accounts.corporate == expected, "monthly rent and salary debit corporate account once")
	GameSession._process_office_invoice(due)
	_expect(GameSession.accounts.corporate == expected, "invoice ID prevents duplicate billing")

func _check_save_restore_and_trade_regression() -> void:
	_fresh()
	GameSession.current_region = "incheon"
	var bought := GameSession.execute_trade("phase3-regression-buy", "incheon_seafood", "seafood", "buy", "player", 1)
	_expect(bought.ok, "existing Phase 2 trade path still succeeds")
	_expect(GameSession.save_game(), "phase 3 isolated save succeeds")
	var snapshot: Dictionary = GameSession._make_payload().duplicate(true)
	GameSession.accounts.corporate = 0
	_expect(GameSession.load_game(), "phase 3 save reload succeeds")
	_expect(_same_state(snapshot, GameSession._make_payload()), "clock, market, account, cargo and ledger restore")
