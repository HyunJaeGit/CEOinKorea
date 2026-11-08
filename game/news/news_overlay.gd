## 날짜 사건을 임시 컷씬 패널로 표시하고 확인 후 정지를 해제한다.
extends CanvasLayer

var article: Dictionary = {}

func _ready() -> void:
	GameSession.set_pause_reason("news_cutscene", true)
	$Screen/Panel/Continue.pressed.connect(_continue)

func present_article(data: Dictionary) -> void:
	article = data.duplicate(true)
	$Screen/Panel/Title.text = str(article.get("title", "뉴스"))
	$Screen/Panel/Body.text = str(article.get("body", ""))
	$Screen/Panel/Dialogue.text = str(article.get("dialogue", ""))
	var supply_factor := float(article.get("supply_factor", 1.0))
	var demand_factor := float(article.get("demand_factor", 1.0))
	var market_change := "공급 감소" if supply_factor < 1.0 else ("공급 증가" if supply_factor > 1.0 else "수요 감소" if demand_factor < 1.0 else "수요 증가" if demand_factor > 1.0 else "시장 변동")
	$Screen/Panel/Impact.text = "시장 영향  ·  %s  ·  %s  ·  %d일" % [GameSession.get_product_name(str(article.get("product_id", ""))), market_change, int(article.get("duration_days", 0))]
	$Screen/Panel/AssetNote.hide()
	$Screen/Panel/Continue.text = "계속"

func _continue() -> void:
	GameSession.acknowledge_news(str(article.get("id", "")))
	queue_free()
