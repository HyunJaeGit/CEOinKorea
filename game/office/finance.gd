## 사옥 재무 업무에서 계좌 잔액과 출자·반환·실현이익 인출을 제공한다.
extends Control

signal closed
var operation_ids: Dictionary = {}

func _ready() -> void:
	$Panel/Personal.text = "개인 계좌: %s원" % _money(GameSession.accounts["personal"])
	$Panel/Corporate.text = "법인 계좌: %s원" % _money(GameSession.accounts["corporate"])
	$Panel/Capital.text = "반환 가능 출자 원금: %s원 · 누적 실현이익: %s원" % [_money(GameSession.contribution_principal), _money(GameSession.retained_realized_profit)]
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
	$Panel/Message.text = "처리했습니다." if result["ok"] else "잔액·출자 원금·30일 고정비 예비금을 확인하세요."
	if result["ok"]:
		match kind:
			"contribute": $Panel/Contribute.disabled = true
			"return_contribution": $Panel/Return.disabled = true
			"withdraw_profit": $Panel/WithdrawProfit.disabled = true

func _reset_operation_ids() -> void:
	for kind in ["contribute", "return_contribution", "withdraw_profit"]:
		operation_ids[kind] = "finance-%s-%s" % [kind, Time.get_ticks_usec()]

func _refresh() -> void:
	$Panel/Personal.text = "개인 계좌: %s원" % _money(GameSession.accounts["personal"])
	$Panel/Corporate.text = "법인 계좌: %s원" % _money(GameSession.accounts["corporate"])
	$Panel/Capital.text = "반환 가능 출자 원금: %s원 · 누적 실현이익: %s원" % [_money(GameSession.contribution_principal), _money(GameSession.retained_realized_profit)]
	$Panel/Ledger.text = _ledger_text()
	_refresh_growth()

func _refresh_growth() -> void:
	var tier_name: String = {"rented_base": "기본 임대", "rented_expanded": "확장 임대", "owned": "자가 사무실"}.get(GameSession.office_tier, "미확인")
	$Panel/OfficeStatus.text = "사옥: %s · 직원 %d/%d명 · 월 고정비 %s원" % [tier_name, GameSession.employee_states.size(), GameSession.get_employee_capacity(), _money(GameSession.get_monthly_fixed_cost_total())]
	$Panel/OfficeUpgrade.text = "확장 임대 계약 · 이전비 200,000원" if GameSession.office_tier == "rented_base" else "첫 자가 사무실 구매 · 12,000,000원" if GameSession.office_tier == "rented_expanded" else "자가 사무실 보유 · 담보 매각은 연결 대출 완납 후"
	$Panel/OfficeUpgrade.disabled = GameSession.office_tier == "owned" or GameSession.captivity_state.get("active", false)
	var names: Array[String] = []
	for employee_id in GameSession.employee_states:
		var state: Dictionary = GameSession.employee_states[employee_id]
		names.append("%s(%s)" % [str(employee_id), _role_name(str(state.get("role", "general")))])
	$Panel/StaffStatus.text = "직원: %s" % ", ".join(names)
	$Panel/Hire.disabled = GameSession.employee_states.size() >= GameSession.get_employee_capacity() or GameSession.captivity_state.get("active", false)
	$Panel/LoanLimit.text = "일반 대출 가능액 %s원 · 무담보 200,000원 + 자가 사옥 구입가 40%% − 원금 · 구조 채무와 별도" % _money(GameSession.get_general_loan_limit())
	$Panel/TakeLoan.disabled = GameSession.captivity_state.get("active", false) or int($Panel/Amount.value) > GameSession.get_general_loan_limit()
	var loans: VBoxContainer = $Panel/Loans
	for child in loans.get_children(): child.queue_free()
	for loan in GameSession.general_loans:
		var row := HBoxContainer.new()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "대출 %s · 원금 %s원 · 미납 이자 %s원" % [loan.get("id", ""), _money(int(loan.get("principal", 0))), _money(int(loan.get("arrears", 0)))]
		row.add_child(info)
		var pay := Button.new()
		pay.text = "선택 금액 원금 상환"
		pay.disabled = int(loan.get("principal", 0)) <= 0 or GameSession.captivity_state.get("active", false)
		pay.pressed.connect(_repay_loan.bind(str(loan.get("id", ""))))
		row.add_child(pay)
		loans.add_child(row)
	if not GameSession.unpaid_invoices.is_empty() or GameSession.general_loans.any(func(item: Dictionary) -> bool: return int(item.get("arrears", 0)) > 0):
		$Panel/Message.text = "미납 고정비·이자는 추가 연체료 없이 이월됩니다. 영업은 계속되며 사옥·계좌에서 대응할 수 있습니다."

func _upgrade_office() -> void:
	var target := "rented_expanded" if GameSession.office_tier == "rented_base" else "owned"
	var result: Dictionary = GameSession.upgrade_office(target, "office-upgrade-%s-%d" % [target, Time.get_ticks_usec()])
	$Panel/Message.text = "사옥 계약을 변경했습니다." if result.ok else "계약 변경 실패: 법인 잔액 또는 직원 정원을 확인하세요."
	_refresh()

func _hire_employee() -> void:
	var role: String = ["general", "research", "office"][$Panel/Role.selected]
	var result: Dictionary = GameSession.hire_employee("employee-hire-%d" % Time.get_ticks_usec(), role)
	$Panel/Message.text = "직원을 채용했습니다. 월 급여 80,000원이 고정비에 추가됩니다." if result.ok else "채용 실패: 정원을 확인하세요."
	_refresh()

func _take_loan() -> void:
	var amount := int($Panel/Amount.value)
	var result: Dictionary = GameSession.take_general_loan(amount, "general-loan-%d" % Time.get_ticks_usec())
	$Panel/Message.text = "일반 대출 %s원을 실행했습니다." % _money(amount) if result.ok else "대출 실패: 가능 한도·금액을 확인하세요."
	_refresh()

func _repay_loan(loan_id: String) -> void:
	var principal := 0
	for loan in GameSession.general_loans:
		if str(loan.get("id", "")) == loan_id: principal = int(loan.get("principal", 0))
	var amount := mini(principal, int($Panel/Amount.value))
	var result: Dictionary = GameSession.repay_general_loan(loan_id, amount, "general-repay-%d" % Time.get_ticks_usec())
	$Panel/Message.text = "원금을 상환했습니다." if result.ok else "상환 실패: 법인 잔액·원금을 확인하세요."
	_refresh()

func _role_name(role: String) -> String:
	return {"general": "사무·업무 겸임", "research": "시장 조사", "office": "사옥 업무"}.get(role, "사무·업무 겸임")

func _ledger_text() -> String:
	var lines := "최근 원장\n"
	var start := maxi(0, GameSession.ledger.size() - 5)
	for index in range(start, GameSession.ledger.size()):
		var entry: Dictionary = GameSession.ledger[index]
		lines += "%s · %s · %s원\n" % [entry.get("kind", "거래"), entry.get("product_id", entry.get("account", "")), _money(int(entry.get("amount", 0)))]
	return lines

func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
