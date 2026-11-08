## 사옥의 조사 지시, 보고, 전화, 회의, 기사, 재무 업무를 연결한다.
extends Control

var workflow_panel: PanelContainer
var workflow_reason := ""
var survey_region := "seoul"
var survey_companion_check: CheckBox
var survey_cargo_check: CheckBox
var survey_message: Label
var survey_employee_select: OptionButton
var survey_employee_id := "staff_01"
var survey_destination_select: OptionButton
var active_menu_object := ""

func _exit_tree() -> void:
	GameSession.set_pause_reason("office_object_menu", false)

func _ready() -> void:
	$Panel/LaptopHotspot.pressed.connect(_open_object_menu.bind("laptop"))
	$Panel/SecretaryHotspot.pressed.connect(_open_object_menu.bind("secretary"))
	$Panel/PhoneHotspot.pressed.connect(_open_object_menu.bind("phone"))
	$Panel/LaptopHotspot.mouse_entered.connect(_on_hotspot_hover.bind("laptop", true))
	$Panel/LaptopHotspot.mouse_exited.connect(_on_hotspot_hover.bind("laptop", false))
	$Panel/SecretaryHotspot.mouse_entered.connect(_on_hotspot_hover.bind("secretary", true))
	$Panel/SecretaryHotspot.mouse_exited.connect(_on_hotspot_hover.bind("secretary", false))
	$Panel/PhoneHotspot.mouse_entered.connect(_on_hotspot_hover.bind("phone", true))
	$Panel/PhoneHotspot.mouse_exited.connect(_on_hotspot_hover.bind("phone", false))
	$FinanceScreen.closed.connect(_close_finance)
	$Panel/Meeting.pressed.connect(_open_meeting)
	$Panel/Exit.pressed.connect(SceneRouter.exit_building)
	$Panel/Meeting.text = "회의 · 도착 보고 %d" % GameSession.market_reports.size()
	$Panel/Meeting.disabled = GameSession.market_reports.is_empty()
	$InteractionMenu/Rows/Close.pressed.connect(_close_object_menu)
	$NewsArchive.closed.connect(_close_archive)
	GameSession.state_changed.connect(_refresh_staff)
	GameSession.reports_changed.connect(_refresh_staff)
	GameSession.reports_changed.connect(_refresh_meeting_button)
	_refresh_staff()

func _open_finance() -> void:
	GameSession.set_pause_reason("office_finance", true)
	$Panel.hide()
	$FinanceScreen.show()

func _close_finance() -> void:
	$FinanceScreen.hide()
	GameSession.set_pause_reason("office_finance", false)
	$Panel.show()

func _open_archive() -> void:
	$Panel.hide()
	$NewsArchive.show()
	$NewsArchive.open_archive()

func _close_archive() -> void:
	$NewsArchive.hide()
	$Panel.show()

## 오브젝트 위에 포인터가 있을 때만 작고 부드러운 안내를 표시한다.
func _on_hotspot_hover(object_id: String, entered: bool) -> void:
	var highlight_paths := {
		"laptop": ^"Panel/LaptopHighlight",
		"secretary": ^"Panel/SecretaryHighlight",
		"phone": ^"Panel/PhoneHighlight",
	}
	var highlight_path: NodePath = highlight_paths.get(object_id, NodePath())
	if not highlight_path.is_empty():
		get_node(highlight_path).visible = entered
	if not entered:
		if active_menu_object.is_empty():
			$Panel/HintCard/Hint.text = "노트북 · 비서 · 전화기에 마우스를 올려보세요"
		return
	var hints := {
		"laptop": "노트북 · 조사 · 보고 · 재무",
		"secretary": "비서 · 직원 관리",
		"phone": "전화기 · 직원 연락",
	}
	$Panel/HintCard/Hint.text = str(hints.get(object_id, "오브젝트 선택"))

## 오브젝트별 메뉴를 만들고 해당 기기의 기능만 노출한다.
func _open_object_menu(object_id: String) -> void:
	GameSession.set_pause_reason("office_object_menu", true)
	active_menu_object = object_id
	$Panel/HintCard.hide()
	var title: Label = $InteractionMenu/Rows/Title
	var description: Label = $InteractionMenu/Rows/Description
	var actions: VBoxContainer = $InteractionMenu/Rows/Actions
	for child in actions.get_children():
		child.free()
	match object_id:
		"laptop":
			title.text = "노트북 업무"
			description.text = "시장 정보를 살피고 회사 운영을 관리합니다."
			_add_menu_section(actions, "시장 정보")
			_add_menu_action(actions, "시장 조사 지시", _select_survey, GameSession.employee_states.get("staff_01", {}).get("assignment", "") == "research_trip")
			_add_menu_action(actions, "뉴스 보관함", _select_archive)
			_add_menu_section(actions, "회사 운영")
			_add_menu_action(actions, "재무 · 계좌", _select_finance)
			_add_menu_action(actions, "차량 구매", _select_vehicle_shop)
		"phone":
			title.text = "전화 연결"
			description.text = "출장 중인 직원에게도 연락할 수 있습니다."
			_add_menu_action(actions, "직원에게 연락하기", _phone)
		"secretary":
			title.text = "비서 · 직원 업무"
			var state: Dictionary = GameSession.employee_states.get("staff_01", {})
			var assignment := str(state.get("assignment", "office_standby"))
			description.text = "직원 배치와 용병단을 관리합니다."
			if assignment == "office_standby":
				_add_menu_action(actions, "야외 동행으로 합류", _staff_action, GameSession.party_ids.size() >= 4)
			elif assignment == "research_trip":
				_add_menu_action(actions, "출장 취소 · 비용 반환 없음", _cancel_task)
			else:
				description.text += "\n현재 야외 동행 중입니다."
			_add_menu_action(actions, "용병 고용 · 치료", _select_mercenary_management)
	$Dimmer.show()
	$InteractionMenu.show()

## 메뉴 선택은 기존 업무 처리 함수로 전달한다.
func _add_menu_action(actions: VBoxContainer, label_text: String, callback: Callable, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = label_text
	button.disabled = disabled
	button.pressed.connect(callback)
	actions.add_child(button)


## 메뉴 기능을 업무 주제별로 묶어 한눈에 찾게 한다.
func _add_menu_section(actions: VBoxContainer, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.42, 0.56, 0.4, 1.0))
	actions.add_child(label)

func _close_object_menu() -> void:
	GameSession.set_pause_reason("office_object_menu", false)
	$InteractionMenu.hide()
	$Dimmer.hide()
	active_menu_object = ""
	$Panel/HintCard.show()

func _select_survey() -> void:
	_close_object_menu()
	_open_survey()

func _select_archive() -> void:
	_close_object_menu()
	_open_archive()

func _select_finance() -> void:
	_close_object_menu()
	_open_finance()


func _select_vehicle_shop() -> void:
	_close_object_menu()
	_open_vehicle_shop()


func _select_mercenary_management() -> void:
	_close_object_menu()
	_open_mercenary_management()


## 기획 차량의 가격·하중·속도·주행비를 표시하고 법인 구매/교체를 제공한다.
func _open_vehicle_shop() -> void:
	_open_workflow("office_vehicle_shop")
	var box := _workflow_box("차량 상점")
	box.add_child(_label("법인 계좌로 구매합니다. 선택 차량의 속도·적재량·운송비가 적용됩니다."))
	for vehicle_id in GameSession.vehicle_definitions:
		var definition: Dictionary = GameSession.vehicle_definitions[vehicle_id]
		var owned := GameSession.owned_vehicle_ids.has(vehicle_id)
		var button := Button.new()
		button.text = "%s · %s원 · %.0fkg · 속도 ×%.1f · %s원/km · %s" % [definition["name"], _money(int(definition["price"])), float(definition["capacity_g"]) / 1000.0, float(definition["speed_multiplier"]), int(definition["cost_per_km"]), "선택" if owned else "구매"]
		button.pressed.connect(_purchase_or_select_vehicle.bind(str(vehicle_id)))
		box.add_child(button)
	box.add_child(_label("현재 활성 차량: %s" % (str(GameSession.vehicle_definitions.get(GameSession.active_vehicle_id, {}).get("name", "도보")))))
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_workflow)
	box.add_child(close)


func _purchase_or_select_vehicle(vehicle_id: String) -> void:
	var result: Dictionary
	if GameSession.owned_vehicle_ids.has(vehicle_id):
		result = GameSession.select_vehicle(vehicle_id)
	else:
		result = GameSession.purchase_vehicle(vehicle_id, "vehicle-purchase-%s" % vehicle_id)
	var message := "차량 선택 완료" if result.ok and GameSession.owned_vehicle_ids.has(vehicle_id) else "차량 구매 완료"
	if not result.ok:
		message = "차량 처리 실패: %s" % _reason_text(str(result.get("reason", "unknown")))
	if workflow_panel != null and is_instance_valid(workflow_panel):
		workflow_panel.get_child(0).add_child(_label(message))


## 최대 3명 편성과 기획 치료·일일 재기 지원을 제공한다.
func _open_mercenary_management() -> void:
	_open_workflow("office_mercenary_management")
	var box := _workflow_box("용병 관리")
	box.add_child(_label("야외 동행과 별도 편성 · 최대 3명 · 전투 출전 1명"))
	for mercenary_id in GameSession.mercenary_roster:
		var mercenary: Dictionary = GameSession.mercenaries[mercenary_id]
		var definition: Dictionary = GameSession.mercenary_definitions[str(mercenary["type_id"])]
		box.add_child(_label("%s · 체력 %d/%d" % [definition["name"], mercenary["hp"], definition["max_hp"]]))
		if int(mercenary["hp"]) < int(definition["max_hp"]):
			var treat := Button.new()
			treat.text = "치료 · %s원" % _money((int(definition["max_hp"]) - int(mercenary["hp"])) * 100)
			treat.pressed.connect(_treat_mercenary.bind(str(mercenary_id)))
			box.add_child(treat)
	for type_id in GameSession.mercenary_definitions:
		var definition: Dictionary = GameSession.mercenary_definitions[type_id]
		var hire := Button.new()
		hire.text = "%s 고용 · %s원" % [definition["name"], _money(int(definition["hire_cost"]))]
		hire.disabled = GameSession.mercenary_roster.size() >= 3
		hire.pressed.connect(_hire_mercenary.bind(str(type_id)))
		box.add_child(hire)
	var revival := Button.new()
	revival.text = "초기 용병 재기 지원 · 하루 1회"
	revival.pressed.connect(_revive_basic_mercenary)
	box.add_child(revival)
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_workflow)
	box.add_child(close)


func _hire_mercenary(type_id: String) -> void:
	var result := GameSession.hire_mercenary(type_id, "mercenary-%s-%d" % [type_id, GameSession.mercenary_roster.size() + 1])
	if result.ok: call_deferred("_open_mercenary_management")
	elif workflow_panel != null and is_instance_valid(workflow_panel): workflow_panel.get_child(0).add_child(_label("고용 실패: %s" % _reason_text(str(result.get("reason", "unknown")))))


func _treat_mercenary(mercenary_id: String) -> void:
	var result := GameSession.treat_mercenary(mercenary_id)
	if result.ok: call_deferred("_open_mercenary_management")
	elif workflow_panel != null and is_instance_valid(workflow_panel): workflow_panel.get_child(0).add_child(_label("치료 실패: %s" % _reason_text(str(result.get("reason", "unknown")))))


func _revive_basic_mercenary() -> void:
	var result := GameSession.use_free_revival()
	if result.ok: call_deferred("_open_mercenary_management")
	elif workflow_panel != null and is_instance_valid(workflow_panel): workflow_panel.get_child(0).add_child(_label("재기 지원 불가: %s" % _reason_text(str(result.get("reason", "unknown")))))

func _phone() -> void:
	_close_object_menu()
	_open_workflow("office_phone")
	var box := _workflow_box("직원 연락")
	var state: Dictionary = GameSession.employee_states.get("staff_01", {})
	box.add_child(_label("직원 상태: %s\n도착한 조사 보고: %d건\n출장 중에도 이 전화로 연락할 수 있습니다." % [_assignment_name(str(state.get("assignment", "사옥 대기"))), GameSession.market_reports.size()]))
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_workflow)
	box.add_child(close)

func _staff_action() -> void:
	var result := GameSession.return_staff_to_companion("staff_01")
	if not result.ok:
		$InteractionMenu/Rows/Description.text = "합류할 수 없습니다. %s" % _reason_text(str(result.get("reason", "")))

func _cancel_task() -> void:
	var active_id := ""
	for task_id in GameSession.staff_tasks:
		if GameSession.staff_tasks[task_id].get("status") == "in_progress":
			active_id = str(task_id)
	if active_id.is_empty():
		return
	var result := GameSession.cancel_research(active_id)
	if result.ok:
		$InteractionMenu/Rows/Description.text = "출장을 취소했습니다. 비용은 반환되지 않습니다."
	else:
		$InteractionMenu/Rows/Description.text = "취소할 수 없습니다. %s" % _reason_text(str(result.get("reason", "")))

func _refresh_staff() -> void:
	if active_menu_object == "secretary" and $InteractionMenu.visible:
		call_deferred("_open_object_menu", "secretary")


## 회의 진입 버튼은 읽지 않은 보고가 없을 때 비활성화한다.
func _refresh_meeting_button() -> void:
	if not is_inside_tree():
		return
	$Panel/Meeting.text = "회의 · 도착 보고 %d" % GameSession.market_reports.size()
	$Panel/Meeting.disabled = GameSession.market_reports.is_empty()

func _assignment_name(value: String) -> String:
	match value:
		"companion": return "야외 동행"
		"research_trip": return "조사 출장"
		_: return "사옥 대기"

func _open_survey() -> void:
	_open_workflow("office_workflow")
	var box := _workflow_box("시장 조사")
	var destination := OptionButton.new()
	survey_destination_select = destination
	for region_id in GameSession.region_definitions:
		destination.add_item(str(GameSession.region_definitions[region_id].get("name", region_id)))
		destination.set_item_metadata(destination.get_item_count() - 1, str(region_id))
	destination.item_selected.connect(_set_survey_destination)
	box.add_child(destination)
	survey_region = str(destination.get_item_metadata(0)) if destination.get_item_count() > 0 else "seoul"
	survey_employee_select = OptionButton.new()
	var eligible_found := false
	for employee_id in GameSession.employee_states:
		var employee: Dictionary = GameSession.employee_states[employee_id]
		if str(employee.get("assignment", "")) == "research_trip" or str(employee.get("role", "general")) == "office": continue
		survey_employee_select.add_item("%s · %s" % [employee_id, _assignment_name(str(employee.get("assignment", "office_standby")))])
		survey_employee_select.set_item_metadata(survey_employee_select.get_item_count() - 1, str(employee_id))
		eligible_found = true
	if not eligible_found:
		survey_employee_select.add_item("배치 가능한 직원 없음")
		survey_employee_select.set_item_disabled(0, true)
	else:
		survey_employee_select.select(0)
		survey_employee_id = str(survey_employee_select.get_item_metadata(0))
	survey_employee_select.item_selected.connect(func(index: int): survey_employee_id = str(survey_employee_select.get_item_metadata(index)))
	box.add_child(survey_employee_select)
	box.add_child(_label("출장비 %s원 · 기간 %d일 · 법인 계좌" % [GameSession.office_rules.get("survey_cost", 0), GameSession.office_rules.get("survey_duration_days", 0)]))
	survey_companion_check = CheckBox.new()
	survey_companion_check.text = "동행 직원을 출장 보냅니다"
	survey_companion_check.button_pressed = not GameSession.party_ids.has(survey_employee_id)
	box.add_child(survey_companion_check)
	var transfer := Button.new()
	transfer.text = "직원 화물 옮기기"
	transfer.pressed.connect(_transfer_employee_cargo)
	box.add_child(transfer)
	survey_cargo_check = CheckBox.new()
	survey_cargo_check.text = "직원 화물이 비었음을 확인"
	box.add_child(survey_cargo_check)
	survey_message = _label("직원 화물 %skg · 주인공 화물 %skg" % [_weight_kg(survey_employee_id), _weight_kg("player")])
	box.add_child(survey_message)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var confirm := Button.new()
	confirm.text = "출장 확정"
	confirm.pressed.connect(_confirm_survey)
	buttons.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.pressed.connect(_close_workflow)
	buttons.add_child(cancel)

func _transfer_employee_cargo() -> void:
	for product_id in GameSession.inventories.get(survey_employee_id, {}):
		var quantity := GameSession.get_inventory_count(survey_employee_id, str(product_id))
		if quantity > 0:
			var result := GameSession.transfer_goods(survey_employee_id, "player", str(product_id), quantity)
			if not result.ok:
				survey_message.text = "화물을 옮길 수 없습니다. %s" % _reason_text(str(result.get("reason", "")))
				return
	survey_message.text = "화물 이전 완료 · 직원 %skg · 주인공 %skg" % [_weight_kg(survey_employee_id), _weight_kg("player")]

func _confirm_survey() -> void:
	var id := "research-%s" % Time.get_ticks_usec()
	var result := GameSession.assign_research(id, survey_region, survey_companion_check.button_pressed, survey_cargo_check.button_pressed, survey_employee_id)
	if not result.ok:
		survey_message.text = "출장 확정 실패: %s" % _reason_text(str(result.get("reason", "unknown")))
		return
	_close_workflow()
	_refresh_staff()

func _set_survey_destination(index: int) -> void:
	if survey_destination_select != null and index >= 0 and index < survey_destination_select.item_count:
		survey_region = str(survey_destination_select.get_item_metadata(index))

func _show_report(report: Dictionary) -> void:
	var text := _report_caption(report) + "\n"
	for row in report.snapshots:
		text += "%s · 재고 %s · 관측가 %s원 · 최근 %d일 추세 %+.1f%%\n" % [row.product_name, row.stock, _money(int(row.reference_price)), row.trend_days, row.trend_percent]
	var dialog := AcceptDialog.new()
	dialog.title = "고정 시점 조사 보고"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.confirmed.connect(_mark_report_read_and_close.bind(dialog, str(report.id)))
	dialog.close_requested.connect(_dispose_report_dialog.bind(dialog))
	dialog.popup_centered(Vector2i(650, 450))

## 보고의 관측값은 고정하고 현재 날짜와의 차이만 안내한다.
func _report_caption(report: Dictionary) -> String:
	var observed: int = GameSession._date_to_timestamp(str(report.observed_on))
	var age := maxi(0, floori((GameSession.game_clock.current_timestamp() - observed) / 86400.0))
	var freshness := "최신" if age <= 1 else ("주의" if age <= 3 else "오래됨")
	return "%s · 관측 %s · %s (%d일 경과) · %d개 품목" % [report.region_name, report.observed_on, freshness, age, report.snapshots.size()]

func _mark_report_read_and_close(dialog: AcceptDialog, report_id: String) -> void:
	GameSession.mark_report_read(report_id)
	dialog.queue_free()

func _dispose_report_dialog(dialog: AcceptDialog) -> void:
	dialog.queue_free()

func _open_meeting() -> void:
	_open_workflow("office_meeting")
	var box := _workflow_box("보고 회의")
	box.add_child(_label("함께 검토할 보고를 선택하세요."))
	for report in GameSession.market_reports:
		var button := Button.new()
		button.text = "%s · %s" % [report.region_name, report.observed_on]
		button.pressed.connect(_show_report.bind(report))
		box.add_child(button)
	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(_close_workflow)
	box.add_child(close)

func _open_workflow(reason: String) -> void:
	_close_workflow()
	workflow_reason = reason
	GameSession.set_pause_reason(reason, true)
	$Panel.hide()
	workflow_panel = PanelContainer.new()
	workflow_panel.name = "OfficeWorkflow"
	workflow_panel.anchor_left = 0.18
	workflow_panel.anchor_top = 0.18
	workflow_panel.anchor_right = 0.82
	workflow_panel.anchor_bottom = 0.82
	add_child(workflow_panel)

func _workflow_box(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	workflow_panel.add_child(box)
	var heading := Label.new()
	heading.text = title
	box.add_child(heading)
	return box

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _close_workflow() -> void:
	if workflow_panel != null and is_instance_valid(workflow_panel):
		workflow_panel.queue_free()
	workflow_panel = null
	if not workflow_reason.is_empty():
		GameSession.set_pause_reason(workflow_reason, false)
		workflow_reason = ""
	if is_node_ready() and $NewsArchive.visible == false and $FinanceScreen.visible == false:
		$Panel.show()

func _weight_kg(person_id: String) -> String:
	return "%.1f" % (float(GameSession.get_inventory_weight_g(person_id)) / 1000.0)

func _reason_text(reason: String) -> String:
	var messages := {
		"companion_confirmation_required":"동행 해제가 필요합니다.", "cargo_confirmation_required":"화물 이전을 확인해주세요.",
		"cargo_not_transferred":"직원 화물을 먼저 비워주세요.", "insufficient_funds":"법인 잔액이 부족합니다.",
		"employee_unavailable":"직원을 지금 배치할 수 없습니다.", "save_failed":"저장하지 못했습니다.",
		"vehicle_unavailable":"차량을 이용할 수 없습니다.", "vehicle_too_far":"차량과 너무 멀리 떨어져 있습니다.",
		"already_owned":"이미 보유한 차량입니다.", "roster_full_or_invalid":"용병 편성 한도를 확인해주세요.",
		"already_healthy":"치료가 필요하지 않습니다.", "already_used_today":"오늘은 이미 사용했습니다.",
		"not_eligible":"대상을 이용할 수 없습니다.", "captivity_locked":"현재는 진행할 수 없습니다."
	}
	return str(messages.get(reason, "요청을 처리할 수 없습니다. 조건을 확인해주세요."))

func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
