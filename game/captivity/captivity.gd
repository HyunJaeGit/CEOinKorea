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
		$Card/Rows/Status.text = "지금은 진행할 수 없습니다. 다시 시도해주세요."
	_refresh()


func _refresh() -> void:
	if not is_node_ready() or not GameSession.captivity_state.get("active", false):
		return
	var state: Dictionary = GameSession.captivity_state
	var stage := str(state.get("stage", "call"))
	$Card/Rows/Title.text = "긴급 연락"
	$Card/Rows/Details.text = "요구액 %s원  ·  협상 후 %s원\n법인 잔액 %s원" % [_money(int(state.get("requested_amount", 0))), _money(int(state.get("final_amount", 0))), _money(int(GameSession.accounts.get("corporate", 0)))]
	match stage:
		"call":
			$Card/Rows/Status.text = "회사에 연락해 도움을 요청하세요."
			$Card/Rows/Action.text = "회사에 연락"
		"negotiation":
			$Card/Rows/Status.text = "직원에게 요구액 협상을 맡깁니다."
			$Card/Rows/Action.text = "협상 요청"
		"payment":
			var loan := maxi(0, int(state.get("final_amount", 0)) - int(GameSession.accounts.get("corporate", 0)))
			$Card/Rows/Status.text = "부족한 %s원은 석방 자금으로 충당합니다. 3개월 분할 상환." % _money(loan)
			$Card/Rows/Action.text = "석방금 지급"
		"released":
			$Card/Rows/Status.text = "석방 완료  ·  구조 자금 %s원" % _money(int(state.get("rescue_loan", 0)))
			$Card/Rows/Action.text = "사옥으로 돌아가기"


func _money(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
