## 국내 4지역·작업장·사옥 성장·대출·저장 변환의 최소 회귀 검사를 수행한다.
extends Node

const MahjongRules = preload("res://game/mahjong/mahjong_rules.gd")
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("PHASE5_FAILED: " + label)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--phase5-reload"):
		_check(GameSession.office_tier == "rented_expanded", "office tier restored after process restart")
		_check(GameSession.mahjong_fatigue == 20 and GameSession.mahjong_unlocked_levels.has("intermediate"), "workshop fatigue and unlock restored")
		_check(GameSession.general_loans.size() == 1 and int(GameSession.general_loans[0].principal) == 200000, "general loan restored")
		_check(GameSession.region_definitions.size() == 4, "four region definitions restored")
		print("PHASE5_RESTART_%s" % ("OK" if failures == 0 else "FAILED"))
		get_tree().quit(0 if failures == 0 else 1)
		return
	GameSession.save_path = "user://phase5_checks/session.json"
	GameSession._reset_new_game_state()
	_check(GameSession.region_definitions.size() == 4, "Seoul, Incheon, Suwon, Cheonan definitions loaded")
	_check(GameSession.get_region_markets("suwon").size() >= 2 and GameSession.get_region_markets("cheonan").size() >= 2, "Suwon and Cheonan have regional markets")
	_check(float(GameSession.products.seafood.regions.incheon) == 0.5 and float(GameSession.products.rice.regions.cheonan) == 0.7, "design price coefficients preserved")

	var board: Array[int] = MahjongRules.generate_board(6, 6, 18, 9401)
	_check(board.size() == 36 and MahjongRules.find_pairs(board, 6, 6).size() > 0, "generated beginner board starts with a legal pair")
	var path_board: Array[int] = [1, 0, 0, 0, 0, 0, 0, 0, 1]
	_check(MahjongRules.can_connect(path_board, 3, 3, Vector2i(0, 0), Vector2i(2, 2)), "matching tiles connect across a legal route")
	for blocker in [1, 2, 3, 5, 6, 7]: path_board[blocker] = 2
	_check(not MahjongRules.can_connect(path_board, 3, 3, Vector2i(0, 0), Vector2i(2, 2)), "blocking tiles prevent crossing")

	GameSession.current_region = "suwon"
	var start_workshop: Dictionary = GameSession.start_mahjong("beginner", "suwon", board)
	_check(start_workshop.ok and GameSession.get_is_clock_paused(), "workshop starts and pauses world clock")
	var reward_id := str(GameSession.mahjong_state.reward_id)
	var invalid_finish: Dictionary = GameSession.finish_mahjong(true, reward_id)
	_check(not invalid_finish.ok and invalid_finish.reason == "board_not_cleared", "cannot claim reward while tiles remain")
	GameSession.mahjong_state.board = []
	var before_personal := int(GameSession.accounts.personal)
	var finished: Dictionary = GameSession.finish_mahjong(true, reward_id)
	_check(finished.ok and int(finished.payout) == 22000, "Suwon payout multiplier is applied to personal account")
	_check(int(GameSession.accounts.personal) == before_personal + 22000 and GameSession.pause_reasons.is_empty(), "reward settles once and releases pause token")
	_check(not GameSession.finish_mahjong(true, reward_id).ok, "same workshop reward ID cannot settle twice")
	GameSession.mahjong_fatigue = 20
	GameSession._process_game_day(GameSession.game_clock.next_unprocessed_day())
	_check(GameSession.mahjong_fatigue == 15, "fatigue recovers five on each game day")

	GameSession._reset_new_game_state()
	var timed_scene: Control = load("res://game/mahjong/mahjong.tscn").instantiate()
	add_child(timed_scene)
	await get_tree().process_frame
	timed_scene.call("_start_level")
	var timed_reward_id := str(GameSession.mahjong_state.get("reward_id", ""))
	var before_timeout_cash := int(GameSession.accounts.personal)
	timed_scene.call("_process", 90.0)
	_check(not GameSession.mahjong_state.get("active", false) and GameSession.mahjong_state.get("result", "") == "failed", "real-time limit fails without advancing world date")
	_check(int(GameSession.accounts.personal) == before_timeout_cash and GameSession.processed_mahjong_rewards.has(timed_reward_id), "timeout retains fatigue and grants no payout")
	var forced_scene: Control = load("res://game/mahjong/mahjong.tscn").instantiate()
	add_child(forced_scene)
	await get_tree().process_frame
	forced_scene.call("_start_level")
	var forced_payload: Dictionary = GameSession._make_payload()
	var fatigue_before_close := GameSession.mahjong_fatigue
	GameSession._apply_payload(forced_payload)
	_check(not GameSession.mahjong_state.get("active", false) and GameSession.mahjong_state.get("result", "") == "forced_exit" and GameSession.mahjong_fatigue == fatigue_before_close, "forced close becomes failed after restart while keeping fatigue")
	timed_scene.queue_free()
	forced_scene.queue_free()

	GameSession._reset_new_game_state()
	var expansion: Dictionary = GameSession.upgrade_office("rented_expanded", "phase5-expand")
	_check(expansion.ok and GameSession.get_employee_capacity() == 4, "office lease expansion increases capacity")
	_check(GameSession.accounts.corporate == 800000 and GameSession.office_tier == "rented_expanded", "lease move-in cost debits corporate account")
	var hired: Dictionary = GameSession.hire_employee("phase5-hire", "research")
	_check(hired.ok and GameSession.employee_states.size() == 2 and GameSession.inventories.has(hired.employee_id), "hired employee receives a separate inventory and role")
	_check(GameSession.get_monthly_fixed_cost_total() == 410000, "expanded rent and both salaries form monthly fixed cost")
	var loan: Dictionary = GameSession.take_general_loan(200000, "phase5-loan")
	_check(loan.ok and GameSession.accounts.corporate == 1000000, "general loan adds funds to corporate account")
	_check(GameSession.get_general_loan_limit() == 0, "unsecured principal consumes its borrowing limit")
	var interest_date := GameSession.game_clock.anniversary_timestamp(1)
	GameSession._process_general_loan_due(interest_date)
	_check(GameSession.accounts.corporate == 998000 and GameSession.ledger.back().kind == "general_loan_interest", "monthly one-percent interest is charged once")
	var repayment: Dictionary = GameSession.repay_general_loan("phase5-loan", 100000, "phase5-repay")
	_check(repayment.ok and repayment.remaining_principal == 100000, "principal can be repaid independently")
	_check(GameSession.rescue_debts.is_empty(), "general loan remains separate from rescue debt")
	var unpaid_interest := int(GameSession.general_loans[0].get("arrears", 0))
	GameSession.accounts.corporate = 0
	GameSession._process_general_loan_due(GameSession.game_clock.anniversary_timestamp(2))
	_check(int(GameSession.general_loans[0].arrears) == unpaid_interest + 1000, "missed interest carries forward without late fee")

	GameSession.current_region = "incheon"
	GameSession.player_position = Vector2(450, 780)
	var old_payload: Dictionary = GameSession._make_payload()
	old_payload["schema_version"] = 4
	old_payload["game_version"] = "phase4"
	for key in ["office_tier", "office_purchase_price", "general_loans", "general_loan_arrears", "staff_counter", "mahjong_fatigue", "mahjong_unlocked_levels", "mahjong_state", "processed_mahjong_rewards"]:
		old_payload.erase(key)
	var dir := "user://phase5_checks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var migration_path := dir + "/phase4_save.json"
	var file := FileAccess.open(migration_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_payload))
	file.close()
	GameSession.save_path = migration_path
	_check(GameSession.load_game(), "schema 4 save migrates to schema 5")
	_check(GameSession.current_region == "incheon" and GameSession.office_tier == "rented_base", "migration preserves location and provides growth defaults")
	GameSession._reset_new_game_state()
	GameSession.upgrade_office("rented_expanded", "phase5-collateral-expansion")
	GameSession.accounts.corporate = 12800000
	var owned_upgrade: Dictionary = GameSession.upgrade_office("owned", "phase5-owned-office")
	_check(owned_upgrade.ok and GameSession.office_purchase_price == 12000000 and GameSession.get_employee_capacity() == 6, "first owned office uses design cost and capacity")
	var secured_loan: Dictionary = GameSession.take_general_loan(5000000, "phase5-secured-loan")
	_check(secured_loan.ok and not GameSession.can_sell_office(), "collateral office sale is locked while linked principal remains")
	var secured_repayment: Dictionary = GameSession.repay_general_loan("phase5-secured-loan", 5000000, "phase5-secured-payoff")
	_check(secured_repayment.ok and GameSession.can_sell_office(), "collateral office unlocks after full linked debt payoff")

	GameSession.save_path = "user://phase5_checks/session.json"
	GameSession._reset_new_game_state()
	GameSession.upgrade_office("rented_expanded", "phase5-save-expand")
	GameSession.hire_employee("phase5-save-hire", "research")
	GameSession.take_general_loan(200000, "phase5-save-loan")
	GameSession.start_mahjong("beginner", "seoul", MahjongRules.generate_board(6, 6, 18, 552))
	var active_reward_id := str(GameSession.mahjong_state.reward_id)
	GameSession.mahjong_state.board = []
	GameSession.finish_mahjong(true, active_reward_id)
	GameSession.mahjong_fatigue = 20
	_check(GameSession.save_game(), "schema 5 state saves")
	print("PHASE5_%s" % ("OK" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)



