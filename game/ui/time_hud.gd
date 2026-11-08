## 야외·사옥의 달력, 계좌, 동행 인원과 최근 알림을 보여준다.
extends CanvasLayer

var refresh_seconds := 0.0
var settings_window: Window
var settings_file := ConfigFile.new()

## 저장 주기와 무관하게 달력과 장면 전환 직후 상태를 갱신한다.
func _process(delta: float) -> void:
	refresh_seconds += delta
	if refresh_seconds >= 0.25:
		refresh_seconds = 0.0
		_refresh()

func _ready() -> void:
	settings_file.load("user://settings.cfg")
	_apply_settings()
	var settings_button := Button.new()
	settings_button.text = "설정"
	settings_button.pressed.connect(_open_settings)
	$Panel/Rows.add_child(settings_button)
	GameSession.clock_changed.connect(_refresh)
	GameSession.state_changed.connect(_refresh)
	GameSession.state_changed.connect(_refresh_party)
	GameSession.alert_received.connect(_show_alert)
	_refresh()
	_refresh_party()

## 씬 교체 중 오토로드 신호가 해제된 HUD를 다시 호출하지 않게 한다.
func _exit_tree() -> void:
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
	$Panel/Rows/Date.text = "%s  %02d:%02d" % [GameSession.get_game_date_string(), GameSession.get_game_datetime()["hour"], GameSession.get_game_datetime()["minute"]]
	$Panel/Rows/Accounts.text = "개인 %s원 · 법인 %s원" % [_money(GameSession.accounts["personal"]), _money(GameSession.accounts["corporate"])]
	var active_vehicle: Dictionary = GameSession.vehicle_definitions.get(GameSession.active_vehicle_id, {})
	$Panel/Rows/Vehicle.text = "활성 차량 %s · 거리 비용 %s원/km" % [active_vehicle.get("name", "도보"), active_vehicle.get("cost_per_km", 0)]
	$Panel/Rows/Invoice.text = "다음 월세·급여 납부일 %s" % GameSession.get_next_invoice_date()
	$Panel/Rows/Status.text = "정지" if GameSession.get_is_clock_paused() else "진행"
	$Panel/Rows/Alert.text = str(GameSession.daily_alerts.back()) if not GameSession.daily_alerts.is_empty() else ""

func _show_alert(message: String) -> void:
	if not is_inside_tree():
		return
	$Panel/Rows/Alert.text = message

func _refresh_party() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var members := scene.get_node_or_null("UI/Party/Members")
	if members == null:
		return
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
	scale_label.text = "UI 크기"
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
