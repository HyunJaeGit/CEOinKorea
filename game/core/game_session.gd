## 거래·계좌·화물·시장 상태를 소유하고 버전 저장 및 복구를 처리한다.
extends Node

signal state_changed
signal clock_changed
signal reports_changed
signal alert_received(message: String)

const SAVE_PATH := "user://saves/phase1_save.json"
const SCHEMA_VERSION := 5
const LEGACY_SCHEMA_VERSION := 1
const PHASE2_SCHEMA_VERSION := 2
const PREVIOUS_SCHEMA_VERSION := 3
const PHASE4_SCHEMA_VERSION := 4
const GameClockScript = preload("res://game/core/game_clock.gd")
const BattleRules = preload("res://game/combat/battle_rules.gd")
const REGION_IDS := ["seoul", "incheon", "suwon", "cheonan"]
const STARTING_PERSONAL_CASH := 100000
const STARTING_CORPORATE_CASH := 1000000
const STARTING_CAPITAL := 1000000
const PERSON_CAPACITY_G := 20000
const TRADE_SPREAD := 0.05
const MIN_PRICE_FACTOR := 0.5
const MAX_PRICE_FACTOR := 3.0

var save_path: String = SAVE_PATH
var current_region: String = "seoul"
var player_position: Vector2 = Vector2(930.0, 470.0)
var party_ids: Array[String] = ["player", "staff_01"]
var accounts: Dictionary = {}
var contribution_principal: int = STARTING_CAPITAL
var retained_realized_profit: int = 0
var ledger: Array[Dictionary] = []
var inventories: Dictionary = {}
var inventory_costs: Dictionary = {}
var market_states: Dictionary = {}
var processed_order_ids: Array[String] = []
var products: Dictionary = {}
var market_definitions: Dictionary = {}
var region_definitions: Dictionary = {}
var event_definitions: Dictionary = {}
var office_rules: Dictionary = {}
var vehicle_definitions: Dictionary = {}
var mercenary_definitions: Dictionary = {}
var enemy_definitions: Dictionary = {}
var owned_vehicle_ids: Array[String] = []
var active_vehicle_id := ""
var vehicle_cost_remainders: Dictionary = {}
var travel_meter_remainder := 0.0
var parked_vehicles: Array[Dictionary] = []
var cargo_caches: Array[Dictionary] = []
var mercenaries: Dictionary = {}
var mercenary_roster: Array[String] = []
var free_revival_date := ""
var battle_state: Dictionary = {}
var captivity_state: Dictionary = {}
var processed_result_ids: Array[String] = []
var rescue_debts: Array[Dictionary] = []
var enemy_states: Dictionary = {}
var enemy_grace_seconds_remaining := 0.0
var game_clock = GameClockScript.new()
var pause_reasons: Dictionary = {}
var employee_states: Dictionary = {}
var staff_tasks: Dictionary = {}
var market_reports: Array[Dictionary] = []
var event_states: Dictionary = {}
var pending_news_ids: Array[String] = []
var processed_invoice_ids: Array[String] = []
var unpaid_invoices: Array[Dictionary] = []
var daily_alerts: Array[String] = []
var contract_start_timestamp: int = 0
var contract_day: int = 20
var rng_state: int = 20250120
var news_overlay_open: bool = false
var clock_autosave_seconds: float = 0.0
var is_processing_day: bool = false
var queued_daily_alerts: Array[String] = []
var office_tier := "rented_base"
var office_purchase_price := 0
var general_loans: Array[Dictionary] = []
var general_loan_arrears := 0
var staff_counter := 1
var mahjong_fatigue := 0
var mahjong_unlocked_levels: Array[String] = ["beginner"]
var mahjong_state: Dictionary = {}
var processed_mahjong_rewards: Array[String] = []
var settings := {"fullscreen": false, "master_volume": 1.0, "ui_scale": 1.0}


func _ready() -> void:
	_load_definitions()
	_reset_new_game_state()
	if OS.get_cmdline_user_args().has("--phase2-tests"):
		save_path = "user://phase2_checks/session.json"
	elif OS.get_cmdline_user_args().has("--phase3-tests"):
		save_path = "user://phase3_checks/session.json"
	elif OS.get_cmdline_user_args().has("--phase4-tests"):
		save_path = "user://phase4_checks/session.json"
	elif OS.get_cmdline_user_args().has("--phase5-tests"):
		save_path = "user://phase5_checks/session.json"
	elif OS.get_cmdline_user_args().has("--p0-tests"):
		save_path = "user://p0_checks/session.json"
	load_game()
	call_deferred("_show_next_pending_news")


func _process(delta: float) -> void:
	_ensure_time_hud()
	if not _is_normal_time_scene() or not pause_reasons.is_empty():
		return
	game_clock.advance(delta)
	var current_day := game_clock.get_current_day_start()
	var processed_any := false
	while game_clock.next_unprocessed_day() <= current_day:
		var day_timestamp := game_clock.next_unprocessed_day()
		_process_game_day(day_timestamp)
		game_clock.mark_day_processed(day_timestamp)
		processed_any = true
		clock_changed.emit()
		if not save_game():
			alert_received.emit("게임 날짜 저장에 실패했습니다. 기존 저장을 유지합니다.")
	if processed_any:
		_show_next_pending_news()
	clock_autosave_seconds += delta
	if clock_autosave_seconds >= 10.0:
		clock_autosave_seconds = 0.0
		save_game()
		clock_changed.emit()


func _load_definitions() -> void:
	products = _read_json_array("res://data/products.json", "id")
	market_definitions = _read_json_array("res://data/markets.json", "id")
	region_definitions = _read_json_collection("res://data/regions.json", "regions", "id")
	event_definitions = _read_json_array("res://data/events.json", "id")
	vehicle_definitions = _read_json_array("res://data/vehicles.json", "id")
	mercenary_definitions = _read_json_array("res://data/mercenaries.json", "id")
	enemy_definitions = _read_json_array("res://data/enemies.json", "id")
	var rules_file := FileAccess.open("res://data/office_rules.json", FileAccess.READ)
	if rules_file != null:
		var rules: Variant = JSON.parse_string(rules_file.get_as_text())
		rules_file.close()
		if rules is Dictionary:
			office_rules = rules


func _read_json_collection(path: String, collection_key: String, id_key: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var result: Dictionary = {}
	if parsed is Dictionary:
		for entry in parsed.get(collection_key, []):
			if entry is Dictionary and entry.has(id_key):
				result[str(entry[id_key])] = entry
	return result


func _read_json_array(path: String, key: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var result: Dictionary = {}
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has(key):
				result[str(entry[key])] = entry
	return result


## 새 시장 상태만 기본값으로 보충하고 기존 시장 시세·재고는 보존한다.
func _make_initial_market_state(market_id: String, product_id: String) -> Dictionary:
	var market: Dictionary = market_definitions[market_id]
	var product: Dictionary = products[product_id]
	var region_prices: Dictionary = product.get("regions", {})
	var base := float(product["base_price"]) * float(region_prices.get(str(market["region_id"]), 1.0))
	return {
		"stock": int(market["initial_stock"]), "target_stock": int(market["target_stock"]), "reference_stock": int(market["initial_stock"]),
		"reference_price": base, "base_price": base, "production_remainder": 0.0, "consumption_remainder": 0.0, "trend_percent": 0.0, "trend_days": 0, "price_history": [],
	}


func _reset_new_game_state() -> void:
	current_region = "seoul"
	player_position = Vector2(930.0, 470.0)
	party_ids = ["player", "staff_01"]
	accounts = {"personal": STARTING_PERSONAL_CASH, "corporate": STARTING_CORPORATE_CASH}
	contribution_principal = STARTING_CAPITAL
	retained_realized_profit = 0
	ledger = [
		{"id": "opening-personal", "kind": "opening_balance", "account": "personal", "amount": STARTING_PERSONAL_CASH},
		{"id": "opening-corporate", "kind": "opening_balance", "account": "corporate", "amount": STARTING_CORPORATE_CASH},
	]
	inventories = {"player": {}, "staff_01": {}}
	inventory_costs = {"player": {}, "staff_01": {}}
	processed_order_ids.clear()
	owned_vehicle_ids.clear()
	active_vehicle_id = ""
	vehicle_cost_remainders.clear()
	travel_meter_remainder = 0.0
	parked_vehicles.clear()
	cargo_caches.clear()
	mercenaries = {"basic_01": {"type_id": "basic", "hp": 100, "owned": true}}
	mercenary_roster = ["basic_01"]
	free_revival_date = ""
	battle_state.clear()
	captivity_state.clear()
	processed_result_ids.clear()
	rescue_debts.clear()
	enemy_states.clear()
	enemy_grace_seconds_remaining = 0.0
	market_states.clear()
	for market_id in market_definitions:
		var definition: Dictionary = market_definitions[market_id]
		for product_id in definition["product_ids"]:
			market_states[market_id + ":" + product_id] = _make_initial_market_state(str(market_id), str(product_id))
	_reset_phase3_state()
	_reset_phase5_state()


func _reset_phase3_state() -> void:
	game_clock = GameClockScript.new()
	game_clock.start_date = {"year": 2025, "month": 1, "day": 20, "hour": 0, "minute": 0, "second": 0}
	game_clock.processed_through_day = GameClockScript.get_day_start_timestamp(_date_to_timestamp("2025-01-20"))
	pause_reasons.clear()
	var initial_assignment := "companion" if party_ids.has("staff_01") else "office_standby"
	employee_states = {"staff_01": {"assignment": initial_assignment, "last_task_id": "", "level": 1, "cargo_capacity_g": PERSON_CAPACITY_G}}
	staff_tasks.clear()
	market_reports.clear()
	event_states.clear()
	for event_id in event_definitions:
		event_states[event_id] = {"started": false, "active": false, "ended": false, "read": false}
	pending_news_ids.clear()
	processed_invoice_ids.clear()
	unpaid_invoices.clear()
	rng_state = 20250120
	daily_alerts.clear()
	news_overlay_open = false
	clock_autosave_seconds = 0.0
	is_processing_day = false
	queued_daily_alerts.clear()
	var contract_start := str(office_rules.get("contract_start", "2025-01-20"))
	contract_start_timestamp = _date_to_timestamp(contract_start)
	contract_day = int(contract_start.substr(8, 2))


## P1 사옥·대출·작업장 상태의 새 게임 기본값을 초기화한다.
func _reset_phase5_state() -> void:
	office_tier = "rented_base"
	office_purchase_price = 0
	general_loans.clear()
	general_loan_arrears = 0
	staff_counter = 1
	mahjong_fatigue = 0
	mahjong_unlocked_levels = ["beginner"]
	mahjong_state.clear()
	processed_mahjong_rewards.clear()


func _is_normal_time_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null or not pause_reasons.is_empty():
		return false
	var path := scene.scene_file_path
	return path.ends_with("game/app/main.tscn") or path.ends_with("game/world/korea_world.tscn") or path.ends_with("game/office/office.tscn")


func _ensure_time_hud() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if not (path.ends_with("game/app/main.tscn") or path.ends_with("game/world/korea_world.tscn") or path.ends_with("game/office/office.tscn")):
		return
	if scene.get_node_or_null("TimeHUD") == null:
		var hud_scene: PackedScene = load("res://game/ui/time_hud.tscn")
		scene.add_child(hud_scene.instantiate())


func set_pause_reason(reason: String, paused: bool) -> void:
	if reason.is_empty():
		return
	if paused:
		pause_reasons[reason] = true
	else:
		pause_reasons.erase(reason)
	clock_changed.emit()


func get_game_date_string() -> String:
	return game_clock.get_date_string()


func get_game_datetime() -> Dictionary:
	return game_clock.get_current_date()


func get_next_invoice_date() -> String:
	var contract_date: Dictionary = Time.get_datetime_dict_from_unix_time(contract_start_timestamp)
	var calendar = GameClockScript.new()
	calendar.start_date = {"year": contract_date["year"], "month": contract_date["month"], "day": contract_day, "hour": 0, "minute": 0, "second": 0}
	for month_index in range(1, 241):
		var due_timestamp: int = calendar.anniversary_timestamp(month_index)
		if float(due_timestamp) > game_clock.current_timestamp():
			return calendar.get_date_string(due_timestamp)
	return "일정 없음"


func get_is_clock_paused() -> bool:
	return not _is_normal_time_scene() or not pause_reasons.is_empty()


func _process_game_day(day_timestamp: int) -> void:
	is_processing_day = true
	queued_daily_alerts.clear()
	var date_key := game_clock.get_date_string(day_timestamp)
	var report_count_before := market_reports.size()
	var started_today := _update_event_schedule(day_timestamp)
	mahjong_fatigue = maxi(0, mahjong_fatigue - 5)
	_update_market_daily(started_today)
	_complete_research_tasks(day_timestamp)
	_process_office_invoice(day_timestamp)
	_process_rescue_debt_due(day_timestamp)
	_process_general_loan_due(day_timestamp)
	daily_alerts.append("게임 날짜 %s 처리 완료" % date_key)
	if daily_alerts.size() > 30:
		daily_alerts.pop_front()
	is_processing_day = false
	for message in queued_daily_alerts:
		alert_received.emit(message)
	queued_daily_alerts.clear()
	state_changed.emit()
	if market_reports.size() > report_count_before:
		reports_changed.emit()


func _update_event_schedule(day_timestamp: int) -> Array[String]:
	var started_today: Array[String] = []
	for event_id in event_definitions:
		var event: Dictionary = event_definitions[event_id]
		var state: Dictionary = event_states.get(event_id, {"started": false, "active": false, "ended": false, "read": false})
		var start_timestamp := _date_to_timestamp(str(event["start_date"]))
		var end_timestamp := start_timestamp + int(event["duration_days"]) * 86400
		if day_timestamp == end_timestamp and state["active"]:
			state["active"] = false
			state["ended"] = true
			_add_daily_alert("사건 효과 종료: %s" % event["title"])
		if day_timestamp == start_timestamp and not state["started"]:
			state["started"] = true
			state["active"] = true
			started_today.append(str(event_id))
			if not state["read"] and not pending_news_ids.has(str(event_id)):
				pending_news_ids.append(str(event_id))
			_add_daily_alert("새 뉴스: %s" % event["title"])
		event_states[event_id] = state
	return started_today


func _update_market_daily(started_today: Array[String]) -> void:
	for market_id in market_definitions:
		var market: Dictionary = market_definitions[market_id]
		var region_id: String = market["region_id"]
		for product_id in market["product_ids"]:
			var key: String = str(market_id) + ":" + str(product_id)
			var state: Dictionary = market_states[key]
			var supply_factor := _event_factor(region_id, str(product_id), "supply_factor")
			var demand_factor := _event_factor(region_id, str(product_id), "demand_factor")
			var stock_before := int(state["stock"])
			var target_stock := int(state["target_stock"])
			var average_production := float(market["average_production"])
			var production_target := maxf(0.0, average_production + 0.1 * float(target_stock - stock_before))
			var production_value := production_target / 0.9 * (0.8 + _next_random_unit() * 0.2) * supply_factor + float(state.get("production_remainder", 0.0))
			var produced := maxi(0, floori(production_value))
			state["production_remainder"] = production_value - float(produced)
			var available := stock_before + produced
			var consumption_target := minf(float(available), float(market["average_consumption"]) * demand_factor)
			var consumption_value := consumption_target + float(state.get("consumption_remainder", 0.0))
			var consumed := mini(available, maxi(0, floori(consumption_value)))
			state["consumption_remainder"] = consumption_value - float(consumed) if consumed < available else 0.0
			var stock_after := maxi(0, available - consumed)
			var previous_price := float(state["reference_price"])
			var base_price := float(state["base_price"])
			var price_factor := clampf(pow(float(target_stock) / maxf(float(stock_after), 1.0), 0.6), MIN_PRICE_FACTOR, MAX_PRICE_FACTOR)
			var target_price := base_price * price_factor
			var approached_price := previous_price + (target_price - previous_price) * 0.25
			var variation := 0.05
			for started_id in started_today:
				var started_event: Dictionary = event_definitions[started_id]
				if started_event["region_id"] == region_id and started_event["product_id"] == product_id:
					variation = 0.20
			var jitter := 1.0 - variation + _next_random_unit() * variation * 2.0
			var new_price := clampf(approached_price * jitter, base_price * MIN_PRICE_FACTOR, base_price * MAX_PRICE_FACTOR)
			state["stock"] = stock_after
			state["reference_stock"] = stock_after
			var history: Array = state.get("price_history", [])
			history.append(new_price)
			while history.size() > 3:
				history.pop_front()
			state["trend_percent"] = (new_price / maxf(float(history[0]), 1.0) - 1.0) * 100.0
			state["trend_days"] = history.size()
			state["price_history"] = history
			state["reference_price"] = new_price
			market_states[key] = state


func _event_factor(region_id: String, product_id: String, factor_key: String) -> float:
	var combined := 1.0
	for event_id in event_states:
		var state: Dictionary = event_states[event_id]
		if not state["active"]:
			continue
		var definition: Dictionary = event_definitions[event_id]
		if definition["region_id"] == region_id and definition["product_id"] == product_id:
			combined *= float(definition[factor_key])
	return clampf(combined, 0.0, 3.0)


func _next_random_unit() -> float:
	rng_state = posmod(rng_state * 48271, 2147483647)
	return float(rng_state) / 2147483647.0


func _complete_research_tasks(day_timestamp: int) -> void:
	for task_id in staff_tasks:
		var task: Dictionary = staff_tasks[task_id]
		if task["status"] != "in_progress" or int(task["completion_day"]) > day_timestamp:
			continue
		var report := _capture_market_report(str(task_id), str(task["destination_region"]), day_timestamp)
		market_reports.append(report)
		task["status"] = "completed"
		task["report_id"] = report["id"]
		staff_tasks[task_id] = task
		var employee_state: Dictionary = employee_states.get(str(task["employee_id"]), {}).duplicate(true)
		employee_state["assignment"] = "office_standby"
		employee_state["last_task_id"] = str(task_id)
		employee_states[task["employee_id"]] = employee_state
		_add_daily_alert("시장 조사 보고 도착: %s" % report["region_name"])


func _capture_market_report(task_id: String, region_id: String, observed_timestamp: int) -> Dictionary:
	var snapshots: Array[Dictionary] = []
	for market in get_region_markets(region_id):
		for product_id in market["product_ids"]:
			var state: Dictionary = market_states[str(market["id"]) + ":" + str(product_id)]
			snapshots.append({
				"market_id": market["id"], "market_name": market["name"], "product_id": product_id,
				"product_name": get_product_name(str(product_id)), "stock": int(state["stock"]),
				"reference_price": float(state["reference_price"]), "trend_percent": float(state.get("trend_percent", 0.0)), "trend_days": int(state.get("trend_days", 0)),
			})
	return {"id": "report-%s" % task_id, "task_id": task_id, "region_id": region_id,
		"region_name": str(region_definitions.get(region_id, {}).get("name", region_id)), "observed_on": game_clock.get_date_string(observed_timestamp),
		"snapshots": snapshots, "read": false}


func _process_office_invoice(day_timestamp: int) -> void:
	if not game_clock.is_month_anniversary(day_timestamp, contract_day, contract_start_timestamp):
		return
	var due_date := game_clock.get_date_string(day_timestamp)
	var invoice_id := "office-fixed-cost-%s" % due_date
	if processed_invoice_ids.has(invoice_id):
		return
	var rent := int(office_rules.get("monthly_rent", 100000)) if office_tier == "rented_base" else (int(office_rules.get("expanded_rent", 250000)) if office_tier == "rented_expanded" else 0)
	var salary := int(office_rules.get("monthly_staff_salary", 80000)) * employee_states.size()
	var management := int(office_rules.get("owned_management_fee", 100000)) if office_tier == "owned" else 0
	var total := rent + salary + management
	processed_invoice_ids.append(invoice_id)
	if int(accounts["corporate"]) < total:
		unpaid_invoices.append({"id": invoice_id, "date": due_date, "amount": total, "status": "unpaid"})
		_add_daily_alert("월세·급여·관리비 %s원 미납: 법인 잔액 부족" % total)
		return
	accounts["corporate"] = int(accounts["corporate"]) - total
	ledger.append({"id": invoice_id, "kind": "office_fixed_cost", "account": "corporate", "amount": -total, "rent": rent, "salary": salary, "management": management, "date": due_date})
	_add_daily_alert("고정비 %s원 납부 · 임대료 %s원 · 급여 %s원 · 관리비 %s원" % [total, rent, salary, management])


## 석방 전용 구조 채무만 월 기념일에 3회 분할 상환한다.
func _process_rescue_debt_due(day_timestamp: int) -> void:
	if not game_clock.is_month_anniversary(day_timestamp, contract_day, contract_start_timestamp):
		return
	for index in rescue_debts.size():
		var debt: Dictionary = rescue_debts[index]
		if int(debt.get("installments_left", 0)) <= 0 or int(debt.get("remaining", 0)) <= 0 or int(debt.get("next_due_timestamp", 0)) > day_timestamp:
			continue
		var left := int(debt["installments_left"])
		var installment := int(debt.get("installment_base", 0)) if left > 1 else int(debt["remaining"])
		installment = mini(installment, int(debt["remaining"]))
		if installment <= 0:
			installment = int(debt["remaining"])
		if int(accounts["corporate"]) < installment:
			rescue_debts[index] = debt
			_add_daily_alert("구조 채무 상환 연기: 미납 회차 이월 · 추가 연체료 없음")
			continue
		var installment_number := 4 - left
		var payment_id := "%s:installment:%d" % [debt["id"], installment_number]
		if processed_order_ids.has(payment_id):
			continue
		var previous_state := _make_payload()
		accounts["corporate"] = int(accounts["corporate"]) - installment
		debt["remaining"] = int(debt["remaining"]) - installment
		debt["installments_left"] = left - 1
		debt["next_due_timestamp"] = int(game_clock.anniversary_timestamp(floori(game_clock.elapsed_real_seconds / GameClockScript.REAL_SECONDS_PER_MONTH) + 1))
		rescue_debts[index] = debt
		processed_order_ids.append(payment_id)
		ledger.append({"id": payment_id, "kind": "rescue_loan_repayment", "account": "corporate", "amount": -installment, "date": game_clock.get_date_string(day_timestamp)})
		if not save_game():
			_apply_payload(previous_state)
			return
		_add_daily_alert("석방 구조 채무 상환: %s원 · 잔액 %s원" % [installment, debt["remaining"]])


## 일반 대출 이자는 계약 기념일에 계산하고 부족분은 가산 없이 이월한다.
func _process_general_loan_due(day_timestamp: int) -> void:
	if not game_clock.is_month_anniversary(day_timestamp, contract_day, contract_start_timestamp):
		return
	for index in general_loans.size():
		var loan: Dictionary = general_loans[index]
		if (int(loan.get("principal", 0)) <= 0 and int(loan.get("arrears", 0)) <= 0) or int(loan.get("next_due_timestamp", 0)) > day_timestamp:
			continue
		var due_index := int(loan.get("next_due_index", floori(game_clock.elapsed_real_seconds / GameClockScript.REAL_SECONDS_PER_MONTH) + 1))
		var loan_id := str(loan["id"])
		var charge_id := "%s:interest:%s" % [loan_id, game_clock.get_date_string(day_timestamp)]
		if processed_order_ids.has(charge_id):
			continue
		var exact_interest := float(loan["principal"]) * float(office_rules.get("monthly_loan_interest_rate", 0.01)) + float(loan.get("interest_remainder", 0.0))
		var interest := floori(exact_interest)
		loan["interest_remainder"] = exact_interest - float(interest)
		var due := int(loan.get("arrears", 0)) + interest
		loan["next_due_index"] = due_index + 1
		loan["next_due_timestamp"] = game_clock.anniversary_timestamp(due_index + 1)
		processed_order_ids.append(charge_id)
		if int(accounts["corporate"]) >= due:
			accounts["corporate"] = int(accounts["corporate"]) - due
			loan["arrears"] = 0
			ledger.append({"id": charge_id, "kind": "general_loan_interest", "account": "corporate", "amount": -due, "date": game_clock.get_date_string(day_timestamp)})
		else:
			loan["arrears"] = due
			_add_daily_alert("대출 이자 %s원 미납 · 추가 연체료 없이 이월" % due)
		general_loans[index] = loan
	if not save_game():
		_add_daily_alert("대출 이자 처리 저장 실패")


func _add_daily_alert(message: String) -> void:
	daily_alerts.append(message)
	if daily_alerts.size() > 30:
		daily_alerts.pop_front()
	if is_processing_day:
		queued_daily_alerts.append(message)
	else:
		alert_received.emit(message)


func _date_to_timestamp(date_text: String) -> int:
	var parts := date_text.split("-")
	if parts.size() != 3:
		return 0
	return Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 0, "minute": 0, "second": 0})


## 조사 출장은 기존 동행자·화물·법인 잔액을 모두 확인한 뒤 확정한다.
func assign_research(task_id: String, destination_region: String, companion_unassignment_confirmed: bool, cargo_transfer_confirmed: bool, selected_employee_id: String = "") -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if task_id.is_empty() or staff_tasks.has(task_id) or processed_order_ids.has(task_id):
		return {"ok": false, "reason": "duplicate_order"}
	if not REGION_IDS.has(destination_region):
		return {"ok": false, "reason": "invalid_region"}
	var employee_id := selected_employee_id if not selected_employee_id.is_empty() else str(office_rules.get("starting_employee_id", "staff_01"))
	var employee: Dictionary = employee_states.get(employee_id, {})
	if employee.is_empty() or employee.get("assignment") == "research_trip":
		return {"ok": false, "reason": "employee_unavailable"}
	if party_ids.has(employee_id) and not companion_unassignment_confirmed:
		return {"ok": false, "reason": "companion_confirmation_required"}
	if not cargo_transfer_confirmed:
		return {"ok": false, "reason": "cargo_confirmation_required"}
	if get_inventory_weight_g(employee_id) > 0:
		return {"ok": false, "reason": "cargo_not_transferred"}
	var cost := int(office_rules.get("survey_cost", 0))
	var duration_days := int(office_rules.get("survey_duration_days", 0))
	if cost <= 0 or duration_days <= 0:
		return {"ok": false, "reason": "survey_rules_invalid"}
	if int(accounts["corporate"]) < cost:
		return {"ok": false, "reason": "insufficient_funds", "account": "corporate", "amount": cost}
	var previous_state := _make_payload()
	if party_ids.has(employee_id):
		party_ids.erase(employee_id)
	accounts["corporate"] = int(accounts["corporate"]) - cost
	var completion_day: int = int(game_clock.processed_through_day) + duration_days * 86400
	staff_tasks[task_id] = {"id": task_id, "employee_id": employee_id, "destination_region": destination_region,
		"departure_date": get_game_date_string(), "completion_day": completion_day, "cost": cost, "status": "in_progress", "report_id": ""}
	var employee_state: Dictionary = employee_states.get(employee_id, {}).duplicate(true)
	employee_state["assignment"] = "research_trip"
	employee_state["last_task_id"] = task_id
	employee_states[employee_id] = employee_state
	processed_order_ids.append(task_id)
	ledger.append({"id": task_id, "kind": "market_research_trip", "account": "corporate", "amount": -cost, "region_id": destination_region, "duration_days": duration_days, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "cost": cost, "duration_days": duration_days, "completion_day": completion_day}


func cancel_research(task_id: String) -> Dictionary:
	if not staff_tasks.has(task_id) or staff_tasks[task_id]["status"] != "in_progress":
		return {"ok": false, "reason": "task_not_active"}
	var previous_state := _make_payload()
	var task: Dictionary = staff_tasks[task_id]
	task["status"] = "cancelled"
	staff_tasks[task_id] = task
	var employee_state: Dictionary = employee_states.get(str(task["employee_id"]), {}).duplicate(true)
	employee_state["assignment"] = "office_standby"
	employee_state["last_task_id"] = task_id
	employee_states[task["employee_id"]] = employee_state
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "refunded": 0}


func return_staff_to_companion(employee_id: String) -> Dictionary:
	if not employee_states.has(employee_id) or employee_states[employee_id]["assignment"] != "office_standby":
		return {"ok": false, "reason": "employee_unavailable"}
	if party_ids.size() >= 4:
		return {"ok": false, "reason": "party_full"}
	var previous_state := _make_payload()
	party_ids.append(employee_id)
	var employee_state: Dictionary = employee_states[employee_id].duplicate(true)
	employee_state["assignment"] = "companion"
	employee_states[employee_id] = employee_state
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


func mark_report_read(report_id: String) -> void:
	for index in market_reports.size():
		if market_reports[index]["id"] == report_id:
			market_reports[index]["read"] = true
			save_game()
			reports_changed.emit()
			return


func get_read_news() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event_id in event_states:
		if event_states[event_id].get("read", false):
			result.append(event_definitions[event_id])
	return result


func get_event_article(event_id: String) -> Dictionary:
	return event_definitions.get(event_id, {}).duplicate(true)


func acknowledge_news(event_id: String) -> void:
	if not event_states.has(event_id) or not event_states[event_id]["started"]:
		return
	event_states[event_id]["read"] = true
	pending_news_ids.erase(event_id)
	news_overlay_open = false
	set_pause_reason("news_cutscene", false)
	save_game()
	state_changed.emit()
	call_deferred("_show_next_pending_news")


func _show_next_pending_news() -> void:
	if news_overlay_open or pending_news_ids.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var event_id := pending_news_ids[0]
	var overlay_scene: PackedScene = load("res://game/news/news_overlay.tscn")
	var overlay: CanvasLayer = overlay_scene.instantiate()
	scene.add_child(overlay)
	overlay.present_article(get_event_article(event_id))
	news_overlay_open = true
	set_pause_reason("news_cutscene", true)


## 상품 목록을 지역의 시장 정의에 따라 반환한다.
func get_region_markets(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for market_id in market_definitions:
		var market: Dictionary = market_definitions[market_id]
		if market["region_id"] == region_id:
			result.append(market)
	return result


func get_product_name(product_id: String) -> String:
	return str(products.get(product_id, {}).get("name", product_id))


func get_inventory_count(person_id: String, product_id: String) -> int:
	return int(inventories.get(person_id, {}).get(product_id, 0))


func get_inventory_weight_g(person_id: String) -> int:
	var total := 0
	for product_id in inventories.get(person_id, {}):
		total += int(inventories[person_id][product_id]) * int(products.get(product_id, {}).get("unit_weight_g", 0))
	return total


## 인물별 적재 능력치를 읽고 구버전 직원 데이터는 기획 기본값으로 보완한다.
func get_cargo_capacity_g(owner_id: String) -> int:
	if owner_id.begins_with("vehicle:"):
		var vehicle_id := owner_id.trim_prefix("vehicle:")
		return int(vehicle_definitions.get(vehicle_id, {}).get("capacity_g", 0))
	if owner_id == "player":
		return PERSON_CAPACITY_G
	return int(employee_states.get(owner_id, {}).get("cargo_capacity_g", PERSON_CAPACITY_G))


## 현재 야외에서 함께 움직이는 인물과 활성 차량의 거래 화물 무게를 합산한다.
func get_moving_trade_cargo_weight_g() -> int:
	var total := 0
	for person_id in party_ids:
		total += get_inventory_weight_g(person_id)
	if not active_vehicle_id.is_empty():
		total += get_inventory_weight_g("vehicle:" + active_vehicle_id)
	return total


## 현재 이동 편성의 총 적재 가능량을 반환해 차량 비용의 적재 비율을 계산한다.
func get_moving_cargo_capacity_g() -> int:
	var total := 0
	for person_id in party_ids:
		total += get_cargo_capacity_g(person_id)
	if not active_vehicle_id.is_empty():
		total += get_cargo_capacity_g("vehicle:" + active_vehicle_id)
	return total


func get_party_weight_g() -> int:
	var total := 0
	for person_id in party_ids:
		total += get_inventory_weight_g(person_id)
	return total


func get_market_stock(market_id: String, product_id: String) -> int:
	return int(market_states.get(market_id + ":" + product_id, {}).get("stock", 0))


## 재고 상태의 곡선에서 플레이어 기준 매입·매도 단가를 계산한다.
func get_quote(market_id: String, product_id: String, side: String, quantity: int) -> Dictionary:
	var key := market_id + ":" + product_id
	if quantity <= 0 or not market_states.has(key):
		return {"ok": false, "reason": "invalid_order", "total": 0}
	var market: Dictionary = market_states[key]
	var stock := int(market["stock"])
	if side == "buy" and quantity > stock:
		return {"ok": false, "reason": "insufficient_stock", "total": 0}
	var product: Dictionary = products[product_id]
	var unit_weight := int(product["unit_weight_g"])
	var projected_stock := stock
	var total := 0
	var unit_prices: Array[int] = []
	for _index in quantity:
		var sample := float(projected_stock) - 0.5 if side == "buy" else float(projected_stock) + 0.5
		var curve_price := _curve_price(market, sample)
		var unit_price := int(ceil(curve_price * (1.0 + TRADE_SPREAD))) if side == "buy" else int(floor(curve_price * (1.0 - TRADE_SPREAD)))
		total += unit_price
		unit_prices.append(unit_price)
		projected_stock += -1 if side == "buy" else 1
	return {"ok": true, "total": total, "unit_weight_g": unit_weight, "total_weight_g": unit_weight * quantity, "unit_price": int(ceil(float(total) / quantity)), "unit_prices": unit_prices}


## 주문 확정 전 취소는 예약 상태가 없으므로 게임 상태를 바꾸지 않는다.
func cancel_trade(order_id: String) -> Dictionary:
	if order_id.is_empty() or processed_order_ids.has(order_id):
		return {"ok": false, "reason": "order_already_processed"}
	return {"ok": true, "reason": "cancelled"}


func _curve_price(market: Dictionary, stock_sample: float) -> float:
	var target: float = float(market["target_stock"])
	var reference_stock: float = float(market["reference_stock"])
	var reference_price: float = float(market["reference_price"])
	var base: float = float(market["base_price"])
	var current_factor := clampf(pow(target / maxf(stock_sample, 1.0), 0.6), MIN_PRICE_FACTOR, MAX_PRICE_FACTOR)
	var reference_factor := clampf(pow(target / maxf(reference_stock, 1.0), 0.6), MIN_PRICE_FACTOR, MAX_PRICE_FACTOR)
	return clampf(reference_price * current_factor / reference_factor, base * MIN_PRICE_FACTOR, base * MAX_PRICE_FACTOR)


## 검증한 거래를 계좌·시장·화물·원장에 한 번에 확정한다.
func execute_trade(order_id: String, market_id: String, product_id: String, side: String, person_id: String, quantity: int) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if not pending_news_ids.is_empty():
		return {"ok": false, "reason": "news_pending"}
	if order_id.is_empty() or processed_order_ids.has(order_id):
		return {"ok": false, "reason": "duplicate_order"}
	if side != "buy" and side != "sell":
		return {"ok": false, "reason": "invalid_order"}
	var market: Dictionary = market_definitions.get(market_id, {})
	if market.is_empty() or market["region_id"] != current_region or not market["product_ids"].has(product_id):
		return {"ok": false, "reason": "not_traded"}
	if not _is_cargo_owner_available(person_id) or not inventories.has(person_id):
		return {"ok": false, "reason": "invalid_owner"}
	var quote := get_quote(market_id, product_id, side, quantity)
	if not quote["ok"]:
		return quote
	var weight := int(quote["total_weight_g"])
	var held := get_inventory_count(person_id, product_id)
	var cost_lots: Array = inventory_costs.get(person_id, {}).get(product_id, [])
	if side == "sell" and cost_lots.size() != held:
		return {"ok": false, "reason": "invalid_inventory"}
	if side == "buy":
		var available_g := _cargo_capacity_g(person_id) - get_inventory_weight_g(person_id)
		if weight > available_g:
			return {"ok": false, "reason": "capacity_exceeded", "needed_g": weight, "available_g": available_g}
		if int(accounts["corporate"]) < int(quote["total"]):
			return {"ok": false, "reason": "insufficient_funds", "account": "corporate", "total": quote["total"]}
	else:
		if held < quantity:
			return {"ok": false, "reason": "insufficient_goods", "held": held, "requested": quantity}
	var total: int = quote["total"]
	var market_key := market_id + ":" + product_id
	var state: Dictionary = market_states[market_key]
	var previous_state := _make_payload()
	var sold_cost := 0
	if side == "buy":
		accounts["corporate"] = int(accounts["corporate"]) - total
		inventories[person_id][product_id] = held + quantity
		if not inventory_costs[person_id].has(product_id):
			inventory_costs[person_id][product_id] = []
		inventory_costs[person_id][product_id].append_array(quote["unit_prices"])
		state["stock"] = int(state["stock"]) - quantity
	else:
		for _index in quantity:
			sold_cost += int(cost_lots.pop_front()) if not cost_lots.is_empty() else 0
		accounts["corporate"] = int(accounts["corporate"]) + total
		inventories[person_id][product_id] = held - quantity
		inventory_costs[person_id][product_id] = cost_lots
		state["stock"] = int(state["stock"]) + quantity
		retained_realized_profit += total - sold_cost
	ledger.append({"id": order_id, "kind": "trade", "side": side, "region_id": current_region, "market_id": market_id, "product_id": product_id, "person_id": person_id, "quantity": quantity, "account": "corporate", "amount": -total if side == "buy" else total, "realized_profit": total - sold_cost if side == "sell" else 0, "date_label": get_game_date_string()})
	processed_order_ids.append(order_id)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "reason": "", "total": total, "weight_g": weight, "side": side, "realized_profit": total - sold_cost if side == "sell" else 0}


## 동행 중인 같은 위치 인물 사이에서 화물 수량을 검증해 이전한다.
func transfer_goods(from_id: String, to_id: String, product_id: String, quantity: int) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if from_id == to_id or not _is_cargo_owner_available(from_id) or not _is_cargo_owner_available(to_id) or quantity <= 0:
		return {"ok": false, "reason": "invalid_transfer"}
	if not products.has(product_id):
		return {"ok": false, "reason": "not_traded"}
	var held := get_inventory_count(from_id, product_id)
	var weight := quantity * int(products[product_id]["unit_weight_g"])
	if held < quantity:
		return {"ok": false, "reason": "insufficient_goods"}
	var available_weight := _cargo_capacity_g(to_id) - get_inventory_weight_g(to_id)
	if weight > available_weight:
		return {"ok": false, "reason": "capacity_exceeded", "available_g": available_weight}
	var previous_state := _make_payload()
	inventories[from_id][product_id] = held - quantity
	inventories[to_id][product_id] = get_inventory_count(to_id, product_id) + quantity
	var from_lots: Array = inventory_costs.get(from_id, {}).get(product_id, [])
	var moved_lots: Array = []
	for _index in quantity:
		if from_lots.is_empty():
			break
		moved_lots.append(from_lots.pop_front())
	inventory_costs[from_id][product_id] = from_lots
	if not inventory_costs[to_id].has(product_id):
		inventory_costs[to_id][product_id] = []
	inventory_costs[to_id][product_id].append_array(moved_lots)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


func _is_cargo_owner_available(owner_id: String) -> bool:
	if party_ids.has(owner_id):
		return true
	if owner_id.begins_with("vehicle:"):
		var vehicle_id := owner_id.trim_prefix("vehicle:")
		return vehicle_id == active_vehicle_id and owned_vehicle_ids.has(vehicle_id)
	return false


func _cargo_capacity_g(owner_id: String) -> int:
	return get_cargo_capacity_g(owner_id)


func get_owner_weight_g(owner_id: String) -> int:
	return get_inventory_weight_g(owner_id)


## 구매를 차량 소유권·법인 출금·원장으로 함께 확정한다.
func purchase_vehicle(vehicle_id: String, order_id: String) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if order_id.is_empty() or processed_order_ids.has(order_id):
		return {"ok": false, "reason": "duplicate_order"}
	if not vehicle_definitions.has(vehicle_id):
		return {"ok": false, "reason": "vehicle_unavailable"}
	if owned_vehicle_ids.has(vehicle_id):
		return {"ok": false, "reason": "already_owned"}
	var price := int(vehicle_definitions[vehicle_id]["price"])
	if int(accounts["corporate"]) < price:
		return {"ok": false, "reason": "insufficient_funds", "account": "corporate", "amount": price}
	var previous_state := _make_payload()
	owned_vehicle_ids.append(vehicle_id)
	active_vehicle_id = vehicle_id
	var owner_id := "vehicle:" + vehicle_id
	inventories[owner_id] = {}
	inventory_costs[owner_id] = {}
	accounts["corporate"] = int(accounts["corporate"]) - price
	processed_order_ids.append(order_id)
	ledger.append({"id": order_id, "kind": "vehicle_purchase", "asset_id": vehicle_id, "account": "corporate", "amount": -price, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "price": price, "vehicle_id": vehicle_id}


## 소유 차량을 활성 차량으로 선택한다. 각 차의 화물은 해당 차량에 남는다.
func select_vehicle(vehicle_id: String) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if not owned_vehicle_ids.has(vehicle_id):
		return {"ok": false, "reason": "vehicle_unavailable"}
	for parked in parked_vehicles:
		if str(parked.get("vehicle_id", "")) == vehicle_id:
			return {"ok": false, "reason": "vehicle_parked_elsewhere"}
	var previous_id := active_vehicle_id
	active_vehicle_id = vehicle_id
	if not save_game():
		active_vehicle_id = previous_id
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


## 논리 이동거리의 소수 비용을 누적하고 법인 원장에 정수 원 단위로 기록한다.
func charge_vehicle_distance(distance_m: float) -> Dictionary:
	if active_vehicle_id.is_empty() or distance_m <= 0.0:
		return {"ok": true, "charged": 0}
	var cargo_weight_g := get_moving_trade_cargo_weight_g()
	if cargo_weight_g <= 0:
		return {"ok": true, "charged": 0, "reason": "empty_cargo"}
	var vehicle: Dictionary = vehicle_definitions[active_vehicle_id]
	var capacity_g := get_moving_cargo_capacity_g()
	if capacity_g <= 0:
		return {"ok": false, "reason": "invalid_capacity"}
	var load_ratio := clampf(float(cargo_weight_g) / float(capacity_g), 0.0, 1.0)
	var exact_cost := distance_m * float(vehicle["cost_per_km"]) / 1000.0 * load_ratio + float(vehicle_cost_remainders.get(active_vehicle_id, 0.0))
	var charge := floori(exact_cost)
	if charge > int(accounts["corporate"]):
		return {"ok": false, "reason": "insufficient_funds", "needed": charge, "available": int(accounts["corporate"])}
	if charge <= 0:
		vehicle_cost_remainders[active_vehicle_id] = exact_cost
		travel_meter_remainder += distance_m
		return {"ok": true, "charged": 0}
	var previous_state := _make_payload()
	vehicle_cost_remainders[active_vehicle_id] = exact_cost - float(charge)
	travel_meter_remainder += distance_m
	accounts["corporate"] = int(accounts["corporate"]) - charge
	var ledger_id := "vehicle-travel-%s-%d" % [get_game_date_string(), ledger.size()]
	ledger.append({"id": ledger_id, "kind": "vehicle_travel", "asset_id": active_vehicle_id, "account": "corporate", "amount": -charge, "distance_m": int(floor(travel_meter_remainder)), "date": get_game_date_string()})
	travel_meter_remainder = fmod(travel_meter_remainder, 1.0)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "charged": charge}


## 소유 차량과 화물을 현재 위치에 주차해 도보 복귀를 허용한다.
func park_active_vehicle(region_id: String, position: Vector2) -> void:
	if active_vehicle_id.is_empty():
		return
	parked_vehicles.append({"vehicle_id": active_vehicle_id, "region_id": region_id, "x": position.x, "y": position.y})
	active_vehicle_id = ""
	save_game()
	state_changed.emit()


func recover_parked_vehicle(vehicle_id: String, region_id: String, position: Vector2) -> Dictionary:
	if not active_vehicle_id.is_empty():
		return {"ok": false, "reason": "vehicle_already_active"}
	for index in parked_vehicles.size():
		var parked: Dictionary = parked_vehicles[index]
		if str(parked.get("vehicle_id", "")) != vehicle_id or str(parked.get("region_id", "")) != region_id:
			continue
		var parked_position := Vector2(float(parked.get("x", 0.0)), float(parked.get("y", 0.0)))
		if parked_position.distance_to(position) > 48.0:
			return {"ok": false, "reason": "vehicle_too_far"}
		var previous_state := _make_payload()
		parked_vehicles.remove_at(index)
		active_vehicle_id = vehicle_id
		if not save_game():
			_apply_payload(previous_state)
			return {"ok": false, "reason": "save_failed"}
		state_changed.emit()
		return {"ok": true}
	return {"ok": false, "reason": "vehicle_not_parked"}


## 동행 또는 활성 차량의 화물을 현재 위치 임시 보관으로 옮기거나 회수한다.
func transfer_cargo_cache(owner_id: String, product_id: String, quantity: int, region_id: String, position: Vector2, store: bool) -> Dictionary:
	if not _is_cargo_owner_available(owner_id) or not products.has(product_id) or quantity <= 0:
		return {"ok": false, "reason": "invalid_transfer"}
	var cache_id := "%s:%.0f:%.0f" % [region_id, position.x, position.y]
	var cache_index := -1
	for index in cargo_caches.size():
		if str(cargo_caches[index].get("id", "")) == cache_id:
			cache_index = index
	var source_owner := owner_id
	var target_owner := owner_id
	if store:
		if int(inventories.get(owner_id, {}).get(product_id, 0)) < quantity:
			return {"ok": false, "reason": "insufficient_goods"}
	else:
		if cache_index < 0 or int(cargo_caches[cache_index].get("goods", {}).get(product_id, 0)) < quantity:
			return {"ok": false, "reason": "insufficient_goods"}
	var previous_state := _make_payload()
	if cache_index < 0:
		cargo_caches.append({"id": cache_id, "region_id": region_id, "x": position.x, "y": position.y, "goods": {}, "costs": {}})
		cache_index = cargo_caches.size() - 1
	var cache: Dictionary = cargo_caches[cache_index]
	var count := int(inventories.get(source_owner, {}).get(product_id, 0)) if store else int(cache["goods"].get(product_id, 0))
	var lots: Array = inventory_costs.get(source_owner, {}).get(product_id, []) if store else cache["costs"].get(product_id, [])
	var moving_lots: Array = []
	for _i in quantity:
		moving_lots.append(lots.pop_front())
	if store:
		inventories[source_owner][product_id] = count - quantity
		cache["goods"][product_id] = int(cache["goods"].get(product_id, 0)) + quantity
		if not cache["costs"].has(product_id): cache["costs"][product_id] = []
		cache["costs"][product_id].append_array(moving_lots)
		inventory_costs[source_owner][product_id] = lots
	else:
		var free_g := _cargo_capacity_g(target_owner) - get_inventory_weight_g(target_owner)
		var weight := int(products[product_id]["unit_weight_g"]) * quantity
		if weight > free_g:
			_apply_payload(previous_state)
			return {"ok": false, "reason": "capacity_exceeded", "available_g": free_g}
		cache["goods"][product_id] = count - quantity
		inventories[target_owner][product_id] = int(inventories[target_owner].get(product_id, 0)) + quantity
		if not inventory_costs[target_owner].has(product_id): inventory_costs[target_owner][product_id] = []
		inventory_costs[target_owner][product_id].append_array(moving_lots)
		cache["costs"][product_id] = lots
	cargo_caches[cache_index] = cache
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


func get_cargo_cache_count(region_id: String, position: Vector2, product_id: String) -> int:
	var cache_id := "%s:%.0f:%.0f" % [region_id, position.x, position.y]
	for cache in cargo_caches:
		if str(cache.get("id", "")) == cache_id:
			return int(cache.get("goods", {}).get(product_id, 0))
	return 0


## 사옥에서 선택한 용병의 피해를 치료한다.
func treat_mercenary(mercenary_id: String) -> Dictionary:
	if captivity_state.get("active", false) or not mercenaries.has(mercenary_id):
		return {"ok": false, "reason": "mercenary_unavailable"}
	var mercenary: Dictionary = mercenaries[mercenary_id]
	var definition: Dictionary = mercenary_definitions.get(str(mercenary["type_id"]), {})
	var missing := int(definition.get("max_hp", 0)) - int(mercenary.get("hp", 0))
	if missing <= 0:
		return {"ok": false, "reason": "already_healthy"}
	var cost := missing * 100
	if int(accounts["corporate"]) < cost:
		return {"ok": false, "reason": "insufficient_funds", "account": "corporate", "amount": cost}
	var previous_state := _make_payload()
	accounts["corporate"] = int(accounts["corporate"]) - cost
	mercenary["hp"] = int(definition["max_hp"])
	mercenaries[mercenary_id] = mercenary
	var order_id := "treatment-%s-%s" % [mercenary_id, get_game_date_string()]
	if processed_order_ids.has(order_id):
		_apply_payload(previous_state)
		return {"ok": false, "reason": "duplicate_order"}
	processed_order_ids.append(order_id)
	ledger.append({"id": order_id, "kind": "mercenary_treatment", "asset_id": mercenary_id, "account": "corporate", "amount": -cost, "hp_restored": missing, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "cost": cost, "hp_restored": missing}


## 사옥에서 고용·치료비 결제·용병 등록을 한 번에 처리한다.
func hire_mercenary(type_id: String, mercenary_id: String) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if not mercenary_definitions.has(type_id) or mercenaries.has(mercenary_id) or mercenary_roster.size() >= 3:
		return {"ok": false, "reason": "roster_full_or_invalid"}
	var definition: Dictionary = mercenary_definitions[type_id]
	var cost := int(definition["hire_cost"])
	if int(accounts["corporate"]) < cost:
		return {"ok": false, "reason": "insufficient_funds", "amount": cost}
	var previous_state := _make_payload()
	accounts["corporate"] = int(accounts["corporate"]) - cost
	mercenaries[mercenary_id] = {"type_id": type_id, "hp": int(definition["max_hp"]), "owned": true}
	mercenary_roster.append(mercenary_id)
	var order_id := "mercenary-hire-%s" % mercenary_id
	processed_order_ids.append(order_id)
	ledger.append({"id": order_id, "kind": "mercenary_hire", "asset_id": mercenary_id, "account": "corporate", "amount": -cost, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "cost": cost}


## 초기 기본형 용병만 하루 한 번 무료 재기 지원을 받는다.
func use_free_revival() -> Dictionary:
	if not mercenaries.has("basic_01"):
		return {"ok": false, "reason": "mercenary_unavailable"}
	var today := get_game_date_string()
	if free_revival_date == today:
		return {"ok": false, "reason": "already_used_today"}
	var mercenary: Dictionary = mercenaries["basic_01"]
	var definition: Dictionary = mercenary_definitions["basic"]
	var missing_hp := int(definition["max_hp"]) - int(mercenary["hp"])
	if missing_hp <= 0 or int(accounts["corporate"]) >= missing_hp * 100:
		return {"ok": false, "reason": "not_eligible"}
	var previous_state := _make_payload()
	mercenary["hp"] = int(definition["max_hp"])
	mercenaries["basic_01"] = mercenary
	free_revival_date = today
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


## 유효한 용병 편성·적 유형을 저장하고 별도 전투 장면을 시작한다.
func begin_battle(encounter_id: String, enemy_type_id: String, enemy_spawn_id: String = "", region_id: String = "", position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if not battle_state.is_empty() or captivity_state.get("active", false) or encounter_id.is_empty():
		return {"ok": false, "reason": "encounter_locked"}
	if mercenary_roster.is_empty() or not enemy_definitions.has(enemy_type_id):
		return {"ok": false, "reason": "no_battle_roster"}
	var first_ready := ""
	for mercenary_id in mercenary_roster:
		if int(mercenaries.get(mercenary_id, {}).get("hp", 0)) > 0:
			first_ready = mercenary_id
			break
	if first_ready.is_empty():
		return {"ok": false, "reason": "all_mercenaries_incapacitated"}
	var enemy_data: Dictionary = enemy_definitions[enemy_type_id]
	var enemies: Array[Dictionary] = []
	for enemy in enemy_data["members"]:
		enemies.append({"id": str(enemy["id"]), "name": str(enemy["name"]), "hp": int(enemy["max_hp"]), "max_hp": int(enemy["max_hp"]), "attack": int(enemy["attack"]), "defense": int(enemy["defense"]), "speed": int(enemy["speed"]), "disrupted": false})
	var cargo_snapshot: Dictionary = {}
	for person_id in party_ids:
		cargo_snapshot[person_id] = inventories.get(person_id, {}).duplicate(true)
	if not active_vehicle_id.is_empty():
		cargo_snapshot["vehicle:" + active_vehicle_id] = inventories.get("vehicle:" + active_vehicle_id, {}).duplicate(true)
	var previous_state := _make_payload()
	if REGION_IDS.has(region_id):
		current_region = region_id
	if position.x >= 0.0 and position.y >= 0.0:
		player_position = position
	rng_state = posmod(rng_state * 48271, 2147483647)
	battle_state = {"id": encounter_id, "enemy_type_id": enemy_type_id, "enemy_spawn_id": enemy_spawn_id, "active": true, "turn": 1, "active_mercenary_id": first_ready, "enemies": enemies, "defending": false, "protect_turns": 0, "skill_used_turn": {}, "escape_failures": 0, "return_region": current_region, "return_position": {"x": player_position.x, "y": player_position.y}, "cargo_snapshot": cargo_snapshot, "result": "", "processed": false, "log": ["조우 시작: %s" % enemy_data["name"]]}
	set_pause_reason("battle", true)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


## 한 턴의 유효성을 먼저 확인하고 수동 명령·상대 행동·결과를 반영한다.
func select_battle_command(command: String, target_id: String = "") -> Dictionary:
	if not battle_state.get("active", false) or battle_state.get("processed", false):
		return {"ok": false, "reason": "battle_not_active"}
	var mercenary_id := str(battle_state["active_mercenary_id"])
	var mercenary: Dictionary = mercenaries.get(mercenary_id, {})
	var definition: Dictionary = mercenary_definitions.get(str(mercenary.get("type_id", "")), {})
	var active_enemy_index := _first_living_enemy_index()
	if active_enemy_index < 0:
		return _finish_battle("victory")
	var enemy: Dictionary = battle_state["enemies"][active_enemy_index]
	var skill_name := str(definition.get("skill_id", ""))
	if command == "skill":
		var last_use: int = int(battle_state.get("skill_used_turn", {}).get(mercenary_id, -1000))
		var cooldown := int(definition.get("skill_cooldown", 3))	
		if skill_name.is_empty() or int(battle_state["turn"]) - last_use < cooldown:
			return {"ok": false, "reason": "skill_unavailable"}
	elif command == "switch":
		if target_id == mercenary_id or not mercenary_roster.has(target_id) or int(mercenaries.get(target_id, {}).get("hp", 0)) <= 0:
			return {"ok": false, "reason": "invalid_switch"}
	elif command not in ["attack", "defend", "escape"]:
		return {"ok": false, "reason": "invalid_command"}
	var previous_state := _make_payload()
	var log: Array = battle_state["log"]
	var should_escape := false
	if command == "escape":
		var chance := BattleRules.escape_chance(int(definition.get("speed", 0)), int(enemy["speed"]), int(battle_state["escape_failures"]))
		should_escape = _next_random_unit() < chance
		log.append("도주 시도 %.0f%% · %s" % [chance * 100.0, "성공" if should_escape else "실패"])
		if should_escape:
			should_escape = true
		else:
			battle_state["escape_failures"] = int(battle_state["escape_failures"]) + 1
	elif command == "switch":
		battle_state["active_mercenary_id"] = target_id
		mercenary_id = target_id
		mercenary = mercenaries[target_id]
		definition = mercenary_definitions[str(mercenary["type_id"])]
		log.append("용병 교체: %s" % mercenary_id)
	elif command == "defend":
		battle_state["defending"] = true
		log.append("방어 태세")
	var is_attack := command in ["attack", "skill"]
	var player_first := BattleRules.action_precedes("attack" if is_attack else command, int(definition.get("speed", 0)), int(enemy["speed"]))
	if not should_escape and player_first and is_attack:
		_apply_player_battle_action(command, skill_name, mercenary_id, definition)
	if not should_escape:
		_apply_enemy_turn()
	if not should_escape and not player_first and is_attack and _living_mercenary_count() > 0:
		_apply_player_battle_action(command, skill_name, mercenary_id, definition)
	if _living_mercenary_count() == 0:
		var defeat_result := _finish_battle("defeat")
		if not defeat_result.ok: _apply_payload(previous_state)
		return defeat_result
	if should_escape:
		var escape_result := _finish_battle("escape")
		if not escape_result.ok: _apply_payload(previous_state)
		return escape_result
	if _first_living_enemy_index() < 0:
		var victory_result := _finish_battle("victory")
		if not victory_result.ok: _apply_payload(previous_state)
		return victory_result
	if bool(battle_state["defending"]): battle_state["defending"] = false
	if int(battle_state["protect_turns"]) > 0: battle_state["protect_turns"] = int(battle_state["protect_turns"]) - 1
	battle_state["turn"] = int(battle_state["turn"]) + 1
	if log.size() > 12: log.pop_front()
	battle_state["log"] = log
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "turn": battle_state["turn"]}


func _apply_player_battle_action(command: String, skill_name: String, mercenary_id: String, definition: Dictionary) -> void:
	if int(mercenaries.get(mercenary_id, {}).get("hp", 0)) <= 0:
		return
	if command == "skill" and skill_name == "protect":
		battle_state["protect_turns"] = 2
		battle_state["skill_used_turn"][mercenary_id] = int(battle_state["turn"])
		battle_state["log"].append("보호 기술 · 2턴 피해 감소")
		return
	if command == "skill" and skill_name == "disrupt":
		var target_index := _first_living_enemy_index()
		if target_index >= 0:
			var enemies: Array = battle_state["enemies"]
			enemies[target_index]["disrupted"] = true
			battle_state["enemies"] = enemies
		battle_state["skill_used_turn"][mercenary_id] = int(battle_state["turn"])
		battle_state["log"].append("교란 기술 · 다음 적 공격 약화")
		return
	var target := _first_living_enemy_index()
	if target < 0:
		return
	var enemies: Array = battle_state["enemies"]
	var enemy: Dictionary = enemies[target]
	var multiplier := 1.5 if command == "skill" and skill_name == "strike" else 1.0
	var damage := BattleRules.basic_damage(int(definition.get("attack", 1)), int(enemy["defense"]), multiplier)
	enemy["hp"] = maxi(0, int(enemy["hp"]) - damage)
	enemies[target] = enemy
	battle_state["enemies"] = enemies
	battle_state["log"].append("%s 피해 %d" % ["고유기" if command == "skill" else "일반 공격", damage])
	if command == "skill":
		battle_state["skill_used_turn"][mercenary_id] = int(battle_state["turn"])


func _first_living_enemy_index() -> int:
	var enemies: Array = battle_state.get("enemies", [])
	for index in enemies.size():
		if int(enemies[index].get("hp", 0)) > 0:
			return index
	return -1


func _living_mercenary_count() -> int:
	var total := 0
	for mercenary_id in mercenary_roster:
		if int(mercenaries.get(mercenary_id, {}).get("hp", 0)) > 0: total += 1
	return total


func _apply_enemy_attack(enemy_index: int) -> void:
	var enemies: Array = battle_state["enemies"]
	var enemy: Dictionary = enemies[enemy_index]
	var mercenary_id := str(battle_state["active_mercenary_id"])
	var mercenary: Dictionary = mercenaries[mercenary_id]
	var definition: Dictionary = mercenary_definitions[str(mercenary["type_id"])]
	var multiplier := 0.7 if bool(enemy.get("disrupted", false)) else 1.0
	if bool(enemy.get("disrupted", false)): enemy["disrupted"] = false
	if int(battle_state["protect_turns"]) > 0: multiplier *= 0.75
	if bool(battle_state["defending"]): multiplier *= 0.5
	var damage := maxi(1, floori(float(BattleRules.basic_damage(int(enemy["attack"]), int(definition["defense"]))) * multiplier))
	mercenary["hp"] = maxi(0, int(mercenary["hp"]) - damage)
	mercenaries[mercenary_id] = mercenary
	enemies[enemy_index] = enemy
	battle_state["enemies"] = enemies
	var log: Array = battle_state["log"]
	log.append("적 공격 · %s에게 %d 피해" % [mercenary_id, damage])
	battle_state["log"] = log
	if int(mercenary["hp"]) <= 0:
		for next_id in mercenary_roster:
			if int(mercenaries.get(next_id, {}).get("hp", 0)) > 0:
				battle_state["active_mercenary_id"] = next_id
				battle_state["log"].append("전투 불능 · %s 자동 출전" % next_id)
				return


## 살아 있는 적이 남았으면 로스터 순서대로 한 번씩 공격한다.
func _apply_enemy_turn() -> void:
	var enemies: Array = battle_state.get("enemies", [])
	for enemy_index in enemies.size():
		if int(enemies[enemy_index].get("hp", 0)) <= 0 or _living_mercenary_count() <= 0:
			continue
		_apply_enemy_attack(enemy_index)


## 전투 결과와 화물 손실을 결과 ID 기준으로 한 번만 처리한다.
func _finish_battle(result: String) -> Dictionary:
	var result_id := str(battle_state.get("id", "")) + ":" + result
	if result_id.is_empty() or processed_result_ids.has(result_id):
		return {"ok": false, "reason": "duplicate_result"}
	var previous_state := _make_payload()
	if result in ["escape", "defeat"]:
		var snapshot: Dictionary = battle_state.get("cargo_snapshot", {})
		var loss_remaining_by_product: Dictionary = {}
		if result == "escape":
			var totals: Dictionary = {}
			for cargo_owner in snapshot:
				for product_id in snapshot[cargo_owner]:
					totals[product_id] = int(totals.get(product_id, 0)) + int(snapshot[cargo_owner][product_id])
			for product_id in totals:
				loss_remaining_by_product[product_id] = floori(float(totals[product_id]) * 0.05)
		for owner_id in snapshot:
			if not inventories.has(owner_id): continue
			for product_id in snapshot[owner_id]:
				var current_count := int(inventories[owner_id].get(product_id, 0))
				var loss := current_count if result == "defeat" else mini(current_count, int(loss_remaining_by_product.get(product_id, 0)))
				if result == "escape": loss_remaining_by_product[product_id] = int(loss_remaining_by_product.get(product_id, 0)) - loss
				loss = mini(current_count, loss)
				if loss <= 0: continue
				inventories[owner_id][product_id] = current_count - loss
				var lots: Array = inventory_costs.get(owner_id, {}).get(product_id, [])
				for _i in loss:
					if not lots.is_empty(): lots.pop_front()
				inventory_costs[owner_id][product_id] = lots
				ledger.append({"id": result_id + ":cargo:" + owner_id + ":" + product_id, "kind": "battle_cargo_loss", "owner_id": owner_id, "product_id": product_id, "quantity": loss, "account": "none", "amount": 0, "date": get_game_date_string()})
	if result == "defeat":
		if not active_vehicle_id.is_empty():
			parked_vehicles.append({"vehicle_id": active_vehicle_id, "region_id": current_region, "x": player_position.x, "y": player_position.y})
			active_vehicle_id = ""
		var ratio := 0.3 + _next_random_unit() * 0.2
		var base_balance := int(accounts["corporate"])
		var requested := maxi(50000, floori(float(base_balance) * ratio))
		captivity_state = {"active": true, "stage": "call", "encounter_id": str(battle_state["id"]), "base_corporate_balance": base_balance, "requested_amount": requested, "final_amount": requested, "negotiated": false, "paid": false, "rescue_loan": 0, "result_id": "captivity:" + str(battle_state["id"])}
	if result == "victory":
		var spawn_id := str(battle_state.get("enemy_spawn_id", ""))
		if not spawn_id.is_empty():
			enemy_states[spawn_id] = {"defeated_until": int(game_clock.processed_through_day) + 86400, "encounter_id": str(battle_state["id"])}
	battle_state["active"] = false
	battle_state["result"] = result
	battle_state["processed"] = true
	processed_result_ids.append(result_id)
	enemy_grace_seconds_remaining = 5.0
	set_pause_reason("battle", false)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "result": result, "result_id": result_id}


## 피랍 중 전화, 직원 협상, 석방 전용 대출 정산과 사옥 복귀를 처리한다.
func negotiate_captivity() -> Dictionary:
	if not captivity_state.get("active", false) or captivity_state.get("stage") != "negotiation":
		return {"ok": false, "reason": "invalid_captivity_stage"}
	var previous_state := _make_payload()
	var discount_rate := 0.0
	var task: Dictionary = employee_states.get("staff_01", {})
	var legal_grade := int(task.get("legal_grade", 0))
	discount_rate = float(clampi(legal_grade, 0, 3)) * 0.05
	var requested := int(captivity_state["requested_amount"])
	captivity_state["final_amount"] = floori(float(requested) * (1.0 - discount_rate))
	captivity_state["negotiated"] = true
	captivity_state["stage"] = "payment"
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "amount": int(captivity_state["final_amount"]), "discount_percent": int(discount_rate * 100.0)}


func contact_company_during_captivity() -> Dictionary:
	if not captivity_state.get("active", false) or captivity_state.get("stage") != "call":
		return {"ok": false, "reason": "invalid_captivity_stage"}
	var previous_state := _make_payload()
	captivity_state["stage"] = "negotiation"
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


func settle_captivity_payment() -> Dictionary:
	if not captivity_state.get("active", false) or captivity_state.get("stage") != "payment" or not captivity_state.get("negotiated", false):
		return {"ok": false, "reason": "invalid_captivity_stage"}
	var result_id := str(captivity_state["result_id"])
	if captivity_state.get("paid", false) or processed_result_ids.has(result_id + ":paid"):
		return {"ok": false, "reason": "duplicate_result"}
	var amount := int(captivity_state["final_amount"])
	var balance := int(accounts["corporate"])
	var shortfall := maxi(0, amount - balance)
	var previous_state := _make_payload()
	if shortfall > 0:
		var loan_id := result_id + ":rescue-loan"
		var next_due_index := floori(game_clock.elapsed_real_seconds / GameClockScript.REAL_SECONDS_PER_MONTH) + 1
		rescue_debts.append({"id": loan_id, "principal": shortfall, "remaining": shortfall, "installments_left": 3, "installment_base": floori(float(shortfall) / 3.0), "next_due_timestamp": game_clock.anniversary_timestamp(next_due_index)})
		accounts["corporate"] = balance + shortfall
		ledger.append({"id": loan_id, "kind": "rescue_loan", "account": "corporate", "amount": shortfall, "purpose": "captivity_release", "date": get_game_date_string()})
	accounts["corporate"] = int(accounts["corporate"]) - amount
	ledger.append({"id": result_id + ":ransom", "kind": "ransom_payment", "account": "corporate", "amount": -amount, "date": get_game_date_string()})
	processed_result_ids.append(result_id + ":paid")
	captivity_state["paid"] = true
	captivity_state["rescue_loan"] = shortfall
	captivity_state["stage"] = "released"
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "paid": amount, "loan": shortfall}


func complete_captivity_release() -> Dictionary:
	if not captivity_state.get("active", false) or captivity_state.get("stage") != "released" or not captivity_state.get("paid", false):
		return {"ok": false, "reason": "invalid_captivity_stage"}
	var previous_state := _make_payload()
	captivity_state["active"] = false
	captivity_state["stage"] = "complete"
	battle_state.clear()
	current_region = "seoul"
	player_position = Vector2(940.0, 418.0)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


func record_finance_operation(kind: String, amount: int, operation_id: String) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if operation_id.is_empty() or processed_order_ids.has(operation_id):
		return {"ok": false, "reason": "duplicate_order"}
	if amount <= 0:
		return {"ok": false, "reason": "invalid_amount"}
	var previous_state := _make_payload()
	if kind == "contribute":
		if int(accounts["personal"]) < amount:
			return {"ok": false, "reason": "insufficient_funds"}
		accounts["personal"] = int(accounts["personal"]) - amount
		accounts["corporate"] = int(accounts["corporate"]) + amount
		contribution_principal += amount
	elif kind == "return_contribution":
		if amount > contribution_principal or int(accounts["corporate"]) - amount < get_corporate_reserve():
			return {"ok": false, "reason": "insufficient_funds"}
		accounts["corporate"] = int(accounts["corporate"]) - amount
		accounts["personal"] = int(accounts["personal"]) + amount
		contribution_principal -= amount
	elif kind == "withdraw_profit":
		if amount > retained_realized_profit or int(accounts["corporate"]) - amount < get_corporate_reserve():
			return {"ok": false, "reason": "insufficient_funds"}
		accounts["corporate"] = int(accounts["corporate"]) - amount
		accounts["personal"] = int(accounts["personal"]) + amount
		retained_realized_profit -= amount
	else:
		return {"ok": false, "reason": "invalid_order"}
	if kind == "contribute":
		ledger.append({"id": operation_id, "kind": kind, "account": "personal", "amount": -amount})
		ledger.append({"id": operation_id, "kind": kind, "account": "corporate", "amount": amount})
	else:
		ledger.append({"id": operation_id, "kind": kind, "account": "corporate", "amount": -amount})
		ledger.append({"id": operation_id, "kind": kind, "account": "personal", "amount": amount})
	processed_order_ids.append(operation_id)
	if not save_game():
		_apply_payload(previous_state)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true}


## 현재 사옥 종류별 인원 정원을 반환한다.
func get_employee_capacity() -> int:
	return int(office_rules.get("office_tiers", {}).get(office_tier, {}).get("employee_capacity", 2))


## 현재 사옥의 월 임대료·관리비·직원 급여 합계를 계산한다.
func get_monthly_fixed_cost_total() -> int:
	var tier: Dictionary = office_rules.get("office_tiers", {}).get(office_tier, {})
	return int(tier.get("monthly_cost", 0)) + int(office_rules.get("monthly_staff_salary", 80000)) * employee_states.size()


## 출자 반환 전에 다음 월 고정비·대출이자·구조채무 분할금·미납을 보전한다.
func get_corporate_reserve() -> int:
	var reserve := get_monthly_fixed_cost_total()
	for loan in general_loans:
		reserve += int(loan.get("arrears", 0)) + floori(float(loan.get("principal", 0)) * float(office_rules.get("monthly_loan_interest_rate", 0.01)) + float(loan.get("interest_remainder", 0.0)))
	for debt in rescue_debts:
		if int(debt.get("installments_left", 0)) > 0:
			reserve += mini(int(debt.get("remaining", 0)), int(debt.get("installment_base", 0)))
	for invoice in unpaid_invoices:
		if str(invoice.get("status", "")) == "unpaid": reserve += int(invoice.get("amount", 0))
	return reserve


## 담보 사옥은 연결된 일반 대출의 원금·미납 이자를 모두 갚기 전 매각할 수 없다.
func can_sell_office() -> bool:
	if office_tier != "owned": return false
	for loan in general_loans:
		if bool(loan.get("collateral_office", false)) and (int(loan.get("principal", 0)) > 0 or int(loan.get("arrears", 0)) > 0): return false
	return true


## 법인 자금과 사옥 계약을 한 번에 바꾸고 저장 실패 시 되돌린다.
func upgrade_office(target_tier: String, operation_id: String) -> Dictionary:
	if captivity_state.get("active", false):
		return {"ok": false, "reason": "captivity_locked"}
	if processed_order_ids.has(operation_id) or operation_id.is_empty():
		return {"ok": false, "reason": "duplicate_order"}
	var tiers: Dictionary = office_rules.get("office_tiers", {})
	if not tiers.has(target_tier):
		return {"ok": false, "reason": "invalid_tier"}
	var target: Dictionary = tiers[target_tier]
	if (office_tier == "rented_base" and target_tier != "rented_expanded" and target_tier != "owned") or (office_tier == "rented_expanded" and target_tier != "owned") or office_tier == "owned":
		return {"ok": false, "reason": "invalid_upgrade"}
	var price := int(target.get("move_in_cost", office_rules.get("expanded_move_in_cost", 0) if target_tier == "rented_expanded" else office_rules.get("owned_purchase_price", 0)))
	if int(accounts.corporate) < price:
		return {"ok": false, "reason": "insufficient_funds"}
	if employee_states.size() > int(target["employee_capacity"]):
		return {"ok": false, "reason": "capacity"}
	var previous := _make_payload()
	office_tier = target_tier
	if target_tier == "owned": office_purchase_price = price
	accounts.corporate = int(accounts.corporate) - price
	processed_order_ids.append(operation_id)
	ledger.append({"id": operation_id, "kind": "office_upgrade", "asset_id": target_tier, "account": "corporate", "amount": -price, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "price": price, "tier": office_tier}


## 직원 채용은 정원 안에서만 하고, 월 급여는 납부일 정산에 포함한다.
func hire_employee(operation_id: String, role: String = "general") -> Dictionary:
	if captivity_state.get("active", false): return {"ok": false, "reason": "captivity_locked"}
	if processed_order_ids.has(operation_id) or operation_id.is_empty(): return {"ok": false, "reason": "duplicate_order"}
	if employee_states.size() >= get_employee_capacity(): return {"ok": false, "reason": "capacity"}
	var previous := _make_payload()
	staff_counter += 1
	var employee_id := "staff_%02d" % staff_counter
	employee_states[employee_id] = {"assignment": "office_standby", "last_task_id": "", "role": role, "level": 1, "cargo_capacity_g": PERSON_CAPACITY_G}
	inventories[employee_id] = {}
	inventory_costs[employee_id] = {}
	processed_order_ids.append(operation_id)
	ledger.append({"id": operation_id, "kind": "employee_hire", "employee_id": employee_id, "account": "corporate", "amount": 0, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "employee_id": employee_id}


## 일반 대출은 담보 한도 안에서만 실행하고 석방 전용 구조 채무와 분리한다.
func get_general_loan_limit() -> int:
	var secured_value := office_purchase_price if office_tier == "owned" else 0
	var principal := 0
	for loan in general_loans: principal += int(loan.get("principal", 0))
	return maxi(0, int(office_rules.get("unsecured_loan_limit", 200000)) + floori(float(secured_value) * float(office_rules.get("collateral_ratio", 0.4))) - principal)


func take_general_loan(amount: int, operation_id: String) -> Dictionary:
	if captivity_state.get("active", false): return {"ok": false, "reason": "captivity_locked"}
	if amount <= 0 or amount > get_general_loan_limit(): return {"ok": false, "reason": "loan_limit"}
	if operation_id.is_empty() or processed_order_ids.has(operation_id): return {"ok": false, "reason": "duplicate_order"}
	var previous := _make_payload()
	var next_index := floori(game_clock.elapsed_real_seconds / GameClockScript.REAL_SECONDS_PER_MONTH) + 1
	var loan := {"id": operation_id, "principal": amount, "arrears": 0, "interest_remainder": 0.0, "next_due_index": next_index, "next_due_timestamp": game_clock.anniversary_timestamp(next_index), "collateral_office": office_tier == "owned"}
	general_loans.append(loan)
	accounts.corporate = int(accounts.corporate) + amount
	processed_order_ids.append(operation_id)
	ledger.append({"id": operation_id, "kind": "general_loan", "account": "corporate", "amount": amount, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "loan_id": operation_id, "amount": amount}


func repay_general_loan(loan_id: String, amount: int, operation_id: String) -> Dictionary:
	if captivity_state.get("active", false): return {"ok": false, "reason": "captivity_locked"}
	if amount <= 0 or int(accounts.corporate) < amount or processed_order_ids.has(operation_id): return {"ok": false, "reason": "invalid_payment"}
	var index := -1
	for i in general_loans.size():
		if str(general_loans[i].get("id", "")) == loan_id: index = i
	if index < 0 or amount > int(general_loans[index].get("principal", 0)): return {"ok": false, "reason": "invalid_payment"}
	var previous := _make_payload()
	var loan: Dictionary = general_loans[index]
	loan["principal"] = int(loan["principal"]) - amount
	general_loans[index] = loan
	accounts.corporate = int(accounts.corporate) - amount
	processed_order_ids.append(operation_id)
	ledger.append({"id": operation_id, "kind": "general_loan_principal", "account": "corporate", "amount": -amount, "date": get_game_date_string()})
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "remaining_principal": int(loan["principal"])}


## 작업장 세션은 세계 시계를 멈추고 보상은 개인계좌로 한 번만 지급한다.
func start_mahjong(level_id: String, region_id: String, board: Array) -> Dictionary:
	if mahjong_state.get("active", false): return {"ok": false, "reason": "already_active"}
	if not region_definitions.has(region_id) or not mahjong_unlocked_levels.has(level_id): return {"ok": false, "reason": "locked"}
	var level_file := FileAccess.open("res://data/mahjong_levels.json", FileAccess.READ)
	var levels: Variant = JSON.parse_string(level_file.get_as_text()) if level_file != null else []
	if level_file != null: level_file.close()
	var definition: Dictionary = {}
	if levels is Array:
		for item in levels:
			if str(item.get("id", "")) == level_id: definition = item
	if definition.is_empty() or mahjong_fatigue + int(definition.fatigue_cost) > 100: return {"ok": false, "reason": "fatigue"}
	var previous := _make_payload()
	mahjong_fatigue += int(definition.fatigue_cost)
	mahjong_state = {"active": true, "level_id": level_id, "region_id": region_id, "board": board.duplicate(true), "started_wall_msec": Time.get_ticks_msec(), "reward_id": "mahjong:%s:%s:%d" % [region_id, level_id, Time.get_ticks_usec()], "hint_used": false}
	set_pause_reason("mahjong", true)
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	state_changed.emit()
	return {"ok": true}


func finish_mahjong(success: bool, result_id: String) -> Dictionary:
	if not mahjong_state.get("active", false) or result_id != str(mahjong_state.get("reward_id", "")) or processed_mahjong_rewards.has(result_id):
		return {"ok": false, "reason": "duplicate_or_inactive"}
	if success:
		for tile in mahjong_state.get("board", []):
			if int(tile) != 0: return {"ok": false, "reason": "board_not_cleared"}
	var previous := _make_payload()
	var payout := 0
	var level_id := str(mahjong_state.level_id)
	if success:
		var levels_file := FileAccess.open("res://data/mahjong_levels.json", FileAccess.READ)
		var levels: Variant = JSON.parse_string(levels_file.get_as_text()) if levels_file != null else []
		if levels_file != null: levels_file.close()
		if levels is Array:
			for item in levels:
				if str(item.id) == level_id:
					payout = roundi(float(item.reward) * float(region_definitions.get(str(mahjong_state.region_id), {}).get("payout_multiplier", 1.0)))
					var next_level := "intermediate" if level_id == "beginner" else ("advanced" if level_id == "intermediate" else "")
					if not next_level.is_empty() and not mahjong_unlocked_levels.has(next_level): mahjong_unlocked_levels.append(next_level)
			accounts.personal = int(accounts.personal) + payout
			ledger.append({"id": result_id, "kind": "mahjong_reward", "account": "personal", "amount": payout, "region_id": mahjong_state.region_id, "date": get_game_date_string()})
	processed_mahjong_rewards.append(result_id)
	mahjong_state["active"] = false
	mahjong_state["result"] = "success" if success else "failed"
	set_pause_reason("mahjong", false)
	if not save_game():
		_apply_payload(previous)
		return {"ok": false, "reason": "save_failed"}
	state_changed.emit()
	return {"ok": true, "payout": payout, "success": success}


## 현 인물의 상품 매입원가와 지역 매도로 인한 실현 손익을 계산한다.
func estimate_realized_profit(person_id: String, product_id: String) -> int:
	var net := 0
	for entry in ledger:
		if entry.get("kind") == "trade" and entry.get("person_id") == person_id and entry.get("product_id") == product_id:
			net += int(entry.get("realized_profit", 0))
	return net


func update_world_state(region_id: String, position: Vector2, notify_ui: bool = true) -> void:
	if not REGION_IDS.has(region_id):
		return
	var should_save := current_region != region_id or player_position.distance_squared_to(position) >= 400.0
	current_region = region_id
	player_position = position
	if not should_save:
		return
	save_game()
	if notify_ui:
		state_changed.emit()


func switch_region(region_id: String, position: Vector2) -> void:
	if not REGION_IDS.has(region_id):
		return
	current_region = region_id
	player_position = position
	save_game()
	state_changed.emit()


func save_game() -> bool:
	var parent_path := save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent_path)) and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent_path)) != OK:
		return false
	return _write_payload(_make_payload())


func _make_payload() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "game_version": "phase5",
		"world": {"region_id": current_region, "player_position": {"x": player_position.x, "y": player_position.y}},
		"party_ids": party_ids.duplicate(), "accounts": accounts.duplicate(true), "contribution_principal": contribution_principal,
		"retained_realized_profit": retained_realized_profit, "ledger": ledger.duplicate(true),
		"inventories": inventories.duplicate(true), "inventory_costs": inventory_costs.duplicate(true), "market_states": market_states.duplicate(true), "processed_order_ids": processed_order_ids.duplicate(),
		"clock": game_clock.save_state(), "employee_states": employee_states.duplicate(true), "staff_tasks": staff_tasks.duplicate(true),
		"market_reports": market_reports.duplicate(true), "event_states": event_states.duplicate(true), "pending_news_ids": pending_news_ids.duplicate(),
		"processed_invoice_ids": processed_invoice_ids.duplicate(), "unpaid_invoices": unpaid_invoices.duplicate(true), "daily_alerts": daily_alerts.duplicate(),
		"contract_start_timestamp": contract_start_timestamp, "contract_day": contract_day, "rng_state": rng_state,
		"owned_vehicle_ids": owned_vehicle_ids.duplicate(), "active_vehicle_id": active_vehicle_id,
		"vehicle_cost_remainders": vehicle_cost_remainders.duplicate(true), "travel_meter_remainder": travel_meter_remainder,
		"parked_vehicles": parked_vehicles.duplicate(true), "cargo_caches": cargo_caches.duplicate(true),
		"mercenaries": mercenaries.duplicate(true), "mercenary_roster": mercenary_roster.duplicate(),
		"free_revival_date": free_revival_date, "battle_state": battle_state.duplicate(true),
		"captivity_state": captivity_state.duplicate(true), "processed_result_ids": processed_result_ids.duplicate(), "rescue_debts": rescue_debts.duplicate(true),
		"enemy_states": enemy_states.duplicate(true), "enemy_grace_seconds_remaining": enemy_grace_seconds_remaining,
		"office_tier": office_tier, "office_purchase_price": office_purchase_price, "general_loans": general_loans.duplicate(true), "general_loan_arrears": general_loan_arrears, "staff_counter": staff_counter,
		"mahjong_fatigue": mahjong_fatigue, "mahjong_unlocked_levels": mahjong_unlocked_levels.duplicate(), "mahjong_state": mahjong_state.duplicate(true), "processed_mahjong_rewards": processed_mahjong_rewards.duplicate(),
	}


func _write_payload(payload: Dictionary) -> bool:
	var parent_path := save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent_path)) and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent_path)) != OK:
		return false
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("저장 임시 파일 열기 실패: %s" % temporary)
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	var verify := FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		push_error("임시 저장 검증 파일 열기 실패: %s" % temporary)
		return false
	var parsed: Variant = JSON.parse_string(verify.get_as_text())
	verify.close()
	if not parsed is Dictionary or not _validate_payload(parsed):
		push_error("저장 임시 파일의 JSON 또는 스키마 검증 실패")
		return false
	var absolute_temp := ProjectSettings.globalize_path(temporary)
	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_backup := ProjectSettings.globalize_path(save_path + ".bak")
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(save_path + ".bak"):
			DirAccess.remove_absolute(absolute_backup)
		if DirAccess.rename_absolute(absolute_save, absolute_backup) != OK:
			push_error("기존 저장 백업 교체 실패: %s" % absolute_save)
			return false
	var replace_error := DirAccess.rename_absolute(absolute_temp, absolute_save)
	if replace_error != OK:
		push_error("임시 저장 파일을 본 저장으로 교체 실패: %s (오류 %s, 임시 파일 존재 %s)" % [absolute_save, error_string(replace_error), FileAccess.file_exists(temporary)])
		if FileAccess.file_exists(save_path + ".bak"):
			DirAccess.rename_absolute(absolute_backup, absolute_save)
		return false
	return true


func _validate_payload(payload: Dictionary) -> bool:
	if int(payload.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var world: Variant = payload.get("world", {})
	if not world is Dictionary or not REGION_IDS.has(world.get("region_id", "")):
		return false
	var saved_accounts: Variant = payload.get("accounts", {})
	var saved_inventory: Variant = payload.get("inventories", {})
	var saved_costs: Variant = payload.get("inventory_costs", {})
	var saved_markets: Variant = payload.get("market_states", {})
	var saved_ledger: Variant = payload.get("ledger", [])
	if not saved_accounts is Dictionary or not saved_inventory is Dictionary or not saved_costs is Dictionary or not saved_markets is Dictionary or not saved_ledger is Array:
		return false
	if not saved_accounts.has("personal") or not saved_accounts.has("corporate"):
		return false
	if int(saved_accounts["personal"]) < 0 or int(saved_accounts["corporate"]) < 0:
		return false
	var saved_party: Variant = payload.get("party_ids", [])
	if not saved_party is Array or saved_party.size() > 4 or not saved_party.has("player"):
		return false
	for person_id in saved_inventory:
		if not saved_inventory[person_id] is Dictionary:
			return false
		for count in saved_inventory[person_id].values():
			if int(count) < 0:
				return false
		for product_id in saved_inventory[person_id]:
			if not products.has(product_id):
				return false
			var costs: Variant = saved_costs.get(person_id, {}).get(product_id, null)
			if not costs is Array or costs.size() != int(saved_inventory[person_id][product_id]):
				return false
		var saved_weight := 0
		for product_id in saved_inventory[person_id]:
			saved_weight += int(saved_inventory[person_id][product_id]) * int(products[product_id]["unit_weight_g"])
		if not str(person_id).begins_with("vehicle:"):
			var saved_capacity := PERSON_CAPACITY_G
			var saved_employees: Variant = payload.get("employee_states", {})
			if person_id != "player" and saved_employees is Dictionary and saved_employees.get(person_id, {}) is Dictionary:
				saved_capacity = int(saved_employees.get(person_id, {}).get("cargo_capacity_g", PERSON_CAPACITY_G))
			if saved_capacity <= 0 or saved_weight > saved_capacity:
				return false
	for entry in saved_ledger:
		if not entry is Dictionary or not entry.has("id"):
			return false
	var clock_state: Variant = payload.get("clock", null)
	if not clock_state is Dictionary:
		return false
	var test_clock = GameClockScript.new()
	if not test_clock.load_state(clock_state):
		return false
	if not payload.get("employee_states", {}) is Dictionary or not payload.get("employee_states", {}).has("staff_01") or not payload.get("staff_tasks", {}) is Dictionary or not payload.get("event_states", {}) is Dictionary:
		return false
	if not payload.get("market_reports", []) is Array or not payload.get("pending_news_ids", []) is Array or not payload.get("processed_invoice_ids", []) is Array:
		return false
	if not payload.get("unpaid_invoices", []) is Array or not payload.get("daily_alerts", []) is Array:
		return false
	if not payload.get("owned_vehicle_ids", []) is Array or not payload.get("vehicle_cost_remainders", {}) is Dictionary or not payload.get("mercenaries", {}) is Dictionary or not payload.get("mercenary_roster", []) is Array:
		return false
	if not payload.get("parked_vehicles", []) is Array or not payload.get("cargo_caches", []) is Array or not payload.get("battle_state", {}) is Dictionary or not payload.get("captivity_state", {}) is Dictionary or not payload.get("processed_result_ids", []) is Array or not payload.get("rescue_debts", []) is Array or not payload.get("enemy_states", {}) is Dictionary:
		return false
	if not payload.get("general_loans", []) is Array or not payload.get("mahjong_unlocked_levels", []) is Array or not payload.get("mahjong_state", {}) is Dictionary or not payload.get("processed_mahjong_rewards", []) is Array:
		return false
	if int(payload.get("mahjong_fatigue", -1)) < 0 or int(payload.get("mahjong_fatigue", 101)) > 100 or not office_rules.get("office_tiers", {}).has(str(payload.get("office_tier", ""))):
		return false
	var active_vehicle := str(payload.get("active_vehicle_id", ""))
	if not active_vehicle.is_empty() and not payload["owned_vehicle_ids"].has(active_vehicle):
		return false
	for vehicle_id in payload["owned_vehicle_ids"]:
		if not vehicle_definitions.has(vehicle_id):
			return false
		var owner_id := "vehicle:" + str(vehicle_id)
		var vehicle_weight := 0
		for product_id in saved_inventory.get(owner_id, {}):
			if not products.has(product_id) or int(saved_inventory[owner_id][product_id]) < 0:
				return false
			vehicle_weight += int(saved_inventory[owner_id][product_id]) * int(products[product_id]["unit_weight_g"])
		if vehicle_weight > int(vehicle_definitions[vehicle_id]["capacity_g"]):
			return false
	var saved_cost_remainders: Dictionary = payload.get("vehicle_cost_remainders", {})
	for vehicle_id in saved_cost_remainders:
		var remainder := float(saved_cost_remainders[vehicle_id])
		if not vehicle_definitions.has(vehicle_id) or remainder < 0.0 or remainder >= 1.0:
			return false
	if float(payload.get("travel_meter_remainder", 0.0)) < 0.0:
		return false
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _load_backup()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _load_backup()
	var version := int(parsed.get("schema_version", -1))
	if version == LEGACY_SCHEMA_VERSION:
		return _migrate_legacy_save(parsed)
	if version == PHASE2_SCHEMA_VERSION:
		if _migrate_phase2_save(parsed):
			return true
		return _load_backup()
	if version == PREVIOUS_SCHEMA_VERSION:
		if _migrate_phase3_save(parsed):
			return true
		return _load_backup()
	if version == PHASE4_SCHEMA_VERSION:
		if _migrate_phase4_save(parsed): return true
		return _load_backup()
	if not _validate_payload(parsed):
		return _load_backup()
	_apply_payload(parsed)
	return true


func _migrate_legacy_save(payload: Dictionary) -> bool:
	if not _apply_legacy_save_state(payload):
		return false
	return save_game()


## Phase 2의 계좌·화물·시장 상태를 보존하며 달력 기능의 기본값만 덧붙인다.
func _migrate_phase2_save(payload: Dictionary) -> bool:
	if not _validate_phase2_payload(payload):
		return false
	var converted := payload.duplicate(true)
	converted["schema_version"] = SCHEMA_VERSION
	converted["game_version"] = "phase5"
	var clock = GameClockScript.new()
	converted["clock"] = clock.save_state()
	var employee_id := "staff_01"
	var assignment := "companion" if converted.get("party_ids", []).has(employee_id) else "office_standby"
	converted["employee_states"] = {employee_id: {"assignment": assignment, "last_task_id": ""}}
	converted["staff_tasks"] = {}
	converted["market_reports"] = []
	converted["event_states"] = {}
	for event_id in event_definitions:
		converted["event_states"][event_id] = {"started": false, "active": false, "ended": false, "read": false}
	converted["pending_news_ids"] = []
	converted["processed_invoice_ids"] = []
	converted["unpaid_invoices"] = []
	converted["daily_alerts"] = []
	converted["contract_start_timestamp"] = _date_to_timestamp(str(office_rules.get("contract_start", "2025-01-20")))
	converted["contract_day"] = int(str(office_rules.get("contract_start", "2025-01-20")).substr(8, 2))
	converted["rng_state"] = 20250120
	for market_key in converted["market_states"]:
		var market_state: Dictionary = converted["market_states"][market_key]
		market_state["production_remainder"] = 0.0
		market_state["consumption_remainder"] = 0.0
		market_state["trend_percent"] = 0.0
		market_state["trend_days"] = 0
		market_state["price_history"] = []
		converted["market_states"][market_key] = market_state
	_add_phase4_defaults(converted)
	_add_phase5_defaults(converted)
	if not _validate_payload(converted):
		return false
	_apply_payload(converted)
	return save_game()


func _validate_phase2_payload(payload: Dictionary) -> bool:
	if int(payload.get("schema_version", -1)) != PHASE2_SCHEMA_VERSION:
		return false
	var world: Variant = payload.get("world", {})
	var accounts_data: Variant = payload.get("accounts", {})
	var inventories_data: Variant = payload.get("inventories", {})
	var markets_data: Variant = payload.get("market_states", {})
	return world is Dictionary and REGION_IDS.has(world.get("region_id", "")) and accounts_data is Dictionary and inventories_data is Dictionary and markets_data is Dictionary


## Phase 3 저장의 경제·뉴스·시계 데이터를 보존하고 P1 상태만 기본값으로 추가한다.
func _migrate_phase3_save(payload: Dictionary) -> bool:
	if int(payload.get("schema_version", -1)) != PREVIOUS_SCHEMA_VERSION or not _validate_phase3_payload(payload):
		return false
	var converted := payload.duplicate(true)
	converted["schema_version"] = SCHEMA_VERSION
	converted["game_version"] = "phase5"
	_add_phase4_defaults(converted)
	_add_phase5_defaults(converted)
	if not _validate_payload(converted):
		return false
	_apply_payload(converted)
	return save_game()


func _validate_phase3_payload(payload: Dictionary) -> bool:
	return int(payload.get("schema_version", -1)) == PREVIOUS_SCHEMA_VERSION \
		and payload.get("world", {}) is Dictionary \
		and payload.get("accounts", {}) is Dictionary \
		and payload.get("inventories", {}) is Dictionary \
		and payload.get("market_states", {}) is Dictionary \
		and payload.get("clock", {}) is Dictionary


## 구버전에는 없던 차량·용병·조우·피랍 상태의 빈 기본값을 만든다.
func _add_phase4_defaults(payload: Dictionary) -> void:
	var inventories_data: Dictionary = payload.get("inventories", {})
	var costs_data: Dictionary = payload.get("inventory_costs", {})
	payload["inventories"] = inventories_data
	payload["inventory_costs"] = costs_data
	payload["owned_vehicle_ids"] = []
	payload["active_vehicle_id"] = ""
	payload["vehicle_cost_remainders"] = {}
	payload["travel_meter_remainder"] = 0.0
	payload["parked_vehicles"] = []
	payload["cargo_caches"] = []
	payload["mercenaries"] = {"basic_01": {"type_id": "basic", "hp": 100, "owned": true}}
	payload["mercenary_roster"] = ["basic_01"]
	payload["free_revival_date"] = ""
	payload["battle_state"] = {}
	payload["captivity_state"] = {}
	payload["processed_result_ids"] = []
	payload["rescue_debts"] = []
	payload["enemy_states"] = {}
	payload["enemy_grace_seconds_remaining"] = 0.0


## schema 4 상태를 유지하고 P1 국내 성장·작업장 상태의 기본값을 추가한다.
func _migrate_phase4_save(payload: Dictionary) -> bool:
	if int(payload.get("schema_version", -1)) != PHASE4_SCHEMA_VERSION or not payload.get("world", {}) is Dictionary or not payload.get("accounts", {}) is Dictionary:
		return false
	var converted := payload.duplicate(true)
	converted["schema_version"] = SCHEMA_VERSION
	converted["game_version"] = "phase5"
	_add_phase5_defaults(converted)
	if not _validate_payload(converted): return false
	_apply_payload(converted)
	return save_game()


func _add_phase5_defaults(payload: Dictionary) -> void:
	payload["office_tier"] = str(payload.get("office_tier", "rented_base"))
	payload["office_purchase_price"] = int(payload.get("office_purchase_price", 0))
	payload["general_loans"] = payload.get("general_loans", [])
	payload["general_loan_arrears"] = int(payload.get("general_loan_arrears", 0))
	payload["staff_counter"] = maxi(1, int(payload.get("staff_counter", 1)))
	payload["mahjong_fatigue"] = int(payload.get("mahjong_fatigue", 0))
	payload["mahjong_unlocked_levels"] = payload.get("mahjong_unlocked_levels", ["beginner"])
	payload["mahjong_state"] = payload.get("mahjong_state", {})
	payload["processed_mahjong_rewards"] = payload.get("processed_mahjong_rewards", [])
	var employees: Dictionary = payload.get("employee_states", {})
	var counter := maxi(1, int(payload["staff_counter"]))
	for employee_id in employees:
		if not employees[employee_id] is Dictionary: continue
		var employee: Dictionary = employees[employee_id]
		employee["role"] = str(employee.get("role", "general"))
		employee["level"] = maxi(1, int(employee.get("level", 1)))
		employee["cargo_capacity_g"] = maxi(1, int(employee.get("cargo_capacity_g", PERSON_CAPACITY_G)))
		employees[employee_id] = employee
		var suffix := str(employee_id).trim_prefix("staff_")
		if suffix.is_valid_int(): counter = maxi(counter, int(suffix))
	payload["employee_states"] = employees
	payload["staff_counter"] = counter


func _apply_legacy_save_state(payload: Dictionary) -> bool:
	var world: Variant = payload.get("world", {})
	if not world is Dictionary or not REGION_IDS.has(world.get("region_id", "")):
		world = {"region_id": "seoul", "player_position": {"x": 760.0, "y": 470.0}}
	current_region = world["region_id"]
	var pos: Variant = world.get("player_position", {"x": 760.0, "y": 470.0})
	player_position = Vector2(float(pos.get("x", 760.0)), float(pos.get("y", 470.0)))
	var saved_party: Variant = payload.get("party_ids", ["player", "staff_01"])
	party_ids.clear()
	if saved_party is Array:
		for person_id in saved_party.slice(0, 4):
			party_ids.append(str(person_id))
	if not party_ids.has("player"):
		party_ids.push_front("player")
	_reset_economic_state()
	return true


func _reset_economic_state() -> void:
	accounts = {"personal": STARTING_PERSONAL_CASH, "corporate": STARTING_CORPORATE_CASH}
	contribution_principal = STARTING_CAPITAL
	retained_realized_profit = 0
	ledger = [
		{"id": "opening-personal", "kind": "opening_balance", "account": "personal", "amount": STARTING_PERSONAL_CASH},
		{"id": "opening-corporate", "kind": "opening_balance", "account": "corporate", "amount": STARTING_CORPORATE_CASH},
	]
	inventories.clear()
	inventory_costs.clear()
	for person_id in party_ids:
		inventories[person_id] = {}
		inventory_costs[person_id] = {}
	if not inventories.has("staff_01"):
		inventories["staff_01"] = {}
		inventory_costs["staff_01"] = {}
	processed_order_ids.clear()
	market_states.clear()
	for market_id in market_definitions:
		for product_id in market_definitions[market_id]["product_ids"]:
			var product: Dictionary = products[product_id]
			var definition: Dictionary = market_definitions[market_id]
			var region_id: String = definition["region_id"]
			var base: float = float(product["base_price"]) * float(product["regions"][region_id])
			market_states[market_id + ":" + product_id] = {"stock": int(definition["initial_stock"]), "target_stock": int(definition["target_stock"]), "reference_stock": int(definition["initial_stock"]), "reference_price": base, "base_price": base, "production_remainder": 0.0, "consumption_remainder": 0.0, "trend_percent": 0.0, "trend_days": 0, "price_history": []}
	_reset_phase3_state()


func _load_backup() -> bool:
	var backup_path := save_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		return false
	var file := FileAccess.open(backup_path, FileAccess.READ)
	if file == null:
		return false
	var payload: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not payload is Dictionary:
		return false
	if int(payload.get("schema_version", -1)) == LEGACY_SCHEMA_VERSION:
		if not _apply_legacy_save_state(payload):
			return false
		return _restore_backup_file(_make_payload())
	if int(payload.get("schema_version", -1)) == PHASE2_SCHEMA_VERSION:
		if not _migrate_phase2_save(payload):
			return false
		return _restore_backup_file(_make_payload())
	if int(payload.get("schema_version", -1)) == 3:
		if not _migrate_phase3_save(payload):
			return false
		return _restore_backup_file(_make_payload())
	if int(payload.get("schema_version", -1)) == PHASE4_SCHEMA_VERSION:
		if not _migrate_phase4_save(payload): return false
		return _restore_backup_file(_make_payload())
	if not _validate_payload(payload):
		return false
	_apply_payload(payload)
	return _restore_backup_file(payload)


func _restore_backup_file(payload: Dictionary) -> bool:
	var temporary := save_path + ".recover.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	var verify := FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		return false
	var parsed: Variant = JSON.parse_string(verify.get_as_text())
	verify.close()
	if not parsed is Dictionary or not _validate_payload(parsed):
		return false
	var primary_path := ProjectSettings.globalize_path(save_path)
	var temporary_path := ProjectSettings.globalize_path(temporary)
	var corrupt_path := ProjectSettings.globalize_path(save_path + ".corrupt")
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(save_path + ".corrupt"):
			DirAccess.remove_absolute(corrupt_path)
		if DirAccess.rename_absolute(primary_path, corrupt_path) != OK:
			return false
	if DirAccess.rename_absolute(temporary_path, primary_path) != OK:
		if FileAccess.file_exists(save_path + ".corrupt"):
			DirAccess.rename_absolute(corrupt_path, primary_path)
		return false
	return true


func _apply_payload(payload: Dictionary) -> void:
	var world: Dictionary = payload["world"]
	current_region = world["region_id"]
	var position: Dictionary = world.get("player_position", {"x": 760.0, "y": 470.0})
	player_position = Vector2(float(position.get("x", 760.0)), float(position.get("y", 470.0)))
	party_ids.clear()
	for person_id in payload.get("party_ids", ["player", "staff_01"]):
		party_ids.append(str(person_id))
	accounts = payload["accounts"].duplicate(true)
	contribution_principal = int(payload.get("contribution_principal", STARTING_CAPITAL))
	retained_realized_profit = int(payload.get("retained_realized_profit", 0))
	ledger.assign(payload.get("ledger", []))
	inventories = payload["inventories"].duplicate(true)
	inventory_costs = payload.get("inventory_costs", {}).duplicate(true)
	market_states = payload["market_states"].duplicate(true)
	for market_id in market_definitions:
		var definition: Dictionary = market_definitions[market_id]
		for product_id in definition["product_ids"]:
			var market_key := str(market_id) + ":" + str(product_id)
			if not market_states.has(market_key):
				market_states[market_key] = _make_initial_market_state(str(market_id), str(product_id))
	processed_order_ids.assign(payload.get("processed_order_ids", []))
	game_clock = GameClockScript.new()
	game_clock.load_state(payload["clock"])
	employee_states = payload["employee_states"].duplicate(true)
	staff_tasks = payload["staff_tasks"].duplicate(true)
	market_reports.assign(payload["market_reports"])
	event_states = payload["event_states"].duplicate(true)
	pending_news_ids.assign(payload["pending_news_ids"])
	processed_invoice_ids.assign(payload["processed_invoice_ids"])
	unpaid_invoices.assign(payload["unpaid_invoices"])
	daily_alerts.assign(payload["daily_alerts"])
	contract_start_timestamp = int(payload["contract_start_timestamp"])
	contract_day = int(payload["contract_day"])
	rng_state = int(payload["rng_state"])
	owned_vehicle_ids.assign(payload.get("owned_vehicle_ids", []))
	active_vehicle_id = str(payload.get("active_vehicle_id", ""))
	vehicle_cost_remainders = payload.get("vehicle_cost_remainders", {}).duplicate(true)
	travel_meter_remainder = float(payload.get("travel_meter_remainder", 0.0))
	parked_vehicles.assign(payload.get("parked_vehicles", []))
	cargo_caches.assign(payload.get("cargo_caches", []))
	mercenaries = payload.get("mercenaries", {}).duplicate(true)
	mercenary_roster.assign(payload.get("mercenary_roster", []))
	free_revival_date = str(payload.get("free_revival_date", ""))
	battle_state = payload.get("battle_state", {}).duplicate(true)
	captivity_state = payload.get("captivity_state", {}).duplicate(true)
	processed_result_ids.assign(payload.get("processed_result_ids", []))
	rescue_debts.assign(payload.get("rescue_debts", []))
	office_tier = str(payload.get("office_tier", "rented_base"))
	office_purchase_price = int(payload.get("office_purchase_price", 0))
	general_loans.assign(payload.get("general_loans", []))
	general_loan_arrears = int(payload.get("general_loan_arrears", 0))
	staff_counter = int(payload.get("staff_counter", 1))
	mahjong_fatigue = int(payload.get("mahjong_fatigue", 0))
	mahjong_unlocked_levels.assign(payload.get("mahjong_unlocked_levels", ["beginner"]))
	mahjong_state = payload.get("mahjong_state", {}).duplicate(true)
	processed_mahjong_rewards.assign(payload.get("processed_mahjong_rewards", []))
	if mahjong_state.get("active", false):
		mahjong_state["active"] = false
		mahjong_state["result"] = "forced_exit"
	enemy_states = payload.get("enemy_states", {}).duplicate(true)
	enemy_grace_seconds_remaining = maxf(0.0, float(payload.get("enemy_grace_seconds_remaining", 0.0)))
	pause_reasons.clear()
	news_overlay_open = false
	is_processing_day = false
	queued_daily_alerts.clear()
	for person_id in party_ids:
		if not inventories.has(person_id):
			inventories[person_id] = {}
		if not inventory_costs.has(person_id):
			inventory_costs[person_id] = {}
	if not inventories.has("staff_01"):
		inventories["staff_01"] = {}
		inventory_costs["staff_01"] = {}


## 계좌·화물·원장·재고를 사용자 저장과 분리한 테스트 경로로 복구한다.
func restore_payload_for_test(payload: Dictionary) -> bool:
	if not _validate_payload(payload):
		return false
	_apply_payload(payload)
	return true
