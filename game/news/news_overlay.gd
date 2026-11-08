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
	$Screen/Panel/Impact.text = "영향: %s 공급 ×%s · 수요 ×%s · %s일" % [GameSession.get_product_name(str(article.get("product_id", ""))), article.get("supply_factor", 1.0), article.get("demand_factor", 1.0), article.get("duration_days", 0)]
	$Screen/Panel/AssetNote.text = str(article.get("asset_note", "임시 텍스트 패널"))

func _continue() -> void:
	GameSession.acknowledge_news(str(article.get("id", "")))
	queue_free()
