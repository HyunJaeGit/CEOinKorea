## 같은 타일의 직교 연결과 풀 수 있는 보드 생성을 담당한다.
extends RefCounted

const DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## 외곽 1칸을 포함한 BFS로 꺾임 2회 이하 경로가 있는지 확인한다.
static func can_connect(board: Array[int], columns: int, rows: int, start: Vector2i, finish: Vector2i) -> bool:
	if start == finish or not _inside(start, columns, rows) or not _inside(finish, columns, rows):
		return false
	var start_index := start.y * columns + start.x
	var finish_index := finish.y * columns + finish.x
	if board[start_index] <= 0 or board[start_index] != board[finish_index]:
		return false
	var queue: Array[Dictionary] = [{"position": start, "direction": Vector2i.ZERO, "turns": -1}]
	var head := 0
	var visited: Dictionary = {}
	while head < queue.size():
		var entry: Dictionary = queue[head]
		head += 1
		var position: Vector2i = entry["position"]
		for direction in DIRECTIONS:
			var next: Vector2i = position + direction
			if next.x < -1 or next.x > columns or next.y < -1 or next.y > rows:
				continue
			var turns := int(entry["turns"])
			if turns < 0:
				turns = 0
			elif Vector2i(entry["direction"]) != direction:
				turns += 1
			if turns > 2:
				continue
			if next == finish:
				return true
			if _inside(next, columns, rows) and board[next.y * columns + next.x] != 0:
				continue
			var key := "%d,%d,%d,%d" % [next.x, next.y, direction.x, turns]
			if visited.has(key):
				continue
			visited[key] = true
			queue.append({"position": next, "direction": direction, "turns": turns})
	return false


## 같은 종류의 서로 다른 위치에서 지금 제거 가능한 쌍을 모두 찾는다.
static func find_pairs(board: Array[int], columns: int, rows: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for first_index in board.size():
		if board[first_index] <= 0:
			continue
		var first := Vector2i(first_index % columns, first_index / columns)
		for second_index in range(first_index + 1, board.size()):
			if board[first_index] != board[second_index]:
				continue
			var second := Vector2i(second_index % columns, second_index / columns)
			if can_connect(board, columns, rows, first, second):
				result.append({"first": first, "second": second})
	return result


## 현재 상태에서 제거 가능한 쌍을 추가해 역순으로 풀리는 보드를 만든다.
static func generate_board(columns: int, rows: int, pair_count: int, seed_value: int) -> Array[int]:
	var kinds: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _index in pair_count:
		kinds.append(rng.randi_range(1, 8))
	return generate_from_kinds(columns, rows, kinds, seed_value)


## 막힘 재배치에도 남은 패 종류·개수를 보존한다.
static func generate_from_kinds(columns: int, rows: int, kinds: Array[int], seed_value: int) -> Array[int]:
	var board: Array[int] = []
	board.resize(columns * rows)
	board.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shuffled_kinds: Array[int] = []
	shuffled_kinds.assign(kinds)
	for index in range(shuffled_kinds.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value: int = shuffled_kinds[index]
		shuffled_kinds[index] = shuffled_kinds[swap_index]
		shuffled_kinds[swap_index] = value
	var pair_index := 0
	for y in rows:
		for x in range(0, columns - 1, 2):
			if pair_index >= shuffled_kinds.size(): return board
			var kind: int = shuffled_kinds[pair_index]
			board[y * columns + x] = kind
			board[y * columns + x + 1] = kind
			pair_index += 1
	return board


## 빈 두 칸을 연결하는 동일 경로 규칙을 사용한다.
static func can_connect_empty(board: Array[int], columns: int, rows: int, start: Vector2i, finish: Vector2i) -> bool:
	if start == finish:
		return false
	var queue: Array[Dictionary] = [{"position": start, "direction": Vector2i.ZERO, "turns": -1}]
	var head := 0
	var visited: Dictionary = {}
	while head < queue.size():
		var entry: Dictionary = queue[head]
		head += 1
		var position: Vector2i = entry["position"]
		for direction in DIRECTIONS:
			var next: Vector2i = position + direction
			if next.x < -1 or next.x > columns or next.y < -1 or next.y > rows:
				continue
			var turns := int(entry["turns"])
			if turns < 0:
				turns = 0
			elif Vector2i(entry["direction"]) != direction:
				turns += 1
			if turns > 2:
				continue
			if next == finish:
				return true
			if _inside(next, columns, rows) and board[next.y * columns + next.x] != 0:
				continue
			var key := "%d,%d,%d,%d" % [next.x, next.y, direction.x, turns]
			if visited.has(key):
				continue
			visited[key] = true
			queue.append({"position": next, "direction": direction, "turns": turns})
	return false


static func _inside(position: Vector2i, columns: int, rows: int) -> bool:
	return position.x >= 0 and position.x < columns and position.y >= 0 and position.y < rows
