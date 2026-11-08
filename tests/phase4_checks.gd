## 차량·전투·피랍의 원자 처리와 P0 저장 호환성을 격리 저장으로 확인한다.
extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("PHASE4_FAILED: " + message)


func _run() -> void:
	if OS.get_cmdline_user_args().has("--phase4-reload"):
		_check(GameSession.accounts.has("corporate"), "phase4 save restores account state")
		_check(GameSession.captivity_state.get("active", false), "separate process restores captivity stage")
		_check(GameSession.captivity_state.get("stage", "") == "released", "separate process restores paid release cutscene")
		_check(GameSession.rescue_debts.size() == 1 and int(GameSession.rescue_debts[0].get("remaining", 0)) == 49000, "separate process restores rescue debt")
		_check(GameSession.processed_result_ids.has(str(GameSession.captivity_state.get("result_id", "")) + ":paid"), "separate process restores ransom result ID")
		_check(GameSession.get_cargo_capacity_g("staff_01") == 25000, "separate process restores the employee cargo ability")
		print("PHASE4_RESTART_%s" % ("OK" if failures == 0 else "FAILED"))
		get_tree().quit(0 if failures == 0 else 1)
		return
	GameSession.save_path = "user://phase4_checks/session.json"
	GameSession._reset_new_game_state()
	GameSession.current_region = "incheon"
	GameSession.player_position = Vector2(321.0, 456.0)
	GameSession.accounts["corporate"] = 654321
	var phase3_payload: Dictionary = GameSession._make_payload()
	phase3_payload["schema_version"] = 3
	phase3_payload["game_version"] = "phase3"
	var phase3_path := "user://phase4_checks/phase3_migration.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://phase4_checks"))
	var phase3_file := FileAccess.open(phase3_path, FileAccess.WRITE)
	_check(phase3_file != null, "phase 3 migration fixture path is available")
	if phase3_file == null:
		get_tree().quit(1)
		return
	phase3_file.store_string(JSON.stringify(phase3_payload))
	phase3_file.close()
	GameSession.save_path = phase3_path
	_check(GameSession.load_game(), "phase 3 save migrates to phase 4")
	_check(GameSession.current_region == "incheon" and GameSession.player_position == Vector2(321.0, 456.0), "phase 3 migration preserves location")
	_check(GameSession.accounts["corporate"] == 654321 and GameSession.owned_vehicle_ids.is_empty(), "phase 3 migration preserves accounts and defaults P1 assets")
	GameSession.save_path = "user://phase4_checks/session.json"
	GameSession._reset_new_game_state()
	GameSession.accounts["corporate"] = 1499999
	var blocked_purchase: Dictionary = GameSession.purchase_vehicle("small_truck", "phase4-no-cash")
	_check(not blocked_purchase.ok and blocked_purchase.reason == "insufficient_funds", "vehicle purchase rejects insufficient corporate funds")
	_check(GameSession.accounts["corporate"] == 1499999 and GameSession.owned_vehicle_ids.is_empty(), "failed vehicle purchase changes no state")
	GameSession.accounts["corporate"] = 2000000
	var purchase: Dictionary = GameSession.purchase_vehicle("small_truck", "phase4-truck")
	_check(purchase.ok and GameSession.active_vehicle_id == "small_truck", "small truck purchase and activation")
	_check(GameSession.accounts["corporate"] == 500000, "vehicle purchase charges corporate account")
	var duplicate_purchase: Dictionary = GameSession.purchase_vehicle("small_truck", "phase4-truck")
	_check(not duplicate_purchase.ok, "repeated vehicle order does not debit twice")
	var cash_before := int(GameSession.accounts["corporate"])
	var empty_vehicle_cost: Dictionary = GameSession.charge_vehicle_distance(1000.0)
	_check(empty_vehicle_cost.ok and int(empty_vehicle_cost.charged) == 0, "empty vehicle travel has no cargo cost")
	_check(GameSession.accounts["corporate"] == cash_before, "empty travel preserves corporate funds")
	GameSession.employee_states["staff_01"]["cargo_capacity_g"] = 25000
	_seed_cargo("player", 20)
	_seed_cargo("staff_01", 25)
	_seed_cargo("vehicle:small_truck", 500)
	_check(GameSession.get_cargo_capacity_g("staff_01") == 25000, "person capacity reads the saved ability value")
	_check(GameSession.get_moving_trade_cargo_weight_g() == 545000 and GameSession.get_moving_cargo_capacity_g() == 545000, "moving cargo ratio includes party and active vehicle goods")
	var full_load_cost: Dictionary = GameSession.charge_vehicle_distance(1000.0)
	_check(full_load_cost.ok and int(full_load_cost.charged) == 200, "full load charges the existing small truck rate per km")
	_check(GameSession.accounts["corporate"] == cash_before - 200, "loaded travel cost is charged to corporate account")
	GameSession.inventories["staff_01"] = {}
	GameSession.inventories["vehicle:small_truck"] = {}
	GameSession.inventory_costs["staff_01"] = {}
	GameSession.inventory_costs["vehicle:small_truck"] = {}
	_seed_cargo("player", 1)
	var fractional_cost: Dictionary = GameSession.charge_vehicle_distance(1000.0)
	_check(fractional_cost.ok and int(fractional_cost.charged) == 0, "partial load keeps sub-won travel cost: %s" % str(fractional_cost))
	var accumulated_cost: Dictionary = GameSession.charge_vehicle_distance(2000.0)
	_check(accumulated_cost.ok and int(accumulated_cost.charged) == 1, "partial load fractions accumulate before corporate debit: %s remainder=%s" % [str(accumulated_cost), str(GameSession.vehicle_cost_remainders)])
	_check(GameSession.accounts["corporate"] == cash_before - 201, "partial load charges the accumulated proportional fare once: %d" % int(GameSession.accounts["corporate"]))
	GameSession.inventories["player"] = {}
	GameSession.inventories["staff_01"] = {}
	GameSession.inventories["vehicle:small_truck"] = {}
	GameSession.inventory_costs["player"] = {}
	GameSession.inventory_costs["staff_01"] = {}
	GameSession.inventory_costs["vehicle:small_truck"] = {}

	_seed_cargo("player", 20)
	var moved: Dictionary = GameSession.transfer_goods("player", "vehicle:small_truck", "seafood", 20)
	_check(moved.ok and GameSession.get_inventory_count("vehicle:small_truck", "seafood") == 20, "person cargo moves to active vehicle")
	var cache_position := Vector2(940.0, 418.0)
	_check(GameSession.transfer_cargo_cache("vehicle:small_truck", "seafood", 5, "seoul", cache_position, true).ok, "vehicle cargo can be stored locally")
	_check(GameSession.get_cargo_cache_count("seoul", cache_position, "seafood") == 5, "local cache count is preserved")
	_check(GameSession.transfer_cargo_cache("player", "seafood", 5, "seoul", cache_position, false).ok, "local cache cargo can be recovered by a person")
	_check(GameSession.get_inventory_count("player", "seafood") == 5, "recovered cargo returns to selected owner")
	var vehicle_owner := "vehicle:small_truck"
	GameSession.inventories[vehicle_owner]["seafood"] = 500
	GameSession.inventory_costs[vehicle_owner]["seafood"] = []
	for _i in 500: GameSession.inventory_costs[vehicle_owner]["seafood"].append(1)
	GameSession.market_states["seoul_fresh:seafood"]["stock"] = 1
	var too_heavy: Dictionary = GameSession.execute_trade("phase4-too-heavy", "seoul_fresh", "seafood", "buy", vehicle_owner, 1)
	_check(not too_heavy.ok and too_heavy.reason == "capacity_exceeded", "vehicle load limit rejects overload")
	_check(GameSession.market_states["seoul_fresh:seafood"]["stock"] == 1, "failed overload leaves market stock unchanged")
	GameSession.inventories[vehicle_owner]["seafood"] = 20
	GameSession.inventory_costs[vehicle_owner]["seafood"] = []
	for _i in 20: GameSession.inventory_costs[vehicle_owner]["seafood"].append(1)

	_check(GameSession.hire_mercenary("defender", "defender_01").ok, "hire defender from corporate account")
	_check(GameSession.hire_mercenary("agile", "agile_01").ok, "hire agile mercenary")
	_check(not GameSession.hire_mercenary("basic", "extra_01").ok, "mercenary roster is limited to three")
	GameSession.mercenaries["defender_01"]["hp"] = 90
	var treatment_cash := int(GameSession.accounts["corporate"])
	var treatment: Dictionary = GameSession.treat_mercenary("defender_01")
	_check(treatment.ok and treatment.cost == 4000 and GameSession.mercenaries["defender_01"]["hp"] == 130, "mercenary treatment charges per missing HP and restores health")
	_check(int(GameSession.accounts["corporate"]) == treatment_cash - 4000, "treatment debit is posted to corporate account")
	GameSession.mercenaries["basic_01"]["hp"] = 0
	GameSession.accounts["corporate"] = 0
	var revival: Dictionary = GameSession.use_free_revival()
	_check(revival.ok and GameSession.mercenaries["basic_01"]["hp"] == 100, "initial basic mercenary can use free revival when treatment is unaffordable")
	GameSession.mercenaries["basic_01"]["hp"] = 1
	_check(GameSession.use_free_revival().reason == "already_used_today", "free revival is limited to once per game day")
	GameSession.accounts["corporate"] = 500000
	GameSession.mercenaries["basic_01"]["hp"] = 100
	GameSession.mercenary_roster = ["basic_01"]
	_check(GameSession.begin_battle("phase4-strike", "beginner_raiders", "strike-spawn").ok, "strike skill encounter starts")
	_check(GameSession.select_battle_command("skill").ok, "basic mercenary strike skill resolves")
	_check(GameSession.battle_state["enemies"][0]["hp"] == 15, "strike skill applies design damage multiplier")
	var strike_turn := int(GameSession.battle_state["turn"])
	var blocked_repeat: Dictionary = GameSession.select_battle_command("skill")
	_check(blocked_repeat.reason == "skill_unavailable" and int(GameSession.battle_state["turn"]) == strike_turn, "skill cooldown rejects repeat without advancing turn")
	GameSession.battle_state.clear()
	GameSession.mercenary_roster = ["defender_01", "basic_01", "agile_01"]
	_check(GameSession.begin_battle("phase4-priority", "beginner_raiders", "test-spawn").ok, "begin manual battle")
	_check(not GameSession.begin_battle("phase4-second", "beginner_raiders").ok, "same frame multiple encounter lock")
	var invalid_turn := int(GameSession.battle_state["turn"])
	_check(not GameSession.select_battle_command("use_item").ok, "unsupported battle command rejected")
	_check(int(GameSession.battle_state["turn"]) == invalid_turn, "invalid command consumes no turn")
	_check(GameSession.select_battle_command("skill").ok, "defender protection skill resolves")
	_check(int(GameSession.battle_state["protect_turns"]) == 1, "two-turn protection includes its activation turn")
	_check(not GameSession.select_battle_command("switch", "unknown").ok, "invalid switch target rejected")
	_check(GameSession.select_battle_command("switch", "basic_01").ok, "valid reserve mercenary can be deployed")
	_check(GameSession.battle_state["active_mercenary_id"] == "basic_01", "switch changes active battle mercenary")
	var first_enemy: Dictionary = GameSession.battle_state["enemies"][0]
	_check(int(first_enemy["hp"]) == 40, "defend/switch do not apply an attack")
	var combat_guard := 0
	while GameSession.battle_state.get("active", false) and GameSession.battle_state["enemies"][0]["hp"] > 0 and combat_guard < 12:
		GameSession.select_battle_command("attack")
		combat_guard += 1
	_check(GameSession.battle_state.get("result", "") == "victory", "manual attacks can win")
	var result_count := GameSession.processed_result_ids.size()
	_check(not GameSession._finish_battle("victory").ok, "victory result cannot settle twice")
	_check(GameSession.processed_result_ids.size() == result_count, "duplicate battle result leaves IDs unchanged")
	_check(int(GameSession.enemy_states.get("test-spawn", {}).get("defeated_until", 0)) > 0, "victory stores one-day enemy respawn cooldown")
	GameSession.battle_state.clear()

	GameSession.mercenary_roster = ["agile_01", "basic_01"]
	GameSession.mercenaries["agile_01"]["hp"] = 80
	_check(GameSession.begin_battle("phase4-escape", "beginner_raiders", "escape-spawn").ok, "escape test encounter starts")
	GameSession.rng_state = 1
	var before_escape := GameSession.get_inventory_count("player", "seafood") + GameSession.get_inventory_count(vehicle_owner, "seafood")
	var escaped: Dictionary = GameSession.select_battle_command("escape")
	_check(escaped.ok and escaped.get("result") == "escape", "escape succeeds on deterministic low roll")
	var after_escape := GameSession.get_inventory_count("player", "seafood") + GameSession.get_inventory_count(vehicle_owner, "seafood")
	_check(before_escape - after_escape == floori(float(before_escape) * 0.05), "escape removes five percent of combined cargo, rounded down")
	GameSession.battle_state.clear()

	GameSession.mercenary_roster = ["basic_01"]
	GameSession.mercenaries["basic_01"]["hp"] = 1
	GameSession.accounts["corporate"] = 1000
	GameSession.accounts["personal"] = 12345
	_seed_cargo("player", 2)
	_seed_cargo("staff_01", 3)
	_seed_cargo(vehicle_owner, 4)
	var inactive_owner := "vehicle:medium_truck"
	GameSession.inventories[inactive_owner] = {"seafood": 7}
	GameSession.inventory_costs[inactive_owner] = {"seafood": [1,1,1,1,1,1,1]}
	GameSession.owned_vehicle_ids.append("medium_truck")
	_reset_test_cargo_lots(inactive_owner)
	GameSession.mercenaries["basic_01"]["hp"] = 1
	_check(GameSession.begin_battle("phase4-defeat", "beginner_raiders", "defeat-spawn").ok, "defeat test encounter starts")
	var defeat: Dictionary = GameSession.select_battle_command("attack")
	_check(defeat.ok and defeat.get("result") == "defeat", "all mercenaries incapacitated causes defeat")
	_check(GameSession.get_inventory_count("player", "seafood") == 0 and GameSession.get_inventory_count("staff_01", "seafood") == 0 and GameSession.get_inventory_count(vehicle_owner, "seafood") == 0, "defeat loses only traveling person and active vehicle cargo")
	_check(GameSession.get_inventory_count(inactive_owner, "seafood") == 7, "inactive vehicle cargo is protected")
	_check(GameSession.captivity_state.get("requested_amount", 0) == 50000, "ransom is fixed from captured balance and minimum")
	_check(not GameSession.record_finance_operation("contribute", 100, "phase4-blocked-transfer").ok, "captivity blocks account transfer")
	_check(GameSession.accounts["personal"] == 12345 and GameSession.accounts["corporate"] == 1000, "blocked transfer keeps both accounts unchanged")
	_check(GameSession.negotiate_captivity().reason == "invalid_captivity_stage", "negotiation cannot skip company call")
	_check(GameSession.contact_company_during_captivity().ok, "company phone contact advances stage")
	var negotiation: Dictionary = GameSession.negotiate_captivity()
	_check(negotiation.ok and negotiation.amount == 50000, "initial legal grade gives no unsupported discount")
	var payment: Dictionary = GameSession.settle_captivity_payment()
	_check(payment.ok and payment.loan == 49000 and GameSession.accounts["corporate"] == 0, "shortfall is funded by release-only rescue debt")
	_check(GameSession.rescue_debts.size() == 1 and GameSession.rescue_debts[0]["installments_left"] == 3, "rescue debt is scheduled for three monthly installments")
	_check(GameSession.processed_result_ids.has("captivity:phase4-defeat:paid"), "ransom payment has stable result ID")
	_check(GameSession.save_game(), "phase4 state is saved")
	var battle_scene: PackedScene = load("res://game/combat/battle.tscn")
	var custody_scene: PackedScene = load("res://game/captivity/captivity.tscn")
	_check(battle_scene != null and custody_scene != null, "battle and captivity scenes load")
	if battle_scene != null:
		var battle_view := battle_scene.instantiate()
		add_child(battle_view)
		await get_tree().process_frame
		_check(battle_view.get_node_or_null("Card/Rows/Commands/Attack") != null, "battle command controls instantiate")
		battle_view.queue_free()
	if custody_scene != null:
		var custody_view := custody_scene.instantiate()
		add_child(custody_view)
		await get_tree().process_frame
		_check(custody_view.get_node_or_null("Card/Rows/Action") != null, "captivity workflow controls instantiate")
		custody_view.queue_free()
	print("PHASE4_%s" % ("OK" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _seed_cargo(owner_id: String, count: int) -> void:
	GameSession.inventories[owner_id] = {"seafood": count}
	GameSession.inventory_costs[owner_id] = {"seafood": []}
	for _i in count:
		GameSession.inventory_costs[owner_id]["seafood"].append(100)


func _reset_test_cargo_lots(owner_id: String) -> void:
	GameSession.inventory_costs[owner_id] = {"seafood": [1,1,1,1,1,1,1]}
