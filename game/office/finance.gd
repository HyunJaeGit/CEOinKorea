## 사옥 재무 업무에서 계좌 잔액과 출자·반환·실현이익 인출을 제공한다.
extends Control

signal closed
var operation_ids: Dictionary = {}

func _ready() -> void:
	$Panel/Personal.text = "개인 잔액  ·  %s원" % _money(GameSession.accounts["personal"])
	$Panel/Corporate.text = "법인 잔액  ·  %s원" % _money(GameSession.accounts["corporate"])
	$Panel/Capital.text = "출자 원금 %s원  ·  누적 이익 %s원" % [_money(GameSession.contribution_principal), _money(GameSession.retained_realized_profit)]
	$Panel/Ledger.text = _ledger_text()
	$Panel/Amount.value_changed.connect(_refresh_preview)
	$Panel/Contribute.pressed.connect(_operate.bind("contribute"))
	$Panel/Return.pressed.connect(_operate.bind("return_contribution"))
	$Panel/WithdrawProfit.pressed.connect(_operate.bind("withdraw_profit"))
	$Panel/OfficeUpgrade.pressed.connect(_upgrade_office)
	$Panel/Hire.pressed.connect(_hire_employee)
	$Panel/TakeLoan.pressed.connect(_take_loan)
	$Panel/Role.add_item("사무·업무 겸임", 0)
	$Panel/Role.add_item("시장 조사", 1)
	$Panel/Role.add_item("사옥 업무", 2)
	$Panel/Exit.pressed.connect(func(): closed.emit())
	_reset_operation_ids()
	GameSession.state_changed.connect(_refresh)
	_refresh_preview()
	_refresh_growth()

func _refresh_preview(_value: float = 0.0) -> void:
	_reset_operation_ids()
	$Panel/Contribute.disabled = false
	$Panel/Return.disabled = false
	$Panel/WithdrawProfit.disabled = false
	$Panel/TakeLoan.disabled = int($Panel/Amount.value) > GameSession.get_general_loan_limit()
	$Panel/Contribute.text = "개인 → 법인 출자 %s원" % _money(int($Panel/Amount.value))

func _operate(kind: String) -> void:
	var result := GameSession.record_finance_operation(kind, int($Panel/Amount.value), str(operation_ids[kind]))
	$Panel/Message.text = "완료했습니다." if result["ok"] else "잔액과 출금 가능 금액을 확인해주세요."
	if result["ok"]:
		match kind:
			"contribute": $Panel/Contribute.disabled = true
			"return_contribution": $Panel/Return.disabled = true
			"withdraw_profit": $Panel/WithdrawProfit.disabled = true

func _reset_operation_ids() -> void:
	for kind in ["contribute", "return_contribution", "withdraw_profit"]:
		operation_ids[kind] = "finance-%s-%s" % [kind, Time.get_ticks_usec()]

func _refresh() -> void:
	$Panel/Personal.text = "개인 잔액  ·  %s원" % _money(GameSession.accounts["personal"])
	$Panel/Corporate.text = "법인 잔액  ·  %s원" % _money(GameSession.accounts["corporate"])
	$Panel/Capital.text = "출자 원금 %s원  ·  누적 이익 %s원" % [_money(GameSession.contribution_principal), _money(GameSession.retained_realized_profit)]
	$Panel/Ledger.text = _ledger_text()
	_refresh_growth()

func _refresh_growth() -> void:
	var tier_name: String = {"rented_base": "기본 임대", "rented_expanded": "확장 임대", "owned": "자가 사무실"}.get(GameSession.office_tier, "미확인")
	$Panel/OfficeStatus.text = "%s  ·  직원 %d/%d  ·  월 고정비 %s원" % [tier_name, GameSession.employee_states.size(), GameSession.get_employee_capacity(), _money(GameSession.get_monthly_fixed_cost_total())]
	$Panel/OfficeUpgrade.text = "임대 확장  ·  이전비 200,000원" if GameSession.office_tier == "rented_base" else "자가 사무실 구매  ·  12,000,000원" if GameSession.office_tier == "rented_expanded" else "자가 사무실 보유  ·  대출 완납 후 매각 가능"
	$Panel/OfficeUpgrade.disabled = GameSession.office_tier == "owned" or GameSession.captivity_state.get("active", false)
	var names: Array[String] = []
	for employee_id in GameSession.employee_states:
		var state: Dictionary = GameSession.employee_states[employee_id]
		names.append("직원 %d · %s" % [names.size() + 1, _role_name(str(state.get("role", "general")))])
	$Panel/StaffStatus.text = "직원  ·  %s" % (", ".join(names) if not names.is_empty() else "없음")
	$Panel/Hire.disabled = GameSession.employee_states.size() >= GameSession.get_employee_capacity() or GameSession.captivity_state.get("active", false)
	$Panel/LoanLimit.text = "대출 한도  ·  %s원" % _money(GameSession.get_general_loan_limit())
	$Panel/LoanLimit.tooltip_text = "무담보 한도와 자가 사무실 담보 한도를 합산한 뒤 기존 원금을 뺍니다. 석방 구조 채무와 별도입니다."
	$Panel/TakeLoan.disabled = GameSession.captivity_state.get("active", false) or int($Panel/Amount.value) > GameSession.get_general_loan_limit()
	var loans: VBoxContainer = $Panel/Loans
	for child in loans.get_children(): child.queue_free()
	for loan_index in GameSession.general_loans.size():
		var loan: Dictionary = GameSession.general_loans[loan_index]
		var row := HBoxContainer.new()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "대출 %d  ·  잔액 %s원  ·  미납 이자 %s원" % [loan_index + 1, _money(int(loan.get("principal", 0))), _money(int(loan.get("arrears", 0)))]
		row.add_child(info)
		var pay := Button.new()
		pay.text = "원금 상환"
		pay.disabled = int(loan.get("principal", 0)) <= 0 or GameSession.captivity_state.get("active", false)
		pay.pressed.connect(_repay_loan.bind(str(loan.get("id", ""))))
		row.add_child(pay)
		loans.add_child(row)
	if not GameSession.unpaid_invoices.is_empty() or GameSession.general_loans.any(func(item: Dictionary) -> bool: return int(item.get("arrears", 0)) > 0):
		$Panel/Message.text = "미납 비용과 이자는 추가 수수료 없이 다음 납부일로 이월됩니다."

func _upgrade_office() -> void:
	var target := "rented_expanded" if GameSession.office_tier == "rented_base" else "owned"
	var result: Dictionary = GameSession.upgrade_office(target, "office-upgrade-%s-%d" % [target, Time.get_ticks_usec()])
	$Panel/Message.text = "사무실을 확장했습니다." if result.ok else "변경할 수 없습니다. 법인 잔액과 직원 정원을 확인해주세요."
	_refresh()

func _hire_employee() -> void:
	var role: String = ["general", "research", "office"][$Panel/Role.selected]
	var result: Dictionary = GameSession.hire_employee("employee-hire-%d" % Time.get_ticks_usec(), role)
	$Panel/Message.text = "직원을 채용했습니다. 월 급여가 고정비에 추가됩니다." if result.ok else "채용할 수 없습니다. 빈자리를 확인해주세요."
	_refresh()

func _take_loan() -> void:
	var amount := int($Panel/Amount.value)
	var result: Dictionary = GameSession.take_general_loan(amount, "general-loan-%d" % Time.get_ticks_usec())
	$Panel/Message.text = "%s원을 대출받았습니다." % _money(amount) if result.ok else "대출할 수 없습니다. 한도와 금액을 확인해주세요."
	_refresh()

func _repay_loan(loan_id: String) -> void:
	var principal := 0
	for loan in GameSession.general_loans:
		if str(loan.get("id", "")) == loan_id: principal = int(loan.get("principal", 0))
	var amount := mini(principal, int($Panel/Amount.value))
	var result: Dictionary = GameSession.repay_general_loan(loan_id, amount, "general-repay-%d" % Time.get_ticks_usec())
	$Panel/Message.text = "원금을 갚았습니다." if result.ok else "상환할 수 없습니다. 법인 잔액을 확인해주세요."
	_refresh()

func _role_name(role: String) -> String:
	return {"general": "사무·업무 겸임", "research": "시장 조사", "office": "사옥 업무"}.get(role, "사무·업무 겸임")

func _ledger_text() -> String:
	var lines := "최근 내역\n"
	var start := maxi(0, GameSession.ledger.size() - 5)
	for index in range(start, GameSession.ledger.size()):
		var entry: Dictionary = GameSession.ledger[index]
		var subject := GameSession.get_product_name(str(entry.get("product_id", ""))) if entry.has("product_id") else ""
		var detail := _ledger_kind(str(entry.get("kind", "")), str(entry.get("side", "")))
		if not subject.is_empty(): detail += " · " + subject
		var amount := int(entry.get("amount", 0))
		var sign := "+" if amount > 0 else "−" if amount < 0 else ""
		lines += "%s  %s%s원\n" % [detail, sign, _money(absi(amount))]
	return lines

func _ledger_kind(kind: String, side: String) -> String:
	if kind == "trade": return "매입" if side == "buy" else "매도"
	return {
		"opening_balance": "시작 자금", "office_fixed_cost": "월 고정비", "rescue_loan_repayment": "구조 채무 상환",
		"general_loan_interest": "대출 이자", "market_research_trip": "시장 조사", "vehicle_purchase": "차량 구매",
		"vehicle_travel": "차량 운송비", "mercenary_treatment": "용병 치료", "mercenary_hire": "용병 고용",
		"rescue_loan": "석방 자금", "ransom_payment": "석방금", "contribute": "개인 출자",
		"return_contribution": "출자금 반환", "withdraw_profit": "이익 인출", "office_upgrade": "사무실 확장",
		"employee_hire": "직원 채용", "general_loan": "대출 실행", "general_loan_principal": "대출 원금 상환",
		"mahjong_reward": "작업장 수당"
	}.get(kind, "거래")

func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
