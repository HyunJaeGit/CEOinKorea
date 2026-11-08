## 저장된 피랍 단계를 전화·협상·지급·석방 순으로 이어준다.
extends Control

func _ready() -> void:
	$Card/Rows/Action.pressed.connect(_advance)
	GameSession.state_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if GameSession.state_changed.is_connected(_refresh):
		GameSession.state_changed.disconnect(_refresh)


func _advance() -> void:
	var stage := str(GameSession.captivity_state.get("stage", ""))
	var result: Dictionary
	match stage:
		"call": result = GameSession.contact_company_during_captivity()
		"negotiation": result = GameSession.negotiate_captivity()
		"payment": result = GameSession.settle_captivity_payment()
		"released":
			SceneRouter.return_to_office_after_release()
			return
	if not result.ok:
		$Card/Rows/Status.text = "진행할 수 없습니다: %s" % result.get("reason", "확인 필요")
	_refresh()


func _refresh() -> void:
	if not is_node_ready() or not GameSession.captivity_state.get("active", false):
		return
	var state: Dictionary = GameSession.captivity_state
	var stage := str(state.get("stage", "call"))
	$Card/Rows/Title.text = "회사 비상 연락 · 피랍 대응"
	$Card/Rows/Details.text = "피랍 당시 법인 잔액 %s원\n최초 요구액 %s원 · 협상 후 %s원\n현재 법인 잔액 %s원" % [_money(int(state.get("base_corporate_balance", 0))), _money(int(state.get("requested_amount", 0))), _money(int(state.get("final_amount", 0))), _money(int(GameSession.accounts.get("corporate", 0)))]
	match stage:
		"call":
			$Card/Rows/Status.text = "회사 전화가 연결되었습니다. 담당 직원은 출장 중이어도 비상 응대할 수 있습니다."
			$Card/Rows/Action.text = "회사에 전화"
		"negotiation":
			$Card/Rows/Status.text = "직원이 법무 담당으로 요구액을 확인하고 협상합니다. 초기 겸임 직원의 할인 등급은 0입니다."
			$Card/Rows/Action.text = "직원 협상 요청"
		"payment":
			var loan := maxi(0, int(state.get("final_amount", 0)) - int(GameSession.accounts.get("corporate", 0)))
			$Card/Rows/Status.text = "부족액 %s원은 석방 전용 구조 대출로만 보충합니다. 3개월 분할 상환." % _money(loan)
			$Card/Rows/Action.text = "지급 확정"
		"released":
			$Card/Rows/Status.text = "지급 완료 · 화물 손실은 이미 한 번만 기록되었습니다. 구조 대출 %s원" % _money(int(state.get("rescue_loan", 0)))
			$Card/Rows/Action.text = "석방 컷씬 확인 · 사옥 복귀"


func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
