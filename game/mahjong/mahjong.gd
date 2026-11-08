## 시청 작업장의 같은 패 연결 제거 게임 화면을 구성한다.
extends Control

const Rules = preload("res://game/mahjong/mahjong_rules.gd")
const FACES := ["🍀", "🌼", "🍊", "🐟", "🏮", "🧧", "🌿", "⭐"]
var definition: Dictionary = {}
var board: Array[int] = []
var first_selected := -1
var elapsed_seconds := 0.0
var started := false
var ended := false
var seed_value := 0
var level_defs: Dictionary = {}

func _ready() -> void:
	GameSession.set_pause_reason("mahjong", true)
	var file := FileAccess.open("res://data/mahjong_levels.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else []
	if file != null: file.close()
	if parsed is Array:
		for entry in parsed: level_defs[str(entry.id)] = entry
	$Margin/Panel/Buttons/Exit.pressed.connect(_give_up)
	$Margin/Panel/Buttons/Hint.pressed.connect(_hint)
	$Margin/Panel/Buttons/Start.pressed.connect(_start_level)
	_build_level_options()
	if GameSession.mahjong_state.get("active", false):
		var saved_region := str(GameSession.mahjong_state.get("region_id", GameSession.current_region))
		var saved_level := str(GameSession.mahjong_state.get("level_id", "beginner"))
		if saved_region == GameSession.current_region and level_defs.has(saved_level):
			definition = level_defs[saved_level]
			var saved_board: Array = GameSession.mahjong_state.get("board", [])
			board.assign(saved_board)
			seed_value = int(GameSession.mahjong_state.get("seed", 0))
			elapsed_seconds = float(GameSession.mahjong_state.get("elapsed", 0.0))
			started = true
			$Margin/Panel/Level.select(_level_index(saved_level))
			$Margin/Panel/Buttons/Start.hide()
			_build_board()
		_refresh_status("진행 중인 작업장을 이어서 합니다.")
	else:
		$Margin/Panel/Buttons/Exit.text = "돌아가기"
	_update_status()

func _process(delta: float) -> void:
	if not started or ended: return
	elapsed_seconds += delta
	_update_status()
	if elapsed_seconds >= float(definition.time_limit_seconds):
		_finish(false, "시간이 끝났습니다.")

func _build_level_options() -> void:
	var selector: OptionButton = $Margin/Panel/Level
	selector.clear()
	for level_id in ["beginner", "intermediate", "advanced"]:
		if not level_defs.has(level_id): continue
		var item: Dictionary = level_defs[level_id]
		var unlocked := GameSession.mahjong_unlocked_levels.has(level_id)
		selector.add_item("%s · %dx%d · %d초 · %d원%s" % [item.name, item.columns, item.rows, item.time_limit_seconds, item.reward, "" if unlocked else " · 잠김"])
		selector.set_item_metadata(selector.get_item_count() - 1, level_id)
		selector.set_item_disabled(selector.get_item_count() - 1, not unlocked)

func _level_index(level_id: String) -> int:
	for index in $Margin/Panel/Level.get_item_count():
		if str($Margin/Panel/Level.get_item_metadata(index)) == level_id: return index
	return 0

func _start_level() -> void:
	if started: return
	var level_id := str($Margin/Panel/Level.get_item_metadata($Margin/Panel/Level.selected))
	definition = level_defs.get(level_id, {})
	if definition.is_empty(): return
	if GameSession.mahjong_fatigue + int(definition.fatigue_cost) > 100:
		_refresh_status("피로도가 부족합니다. 게임 날짜가 바뀌면 5 회복됩니다.")
		return
	seed_value = int(Time.get_ticks_usec())
	board = Rules.generate_board(int(definition.columns), int(definition.rows), int(definition.pairs), seed_value)
	if board.is_empty():
		_refresh_status("보드 생성에 실패했습니다.")
		return
	var result: Dictionary = GameSession.start_mahjong(level_id, GameSession.current_region, board)
	if not result.ok:
		_refresh_status("시작할 수 없습니다: 피로도 또는 작업장 상태를 확인하세요.")
		return
	GameSession.mahjong_state["seed"] = seed_value
	GameSession.save_game()
	started = true
	$Margin/Panel/Buttons/Start.hide()
	$Margin/Panel/Buttons/Hint.disabled = false
	_build_board()
	_update_status()

func _build_board() -> void:
	var grid: GridContainer = $Margin/Panel/Board
	for child in grid.get_children(): child.queue_free()
	grid.columns = int(definition.get("columns", 6))
	var tile_count := int(definition.get("columns", 6)) * int(definition.get("rows", 6))
	for index in tile_count:
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(58, 50)
		tile.add_theme_font_size_override("font_size", 25)
		tile.text = "" if board[index] == 0 else FACES[board[index] - 1]
		tile.disabled = board[index] == 0
		tile.pressed.connect(_select_tile.bind(index))
		grid.add_child(tile)

func _select_tile(index: int) -> void:
	if not started or ended or board[index] <= 0: return
	if first_selected < 0:
		first_selected = index
		_set_tile_selected(index, true)
		return
	if first_selected == index:
		_set_tile_selected(index, false)
		first_selected = -1
		return
	if board[first_selected] == board[index] and Rules.can_connect(board, int(definition.columns), int(definition.rows), Vector2i(first_selected % int(definition.columns), first_selected / int(definition.columns)), Vector2i(index % int(definition.columns), index / int(definition.columns))):
		var click_time := elapsed_seconds
		board[first_selected] = 0
		board[index] = 0
		first_selected = -1
		GameSession.mahjong_state["board"] = board.duplicate()
		GameSession.mahjong_state["elapsed"] = elapsed_seconds
		GameSession.save_game()
		_build_board()
		if board.all(func(value: int) -> bool: return value == 0):
			_finish(click_time < float(definition.time_limit_seconds), "모든 패를 제거했습니다.")
		elif Rules.find_pairs(board, int(definition.columns), int(definition.rows)).is_empty():
			_relayout()
	else:
		_set_tile_selected(first_selected, false)
		first_selected = index
		_set_tile_selected(index, true)
	_update_status()

func _set_tile_selected(index: int, selected: bool) -> void:
	var grid: GridContainer = $Margin/Panel/Board
	if index >= 0 and index < grid.get_child_count():
		var tile := grid.get_child(index) as Button
		tile.modulate = Color("f5d978") if selected else Color.WHITE

func _relayout() -> void:
	var remaining: Array[int] = []
	for kind in board:
		if kind > 0: remaining.append(kind)
	board = Rules.generate_from_kinds(int(definition.columns), int(definition.rows), remaining, seed_value + int(elapsed_seconds * 1000.0))
	GameSession.mahjong_state["board"] = board.duplicate()
	GameSession.save_game()
	_build_board()
	_refresh_status("길이 막혀 남은 패를 다시 배치했습니다. 시간과 피로도는 유지됩니다.")

func _hint() -> void:
	if not started or bool(GameSession.mahjong_state.get("hint_used", false)): return
	var pairs := Rules.find_pairs(board, int(definition.columns), int(definition.rows))
	if pairs.is_empty():
		_relayout()
		return
	var pair: Dictionary = pairs[0]
	var a: Vector2i = pair.first
	var b: Vector2i = pair.second
	var first := a.y * int(definition.columns) + a.x
	var second := b.y * int(definition.columns) + b.x
	_set_tile_selected(first, true)
	_set_tile_selected(second, true)
	GameSession.mahjong_state["hint_used"] = true
	$Margin/Panel/Buttons/Hint.disabled = true
	_refresh_status("연결할 수 있는 같은 패 두 개를 표시했습니다. 힌트는 한 번만 사용할 수 있습니다.")

func _give_up() -> void:
	if started:
		_finish(false, "작업을 포기했습니다. 수당은 지급되지 않습니다.")
	else:
		SceneRouter.exit_mahjong()

func _finish(success: bool, message: String) -> void:
	if ended: return
	ended = true
	var reward_id := str(GameSession.mahjong_state.get("reward_id", ""))
	var result: Dictionary = GameSession.finish_mahjong(success, reward_id)
	$Margin/Panel/Buttons/Hint.disabled = true
	$Margin/Panel/Buttons/Exit.text = "시청으로 돌아가기"
	$Margin/Panel/Buttons/Exit.pressed.disconnect(_give_up)
	$Margin/Panel/Buttons/Exit.pressed.connect(SceneRouter.exit_mahjong)
	var payout := int(result.get("payout", 0))
	_refresh_status("%s%s · 개인 계좌 수당 %d원" % [message, " 성공" if result.ok and success else " 실패", payout])

func _update_status() -> void:
	if definition.is_empty():
		_refresh_status("지역: %s · 피로도 %d/100 · 초급부터 도전할 수 있습니다." % [GameSession.region_definitions.get(GameSession.current_region, {}).get("name", GameSession.current_region), GameSession.mahjong_fatigue])
		return
	_refresh_status("남은 시간 %.1f초 · 제거 %d/%d쌍 · 피로도 %d/100" % [maxf(0.0, float(definition.time_limit_seconds) - elapsed_seconds), int(definition.pairs) - int(board.count(0)) / 2, int(definition.pairs), GameSession.mahjong_fatigue])

func _refresh_status(message: String) -> void:
	$Margin/Panel/Status.text = message
