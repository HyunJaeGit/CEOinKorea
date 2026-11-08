## Phase 2 거래 규칙을 사용자 세이브와 분리해 최소 확인한다.
extends Node

const SEAFOOD_MARKET := "incheon_seafood"
const PRODUCT_ID := "seafood"
var failure_count := 0

func _ready() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	GameSession.save_path = "user://phase2_checks/session.json"
	_fresh("incheon")
	_check_successful_trade_and_cancel()
	_check_region_price_difference()
	_check_failure_conditions()
	_check_same_market_resale()
	_check_split_order_equivalence()
	_check_duplicate_confirmation()
	_check_finance_account_separation()
	_check_save_restore_and_backup()
	_check_legacy_migration()
	if failure_count == 0:
		print("PHASE2_CHECKS_OK: 9 groups")
	else:
		printerr("PHASE2_CHECKS_FAILED: %d checks" % failure_count)
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

func _fresh(region_id: String) -> void:
	GameSession._reset_new_game_state()
	GameSession.current_region = region_id
	GameSession.player_position = Vector2(500.0, 500.0)

func _buy(order_id: String, quantity: int = 1) -> Dictionary:
	return GameSession.execute_trade(order_id, SEAFOOD_MARKET, PRODUCT_ID, "buy", "player", quantity)

func _check_successful_trade_and_cancel() -> void:
	var before := GameSession._make_payload()
	_expect(GameSession.cancel_trade("cancel-check")["ok"], "pending order cancels")
	var canceled := GameSession._make_payload()
	_expect(JSON.stringify(before) == JSON.stringify(canceled), "cancel must not mutate account, cargo, market, or ledger")
	var old_cash: int = GameSession.accounts["corporate"]
	var old_stock := GameSession.get_market_stock(SEAFOOD_MARKET, PRODUCT_ID)
	var result := _buy("check-success")
	_expect(result["ok"], "normal purchase succeeds")
	_expect(GameSession.accounts["corporate"] == old_cash - result["total"], "corporate account settles purchase")
	_expect(GameSession.get_inventory_count("player", PRODUCT_ID) == 1, "purchase enters selected person's inventory")
	_expect(GameSession.get_market_stock(SEAFOOD_MARKET, PRODUCT_ID) == old_stock - 1, "market stock decreases")
	_expect(GameSession.ledger.size() == 3, "purchase records a corporate ledger entry after opening balances")

func _check_failure_conditions() -> void:
	_fresh("incheon")
	GameSession.accounts["corporate"] = 0
	var funds := _buy("check-no-funds")
	_expect(funds.get("reason") == "insufficient_funds", "funds shortage reason")
	_expect(GameSession.accounts["corporate"] == 0 and GameSession.get_market_stock(SEAFOOD_MARKET, PRODUCT_ID) == 300, "funds failure has no partial transaction")
	_fresh("incheon")
	GameSession.market_states[SEAFOOD_MARKET + ":" + PRODUCT_ID]["stock"] = 0
	var stock := _buy("check-no-stock")
	_expect(stock.get("reason") == "insufficient_stock", "stock shortage reason")
	_fresh("incheon")
	GameSession.inventories["player"][PRODUCT_ID] = 20
	GameSession.inventory_costs["player"][PRODUCT_ID] = []
	for _unit in 20:
		GameSession.inventory_costs["player"][PRODUCT_ID].append(1)
	var capacity := _buy("check-capacity")
	_expect(capacity.get("reason") == "capacity_exceeded", "person capacity reason")
	_fresh("incheon")
	var unsupported := GameSession.execute_trade("check-unlisted", "incheon_seafood", "rice", "buy", "player", 1)
	_expect(unsupported.get("reason") == "not_traded", "unlisted product reason")
	_fresh("incheon")
	var starting_accounts := JSON.stringify(GameSession.accounts)
	var starting_cargo := JSON.stringify(GameSession.inventories)
	var starting_ledger := GameSession.ledger.size()
	var starting_market := JSON.stringify(GameSession.market_states)
	var missing_goods := GameSession.execute_trade("check-missing-goods", SEAFOOD_MARKET, PRODUCT_ID, "sell", "player", 1)
	_expect(missing_goods.get("reason") == "insufficient_goods", "missing goods reason")
	_expect(starting_accounts == JSON.stringify(GameSession.accounts) and starting_cargo == JSON.stringify(GameSession.inventories) and starting_ledger == GameSession.ledger.size() and starting_market == JSON.stringify(GameSession.market_states), "failed sale leaves every state unchanged")

func _check_region_price_difference() -> void:
	_fresh("seoul")
	var seoul := GameSession.get_quote("seoul_fresh", PRODUCT_ID, "buy", 1)
	var incheon := GameSession.get_quote(SEAFOOD_MARKET, PRODUCT_ID, "buy", 1)
	_expect(seoul["total"] > incheon["total"], "regional product coefficients change purchase prices")

func _check_same_market_resale() -> void:
	_fresh("incheon")
	var starting_cash: int = GameSession.accounts["corporate"]
	var buy_result := _buy("check-roundtrip-buy")
	_expect(buy_result["ok"], "roundtrip purchase succeeds")
	var sell_result: Dictionary = GameSession.execute_trade("check-roundtrip-sell", SEAFOOD_MARKET, PRODUCT_ID, "sell", "player", 1)
	_expect(sell_result["ok"], "roundtrip sale succeeds")
	_expect(GameSession.accounts["corporate"] < starting_cash, "instant same-market resale cannot profit")
	_expect(GameSession.estimate_realized_profit("player", PRODUCT_ID) < 0, "realized return includes acquisition cost")

func _check_split_order_equivalence() -> void:
	_fresh("incheon")
	var bulk := GameSession.execute_trade("check-bulk", SEAFOOD_MARKET, PRODUCT_ID, "buy", "player", 3)
	_expect(bulk["ok"], "bulk purchase succeeds")
	var bulk_cash: int = GameSession.accounts["corporate"]
	var bulk_stock := GameSession.get_market_stock(SEAFOOD_MARKET, PRODUCT_ID)
	_fresh("incheon")
	var split_total := 0
	for index in 3:
		var split := GameSession.execute_trade("check-split-%d" % index, SEAFOOD_MARKET, PRODUCT_ID, "buy", "player", 1)
		_expect(split["ok"], "split purchase succeeds")
		split_total += int(split["total"])
	_expect(GameSession.accounts["corporate"] == bulk_cash, "split and bulk purchases spend the same account amount")
	_expect(GameSession.get_market_stock(SEAFOOD_MARKET, PRODUCT_ID) == bulk_stock, "split and bulk purchases leave equal stock")
	_expect(split_total == 1000000 - bulk_cash, "split and bulk order totals match")

func _check_duplicate_confirmation() -> void:
	_fresh("incheon")
	var result := _buy("check-once")
	_expect(result["ok"], "first confirmation succeeds")
	var after_first := JSON.stringify(GameSession._make_payload())
	var duplicate := _buy("check-once")
	_expect(duplicate.get("reason") == "duplicate_order", "reused order id rejected")
	_expect(after_first == JSON.stringify(GameSession._make_payload()), "duplicate confirmation changes nothing")

func _check_finance_account_separation() -> void:
	_fresh("seoul")
	_expect(GameSession.accounts["personal"] == 100000 and GameSession.accounts["corporate"] == 1000000, "starting accounts use design values")
	var contribution := GameSession.record_finance_operation("contribute", 10000, "finance-contribution")
	_expect(contribution["ok"], "personal contribution succeeds")
	_expect(GameSession.accounts["personal"] == 90000 and GameSession.accounts["corporate"] == 1010000, "contribution keeps accounts separate")
	var duplicate := JSON.stringify(GameSession._make_payload())
	_expect(GameSession.record_finance_operation("contribute", 10000, "finance-contribution").get("reason") == "duplicate_order", "finance duplicate rejected")
	_expect(duplicate == JSON.stringify(GameSession._make_payload()), "duplicate contribution has no effect")
	_expect(GameSession.record_finance_operation("return_contribution", 100000, "finance-return")["ok"], "capital return succeeds with reserve")
	_expect(GameSession.accounts["corporate"] == 910000 and GameSession.accounts["personal"] == 190000, "capital return credits correct accounts")
	var reserved := JSON.stringify(GameSession._make_payload())
	_expect(not GameSession.record_finance_operation("return_contribution", 800000, "finance-reserve")["ok"], "return cannot spend fixed cost reserve")
	_expect(reserved == JSON.stringify(GameSession._make_payload()), "reserve failure changes no state")

func _check_save_restore_and_backup() -> void:
	_fresh("incheon")
	_expect(_buy("check-save-one")["ok"], "save fixture purchase")
	_expect(GameSession.save_game(), "write isolated phase 2 save")
	var saved: Dictionary = GameSession._make_payload().duplicate(true)
	GameSession.accounts["corporate"] = -1
	_expect(GameSession.load_game(), "load isolated phase 2 save")
	var restored: Dictionary = GameSession._make_payload()
	_expect(_same_state(saved, restored), "account, cargo, market, and ledger restore")
	_expect(_buy("check-save-two")["ok"], "create previous valid backup")
	var backup_snapshot := JSON.stringify(GameSession._make_payload())
	var broken := FileAccess.open(GameSession.save_path, FileAccess.WRITE)
	broken.store_string("broken json")
	broken.close()
	_expect(GameSession.load_game(), "corrupt primary restores backup")
	_expect(backup_snapshot != JSON.stringify(GameSession._make_payload()), "backup holds prior committed transaction")
	var restored_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameSession.save_path))
	_expect(restored_file is Dictionary and GameSession._validate_payload(restored_file), "backup recovery restores a valid primary save")

func _check_legacy_migration() -> void:
	_fresh("seoul")
	var legacy_path := "user://phase2_checks/legacy.json"
	GameSession.save_path = legacy_path
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "world": {"region_id": "incheon", "player_position": {"x": 321.0, "y": 456.0}}, "party_ids": ["player", "staff_01"]}))
	file.close()
	_expect(GameSession.load_game(), "phase 1 save migrates to phase 2")
	_expect(GameSession.current_region == "incheon" and GameSession.player_position == Vector2(321.0, 456.0), "migration preserves phase 1 location")
	_expect(GameSession.accounts["corporate"] == 1000000 and GameSession.accounts["personal"] == 100000, "migration adds documented starting accounts")
	_expect(GameSession._validate_payload(GameSession._make_payload()), "migrated save validates")
