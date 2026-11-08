## 실제 내비게이션·입력 전환·입출구·실내 hover·거래 후 복구를 격리 검사한다.
extends Node
var failures := 0
func _ready() -> void:
	call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("P0_FAILED: " + message)
func _run() -> void:
	if OS.get_cmdline_user_args().has("--p0-reload"):
		check(GameSession.processed_order_ids.has("p0-sell"), "separate process restores trade IDs")
		check(GameSession.current_region == "seoul", "separate process restores region")
		check(GameSession.market_reports.size() == 1, "separate process restores observed report")
		check(GameSession.event_states.get("logistics_disruption_202502", {}).get("read", false), "separate process restores news archive")
		print("P0_RESTART_" + ("OK" if failures == 0 else "FAILED"))
		get_tree().quit(0 if failures == 0 else 1)
		return
	GameSession._reset_new_game_state()
	GameSession.save_path = "user://p0_checks/session.json"
	var world = load("res://game/world/korea_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 6:
		await get_tree().physics_frame
	var player = world.player
	var hud: CanvasLayer = world.get_node_or_null("TimeHUD")
	check(hud != null, "time and account HUD is attached to outdoor scene")
	if hud != null:
		var previous_party: Array[String] = GameSession.party_ids.duplicate()
		GameSession.party_ids = ["player", "staff_01", "staff_02", "staff_03"]
		hud.call("_refresh_party")
		check(world.get_node("UI/Party/Members/CompanionSlot2/Portrait").visible and world.get_node("UI/Party/Members/CompanionSlot3/Portrait").visible, "third and fourth party members receive portrait slots")
		check(world.get_node("UI/Party/Members/CompanionSlot3/Name").text == "직원 3\n동행", "party slot label follows stored employee ID")
		GameSession.party_ids = previous_party
		hud.call("_refresh_party")
	check(world.reference_route_length > 1000.0, "connected navigation exists")
	check(is_equal_approx(world.reference_route_length / player.move_speed, 22.5), "22.5 seconds and 30km reference at doubled base speed")
	player.global_position = Vector2(1320, 758)
	player.set_click_target(Vector2(450, 828))
	var elapsed := 0.0
	while player.has_click_target and elapsed < 48.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	check(elapsed > 21.0 and elapsed < 24.0, "physical one-way travel about 22.5 seconds: %.2f" % elapsed)
	print("P0_TRAVEL seconds=%.2f distance_km=30" % elapsed)
	check(player.global_position.distance_to(Vector2(450,828)) < 10.0 and GameSession.current_region == "incheon", "walk reaches Incheon and updates region")
	var bought: Dictionary = GameSession.execute_trade("p0-buy", "incheon_seafood", "seafood", "buy", "player", 1)
	check(bought.ok, "purchase after arrival")
	player.set_click_target(Vector2(1320,758))
	elapsed = 0.0
	while player.has_click_target and elapsed < 48.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	check(GameSession.current_region == "seoul", "walk returns to Seoul")
	var sale: Dictionary = GameSession.execute_trade("p0-sell", "seoul_fresh", "seafood", "sell", "player", 1)
	check(sale.ok and int(sale.get("realized_profit",0)) > 0, "profitable sale after real travel")
	player.set_click_target(Vector2(450,828))
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_right")
	check(not player.has_click_target, "arrow cancels click path")
	player.set_click_target(Vector2(700,200))
	check(player.click_target.distance_to(Vector2(700,200)) > 20.0, "water target projects onto land")
	player.cancel_pending_interaction()
	for entrance in world.entrance_nodes:
		player.global_position = entrance.global_position + Vector2(0,70)
		world._select_entrance(entrance)
		for i in 3:
			await get_tree().physics_frame
		check(world.interaction_panel.visible, "entrance menu: " + str(entrance.get_meta("label")))
		check(GameSession.pause_reasons.has("building_menu"), "building dialogue pauses clock")
		world._close_interaction_menu()
		check(not GameSession.pause_reasons.has("building_menu"), "closing releases pause")
	GameSession.update_world_state("seoul", Vector2(940,418))
	world.region_id = "seoul"
	player.global_position = Vector2(940,418)
	world.selected_entrance = world.get_node("WorldObjects/SeoulOffice/Entrance")
	world._enter_selected_building()
	for i in 6:
		await get_tree().process_frame
	var office = get_tree().current_scene
	check(office.scene_file_path.ends_with("office.tscn"), "office entry")
	check(GameSession.player_position.distance_to(Vector2(940,396)) < 2.0, "scene exit does not overwrite saved return entrance")
	check(office._report_caption({"observed_on":GameSession.get_game_date_string(), "region_name":"서울", "snapshots":[]}).contains("최신"), "current report freshness")
	check(office._report_caption({"observed_on":"2025-01-01", "region_name":"서울", "snapshots":[]}).contains("오래됨"), "old report warning without changing observations")
	for object_id in ["laptop", "secretary", "phone"]:
		var panel_name: String = {"laptop":"LaptopHighlight", "secretary":"SecretaryHighlight", "phone":"PhoneHighlight"}[object_id]
		office._on_hotspot_hover(object_id, true)
		check(office.get_node("Panel/" + panel_name).visible, "hover shows " + object_id)
		check(office.get_node("Panel/" + panel_name).mouse_filter == Control.MOUSE_FILTER_IGNORE, "highlight does not consume input")
		office._on_hotspot_hover(object_id, false)
		check(not office.get_node("Panel/" + panel_name).visible, "hover exits " + object_id)
		office._open_object_menu(object_id)
		check(office.get_node("InteractionMenu").visible and GameSession.pause_reasons.has("office_object_menu"), "object menu pauses")
		office._close_object_menu()
	SceneRouter.exit_building()
	for i in 8:
		await get_tree().physics_frame
	world = get_tree().current_scene
	check(world.player.global_position.distance_to(Vector2(940,396)) < 2.0, "office exit restores entrance")
	# 세 건물의 실제 장면 교체와 원래 출입구 복귀를 두 번씩 반복한다.
	for cycle in 2:
		for building_name in ["SeoulOffice", "SeoulHall", "IncheonHall"]:
			var entrance = world.get_node("WorldObjects/" + building_name + "/Entrance")
			var expected: Vector2 = entrance.global_position + Vector2(0,48)
			world.region_id = str(entrance.get_meta("region_id"))
			world.player.global_position = expected
			world.selected_entrance = entrance
			world._enter_selected_building()
			for i in 5:
				await get_tree().process_frame
			check(get_tree().current_scene.scene_file_path.ends_with("office.tscn" if building_name == "SeoulOffice" else "city_hall.tscn"), "repeated building entry")
			if building_name != "SeoulOffice":
				var hall = get_tree().current_scene
				check(hall.market_list != null and hall.market_list.get_child_count() == 4, "market widgets ready")
				check(hall.direction != null and hall.direction.item_count == 2, "order widgets ready")
				hall._select_market("seoul_fresh" if building_name == "SeoulHall" else "incheon_seafood")
				hall._select_product("seafood")
				check(hall.quote_label.text.contains("법인 잔액"), "city hall quote displays")
			SceneRouter.exit_building()
			for i in 8:
				await get_tree().physics_frame
			world = get_tree().current_scene
			check(world.player.global_position.distance_to(expected) < 2.0, "repeated entrance restore")
	# UI 패널에 클릭을 전달해 이동 명령으로 새지 않는지 확인한다.
	world.player.cancel_pending_interaction()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(50,250)
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	await get_tree().physics_frame
	check(not world.player.has_click_target, "party UI consumes click")
	GameSession.current_region = "seoul"
	world.region_id = "seoul"
	world.player.global_position = Vector2(940,418)
	var trip: Dictionary = GameSession.assign_research("p0-survey", "incheon", true, true)
	check(trip.ok, "research starts after trade")
	# 실제 달력 처리 진입점으로 조사 완료·뉴스·납부일까지 진행한다.
	GameSession._process(3.0 * 600.0 / 31.0)
	check(GameSession.market_reports.size() == 1, "dated report arrives")
	var seconds_to_news: float = 12.0 * 600.0 / 31.0 - GameSession.game_clock.elapsed_real_seconds + 0.01
	GameSession._process(seconds_to_news)
	check(GameSession.pending_news_ids.has("logistics_disruption_202502"), "scheduled article queues")
	GameSession.acknowledge_news("logistics_disruption_202502")
	for overlay in world.get_children():
		if overlay.scene_file_path.ends_with("news_overlay.tscn"):
			overlay.queue_free()
	GameSession._process(600.0 - GameSession.game_clock.elapsed_real_seconds + 0.01)
	var billed: int = GameSession.accounts.corporate
	GameSession._process_office_invoice(GameSession.contract_start_timestamp + 31 * 86400)
	check(GameSession.accounts.corporate == billed, "integrated cost applies once")
	GameSession.update_world_state(world.region_id, world.player.global_position)
	check(GameSession.save_game(), "save succeeds")
	var money: int = GameSession.accounts.corporate
	check(GameSession.load_game() and GameSession.accounts.corporate == money and GameSession.processed_order_ids.has("p0-sell"), "trade and location reload")
	print("P0_FLOW_" + ("OK" if failures == 0 else "FAILED") + ": failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


