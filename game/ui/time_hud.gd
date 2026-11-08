## 야외·사옥의 달력, 계좌, 동행 인원과 최근 알림을 보여준다.
extends CanvasLayer

const GAME_THEME := preload("res://game/ui/game_theme.tres")
var refresh_seconds := 0.0
var alert_seconds := 0.0
var settings_window: Window
var settings_file := ConfigFile.new()
var inventory_overlay: Control
@onready var user_menu: Control = $UserMenu
@onready var menu_overview: Label = $UserMenu/Center/Card/Margin/Rows/Overview
@onready var menu_feedback: Label = $UserMenu/Center/Card/Margin/Rows/Feedback

## 저장 주기와 무관하게 달력과 장면 전환 직후 상태를 갱신한다.
func _process(delta: float) -> void:
	refresh_seconds += delta
	if refresh_seconds >= 0.25:
		refresh_seconds = 0.0
		_refresh()
	if alert_seconds > 0.0:
		alert_seconds = maxf(0.0, alert_seconds - delta)
		if alert_seconds == 0.0:
			$Panel/Rows/Alert.hide()

func _ready() -> void:
	settings_file.load("user://settings.cfg")
	_apply_settings()
	$Panel/Rows/TopRow/Menu.pressed.connect(_open_user_menu)
	$UserMenu/Center/Card/Margin/Rows/Resume.pressed.connect(_close_user_menu)
	$UserMenu/Center/Card/Margin/Rows/Save.pressed.connect(_save_from_user_menu)
	$UserMenu/Center/Card/Margin/Rows/Settings.pressed.connect(_settings_from_user_menu)
	$UserMenu/Center/Card/Margin/Rows/Quit.pressed.connect(_confirm_quit)
	$Panel/Rows/Alert.hide()
	GameSession.clock_changed.connect(_refresh)
	GameSession.state_changed.connect(_refresh)
	GameSession.state_changed.connect(_refresh_party)
	GameSession.alert_received.connect(_show_alert)
	_refresh()
	_refresh_party()

## 씬 교체 중 오토로드 신호가 해제된 HUD를 다시 호출하지 않게 한다.
func _exit_tree() -> void:
	if inventory_overlay != null and is_instance_valid(inventory_overlay):
		GameSession.set_pause_reason("character_inventory", false)
	if user_menu.visible:
		GameSession.set_pause_reason("user_menu", false)
	GameSession.set_pause_reason("settings", false)
	if GameSession.clock_changed.is_connected(_refresh):
		GameSession.clock_changed.disconnect(_refresh)
	if GameSession.state_changed.is_connected(_refresh):
		GameSession.state_changed.disconnect(_refresh)
	if GameSession.state_changed.is_connected(_refresh_party):
		GameSession.state_changed.disconnect(_refresh_party)
	if GameSession.alert_received.is_connected(_show_alert):
		GameSession.alert_received.disconnect(_show_alert)

func _refresh() -> void:
	if not is_inside_tree():
		return
	var date_label := GameSession.get_game_date_string().replace("-", ".")
	var clock_state := "정지" if GameSession.get_is_clock_paused() else "진행"
	$Panel/Rows/TopRow/Date.text = "%s  %02d:%02d  ·  %s" % [date_label, GameSession.get_game_datetime()["hour"], GameSession.get_game_datetime()["minute"], clock_state]
	$Panel/Rows/Accounts.text = "개인 %s원  ·  법인 %s원" % [_money(GameSession.accounts["personal"]), _money(GameSession.accounts["corporate"])]

func _show_alert(message: String) -> void:
	if not is_inside_tree():
		return
	$Panel/Rows/Alert.text = message
	$Panel/Rows/Alert.show()
	alert_seconds = 5.0

func _refresh_party() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var members := scene.get_node_or_null("UI/Party/Members")
	if members == null:
		return
	var slot_names_for_input := ["PlayerSlot", "StaffSlot", "CompanionSlot2", "CompanionSlot3"]
	for slot_index in slot_names_for_input.size():
		var clickable_slot := members.get_node_or_null(slot_names_for_input[slot_index]) as Control
		if clickable_slot == null:
			continue
		clickable_slot.mouse_filter = Control.MOUSE_FILTER_STOP
		clickable_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		clickable_slot.tooltip_text = "클릭하여 인벤토리 확인"
		for descendant in clickable_slot.find_children("*", "Control", true, false):
			descendant.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not clickable_slot.has_meta("inventory_input_bound"):
			clickable_slot.gui_input.connect(_on_party_slot_input.bind(slot_index))
			clickable_slot.mouse_entered.connect(_on_party_slot_hover.bind(slot_index, true))
			clickable_slot.mouse_exited.connect(_on_party_slot_hover.bind(slot_index, false))
			clickable_slot.set_meta("inventory_input_bound", true)
	var has_player: bool = GameSession.party_ids.has("player")
	var player_slot: Control = members.get_node_or_null("PlayerSlot")
	if player_slot != null:
		player_slot.visible = has_player
	var companion_ids: Array[String] = []
	for person_id in GameSession.party_ids:
		if person_id != "player" and companion_ids.size() < 3:
			companion_ids.append(person_id)
	var slot_names := ["StaffSlot", "CompanionSlot2", "CompanionSlot3"]
	for index in slot_names.size():
		var slot := members.get_node_or_null(slot_names[index]) as HBoxContainer
		if slot == null:
			continue
		var portrait := slot.get_node("Portrait") as Control
		var name_label := slot.get_node("Name") as Label
		if index < companion_ids.size():
			portrait.show()
			name_label.custom_minimum_size.x = 70.0
			name_label.text = _companion_slot_text(companion_ids[index])
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			portrait.hide()
			name_label.custom_minimum_size.x = 122.0
			name_label.text = "빈 슬롯"
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## 초상 슬롯 입력은 현재 동행 인물의 개별 인벤토리를 연다.
func _on_party_slot_input(event: InputEvent, slot_index: int) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if slot_index < 0 or slot_index >= GameSession.party_ids.size():
		return
	get_viewport().set_input_as_handled()
	_open_character_inventory(GameSession.party_ids[slot_index])


## 마우스가 올라온 초상 슬롯에 부드러운 강조를 표시한다.
func _on_party_slot_hover(slot_index: int, hovered: bool) -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var slot_names := ["PlayerSlot", "StaffSlot", "CompanionSlot2", "CompanionSlot3"]
	if slot_index < 0 or slot_index >= slot_names.size():
		return
	var frame := scene.get_node_or_null("UI/Party/Members/%s/Portrait/Frame" % slot_names[slot_index]) as Control
	if frame != null:
		frame.self_modulate = Color(1.12, 1.08, 0.86, 1.0) if hovered else Color.WHITE


## 인물별 거래 화물과 적재 능력치를 모달 인벤토리에 표시한다.
func _open_character_inventory(person_id: String) -> void:
	if inventory_overlay != null and is_instance_valid(inventory_overlay):
		inventory_overlay.queue_free()
	var slot_index := GameSession.party_ids.find(person_id)
	if slot_index < 0:
		return
	var person_name := "주인공" if person_id == "player" else _companion_slot_text(person_id).replace("\n동행", "")
	var capacity_g := GameSession.get_cargo_capacity_g(person_id)
	var weight_g := GameSession.get_inventory_weight_g(person_id)
	var overlay := Control.new()
	overlay.name = "InventoryOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	inventory_overlay = overlay
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.06, 0.08, 0.10, 0.72)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(560, 410)
	card.theme = GAME_THEME
	center.add_child(card)
	var margins := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margins.add_theme_constant_override(side, 20)
	card.add_child(margins)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margins.add_child(rows)
	var heading := Label.new()
	heading.name = "Title"
	var level := 1 if person_id == "player" else int(GameSession.employee_states.get(person_id, {}).get("level", 1))
	heading.text = "%s 인벤토리 · Lv.%d" % [person_name, level]
	heading.add_theme_font_size_override("font_size", 23)
	rows.add_child(heading)
	var load_label := Label.new()
	load_label.name = "Load"
	load_label.text = "적재량  %s / %s kg" % [_format_weight(weight_g), _format_weight(capacity_g)]
	rows.add_child(load_label)
	var load_bar := ProgressBar.new()
	load_bar.max_value = maxf(1.0, float(capacity_g))
	load_bar.value = minf(float(weight_g), load_bar.max_value)
	load_bar.show_percentage = false
	load_bar.custom_minimum_size.y = 18
	rows.add_child(load_bar)
	var grid := GridContainer.new()
	grid.name = "ItemGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(grid)
	var product_ids: Array = GameSession.products.keys()
	product_ids.sort()
	for product_id in product_ids:
		var item_id := str(product_id)
		grid.add_child(_inventory_item_card(person_id, item_id))
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_character_inventory)
	rows.add_child(close)
	GameSession.set_pause_reason("character_inventory", true)
	close.grab_focus()


## 상품별 보유 수량·무게·매입 단가를 한 칸에 요약한다.
func _inventory_item_card(person_id: String, product_id: String) -> Control:
	var tile := PanelContainer.new()
	tile.name = "InventoryItem_%s" % product_id
	tile.custom_minimum_size = Vector2(155, 86)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	tile.add_child(body)
	var count := GameSession.get_inventory_count(person_id, product_id)
	var product: Dictionary = GameSession.products[product_id]
	var title := Label.new()
	title.text = str(product.get("name", product_id))
	title.add_theme_font_size_override("font_size", 17)
	body.add_child(title)
	var quantity := Label.new()
	quantity.text = "%s개 · %s kg" % [_format_number(count), _format_weight(count * int(product.get("unit_weight_g", 0)))] if count > 0 else "비어 있음"
	body.add_child(quantity)
	if count > 0:
		var lots: Array = GameSession.inventory_costs.get(person_id, {}).get(product_id, [])
		var average_cost := 0
		for lot in lots:
			average_cost += int(lot)
		if not lots.is_empty():
			var average := Label.new()
			average.text = "매입 평균 %s원" % _format_number(roundi(float(average_cost) / lots.size()))
			body.add_child(average)
	return tile


## 인벤토리를 닫고 세계 시간 정지 사유를 해제한다.
func _close_character_inventory() -> void:
	if inventory_overlay != null and is_instance_valid(inventory_overlay):
		inventory_overlay.queue_free()
	inventory_overlay = null
	GameSession.set_pause_reason("character_inventory", false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.echo):
		return
	if _close_active_popup():
		get_viewport().set_input_as_handled()
		return
	if user_menu.visible:
		_close_user_menu()
	else:
		_open_user_menu()
	get_viewport().set_input_as_handled()


## Esc는 먼저 열린 창을 닫고, 다른 창이 없을 때 운영 메뉴를 연다.
func _close_active_popup() -> bool:
	if settings_window != null and is_instance_valid(settings_window) and settings_window.visible:
		_close_settings()
		return true
	if inventory_overlay != null and is_instance_valid(inventory_overlay):
		_close_character_inventory()
		return true
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var world_popup := scene.get_node_or_null("UI/InteractionMenu") as Control
	if world_popup != null and world_popup.visible and scene.has_method("_close_interaction_menu"):
		scene.call("_close_interaction_menu")
		return true
	var office_popup := scene.get_node_or_null("InteractionMenu") as Control
	if office_popup != null and office_popup.visible and scene.has_method("_close_object_menu"):
		scene.call("_close_object_menu")
		return true
	if scene.get_node_or_null("OfficeWorkflow") != null and scene.has_method("_close_workflow"):
		scene.call("_close_workflow")
		return true
	for overlay_name in ["FinanceScreen", "NewsArchive"]:
		var overlay := scene.get_node_or_null(overlay_name)
		if overlay != null and overlay is CanvasItem and overlay.visible:
			overlay.emit_signal("closed")
			return true
	return false


## 항상 필요한 날짜·계좌와 상세 상태, 저장·설정 기능을 한 메뉴에 모은다.
func _open_user_menu() -> void:
	if user_menu.visible:
		return
	menu_overview.text = _menu_overview()
	menu_feedback.text = ""
	user_menu.show()
	GameSession.set_pause_reason("user_menu", true)
	$UserMenu/Center/Card/Margin/Rows/Resume.grab_focus()


## 화면에 항상 두지 않는 차량·월 납부 정보는 운영 메뉴에서 확인한다.
func _menu_overview() -> String:
	var region: Dictionary = GameSession.region_definitions.get(GameSession.current_region, {})
	var vehicle: Dictionary = GameSession.vehicle_definitions.get(GameSession.active_vehicle_id, {})
	var vehicle_name := str(vehicle.get("name", "도보"))
	var travel_cost := "%s원/km" % _money(int(vehicle.get("cost_per_km", 0))) if not vehicle.is_empty() else "무료"
	var invoice_date := GameSession.get_next_invoice_date()
	var members := GameSession.party_ids.size()
	return "%s  ·  %s\n개인 %s원  /  법인 %s원\n이동 %s · 거리 비용 %s\n다음 월 고정비 %s · 동행 %d명" % [region.get("name", GameSession.current_region), GameSession.get_game_date_string(), _money(int(GameSession.accounts.personal)), _money(int(GameSession.accounts.corporate)), vehicle_name, travel_cost, invoice_date, members]


## 저장 서비스 결과를 화면에만 알리고 상태는 GameSession이 기록한다.
func _save_from_user_menu() -> void:
	var saved := GameSession.save_game()
	menu_feedback.text = "저장했습니다." if saved else "저장하지 못했습니다. 저장 위치를 확인해주세요."


## 설정은 저장된 운영 메뉴 정지 사유를 넘겨 받아 별도 설정 창에서 처리한다.
func _settings_from_user_menu() -> void:
	_close_user_menu()
	_open_settings()


## 종료 전 명시 확인을 받고 현재 진행을 저장한다.
func _confirm_quit() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "게임 종료"
	dialog.dialog_text = "현재 진행을 저장하고 게임을 종료할까요?"
	dialog.confirmed.connect(func():
		if GameSession.save_game():
			get_tree().quit()
		else:
			menu_feedback.text = "저장하지 못해 종료를 취소했습니다."
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## 운영 메뉴를 닫으면 정지 이유를 해제해 진행을 재개한다.
func _close_user_menu() -> void:
	user_menu.hide()
	GameSession.set_pause_reason("user_menu", false)

## 동행 명단을 초상 슬롯의 표시 이름과 맞춘다.
func _companion_slot_text(person_id: String) -> String:
	var employee_number := person_id.trim_prefix("staff_")
	if employee_number.is_empty():
		employee_number = person_id
	elif employee_number.is_valid_int():
		employee_number = str(employee_number.to_int())
	return "직원 %s\n동행" % employee_number


## 설정은 게임 저장과 별도 user://settings.cfg에 저장한다.
func _open_settings() -> void:
	if settings_window != null and is_instance_valid(settings_window):
		settings_window.popup_centered()
		return
	settings_window = Window.new()
	settings_window.title = "설정"
	settings_window.size = Vector2i(420, 270)
	settings_window.close_requested.connect(_close_settings)
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("margin_left", 20)
	rows.add_theme_constant_override("margin_top", 20)
	rows.add_theme_constant_override("margin_right", 20)
	rows.add_theme_constant_override("margin_bottom", 20)
	settings_window.add_child(rows)
	var fullscreen := CheckButton.new()
	fullscreen.text = "전체 화면"
	fullscreen.button_pressed = bool(settings_file.get_value("display", "fullscreen", false))
	fullscreen.toggled.connect(func(value: bool):
		settings_file.set_value("display", "fullscreen", value)
		_apply_settings()
		settings_file.save("user://settings.cfg")
	)
	rows.add_child(fullscreen)
	var volume_label := Label.new()
	volume_label.text = "음량"
	rows.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = float(settings_file.get_value("audio", "master_volume", 1.0))
	volume.value_changed.connect(func(value: float):
		settings_file.set_value("audio", "master_volume", value)
		_apply_settings()
		settings_file.save("user://settings.cfg")
	)
	rows.add_child(volume)
	var scale_label := Label.new()
	scale_label.text = "상태창 크기"
	rows.add_child(scale_label)
	var scale := HSlider.new()
	scale.min_value = 0.9
	scale.max_value = 1.15
	scale.step = 0.05
	scale.value = float(settings_file.get_value("display", "ui_scale", 1.0))
	scale.value_changed.connect(func(value: float):
		settings_file.set_value("display", "ui_scale", value)
		_apply_settings()
		settings_file.save("user://settings.cfg")
	)
	rows.add_child(scale)
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_settings)
	rows.add_child(close)
	add_child(settings_window)
	GameSession.set_pause_reason("settings", true)
	settings_window.popup_centered()
	settings_window.visibility_changed.connect(func():
		if not settings_window.visible: GameSession.set_pause_reason("settings", false)
	)

func _close_settings() -> void:
	if settings_window != null and is_instance_valid(settings_window): settings_window.hide()
	GameSession.set_pause_reason("settings", false)


func _apply_settings() -> void:
	var fullscreen := bool(settings_file.get_value("display", "fullscreen", false))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var bus := AudioServer.get_bus_index("Master")
	var volume := clampf(float(settings_file.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	AudioServer.set_bus_mute(bus, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))
	$Panel.scale = Vector2.ONE * clampf(float(settings_file.get_value("display", "ui_scale", 1.0)), 0.9, 1.15)

func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped


func _format_number(value: int) -> String:
	return _money(value)


func _format_weight(weight_g: int) -> String:
	return "%.1f" % (float(weight_g) / 1000.0)
