## 확인한 뉴스 기사를 보관하고 정지 토큰을 독립적으로 관리한다.
extends Control

signal closed

func _ready() -> void:
	$Panel/Close.pressed.connect(_close)
	_refresh()

func open_archive() -> void:
	GameSession.set_pause_reason("news_archive", true)
	_refresh()

func _refresh() -> void:
	for child in $Panel/Articles.get_children():
		child.queue_free()
	for article in GameSession.get_read_news():
		var button := Button.new()
		button.text = "%s · %s" % [article.get("start_date", ""), article.get("title", "뉴스")]
		button.pressed.connect(_show_article.bind(article))
		$Panel/Articles.add_child(button)

func _show_article(article: Dictionary) -> void:
	$Panel/Body.text = "%s\n\n%s" % [article.get("title", ""), article.get("body", "")]

func _close() -> void:
	GameSession.set_pause_reason("news_archive", false)
	closed.emit()
