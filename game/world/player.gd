## 주인공 이동과 8방향 캐릭터 시트 표시를 처리한다.
extends CharacterBody2D

signal moved_distance(distance_px: float, from_position: Vector2, to_position: Vector2)

const DIRECTION_SHEET := preload("res://assets/protagonist_8dir_sheet.png")

@export var move_speed: float = 220.0
@onready var character_sprite: Sprite2D = $Body
var click_target: Vector2
var has_click_target: bool = false
var nearest_reachable_point: Vector2
var pending_entrance: Area2D
var navigation_ready := false
var navigation_path := PackedVector2Array()
var path_index := 0
var navigation_agent: NavigationAgent2D

func _ready() -> void:
	navigation_agent = NavigationAgent2D.new()
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 8.0
	navigation_agent.radius = 18.0
	add_child(navigation_agent)
	character_sprite.texture = DIRECTION_SHEET
	character_sprite.region_enabled = true
	character_sprite.scale = Vector2(0.16, 0.16)
	character_sprite.offset = Vector2(0.0, -48.0)
	_set_facing(Vector2.DOWN)

func _physics_process(_delta: float) -> void:
	if not navigation_ready or not GameSession.pause_reasons.is_empty():
		velocity = Vector2.ZERO
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.0:
		has_click_target = false
		pending_entrance = null
		velocity = direction.normalized() * move_speed
		_set_facing(direction)
	elif has_click_target:
		while path_index < navigation_path.size() - 1 and global_position.distance_to(navigation_path[path_index]) < 0.5:
			path_index += 1
		var waypoint := navigation_path[path_index] if not navigation_path.is_empty() else click_target
		var difference := waypoint - global_position
		var arrival_distance := 38.0 if is_instance_valid(pending_entrance) else 8.0
		if global_position.distance_to(click_target) < arrival_distance:
			velocity = Vector2.ZERO
			_finish_click_move()
		else:
			velocity = difference.normalized() * move_speed
			if difference.length() < move_speed * _delta:
				velocity = difference / _delta
			_set_facing(difference)
	else:
		velocity = Vector2.ZERO
	var previous := global_position
	move_and_slide()
	var moved_px := previous.distance_to(global_position)
	if moved_px > 0.01:
		moved_distance.emit(moved_px, previous, global_position)
	# 방향키도 클릭 이동과 같은 보행 영역 안에서만 움직인다.
	var nearest := NavigationServer2D.map_get_closest_point(get_world_2d().navigation_map, global_position)
	if global_position.distance_to(nearest) > 2.0:
		global_position = previous
	if is_instance_valid(pending_entrance) and global_position.distance_to(pending_entrance.global_position) <= 85.0:
		_finish_click_move()
		return
	var arrival_radius := 38.0 if is_instance_valid(pending_entrance) else 8.0
	if has_click_target and global_position.distance_squared_to(click_target) < arrival_radius * arrival_radius:
		_finish_click_move()

signal entrance_menu_requested(entrance: Area2D)

## 클릭 이동이 끝나면 예약된 건물 상호작용 요청을 한 번 전달한다.
func _finish_click_move() -> void:
	has_click_target = false
	if is_instance_valid(pending_entrance):
		var entrance := pending_entrance
		pending_entrance = null
		if OS.is_debug_build():
			print("[BUILDING_INTERACTION] approach_reached entrance=%s player=%s distance=%.1f" % [entrance.get_meta("label"), global_position, global_position.distance_to(entrance.global_position)])
		entrance_menu_requested.emit(entrance)

## 이동 방향을 4×2 스프라이트 시트의 해당 정지 프레임으로 바꾼다.
func _set_facing(direction: Vector2) -> void:
	if direction.length_squared() < 0.001:
		return
	var x := direction.normalized().x
	var y := direction.normalized().y
	var column := 0
	var row := 0
	if y < -absf(x) * 0.414:
		if x < -0.2:
			column = 3
			row = 1
		elif x > 0.2:
			column = 1
	elif y > absf(x) * 0.414:
		if x < -0.2:
			column = 1
			row = 1
		elif x > 0.2:
			column = 3
		else:
			row = 1
	else:
		column = 2
		row = 1 if x < 0.0 else 0
	var frame_width := character_sprite.texture.get_width() / 4.0
	var frame_height := character_sprite.texture.get_height() / 2.0
	character_sprite.region_rect = Rect2(column * frame_width, row * frame_height, frame_width, frame_height)

## UI 밖의 지면 클릭 지점을 이동 목표로 설정한다.
func set_click_target(target: Vector2) -> void:
	if not navigation_ready:
		return
	var map := get_world_2d().navigation_map
	nearest_reachable_point = NavigationServer2D.map_get_closest_point(map, target)
	click_target = nearest_reachable_point
	navigation_agent.target_position = click_target
	navigation_agent.get_next_path_position()
	navigation_path = navigation_agent.get_current_navigation_path()
	path_index = 0
	has_click_target = not navigation_path.is_empty()
	pending_entrance = null

## 클릭한 건물의 입구 앞까지 걸어간 뒤 상호작용 메뉴를 열도록 예약한다.
func walk_to_entrance(entrance: Area2D) -> void:
	if not is_instance_valid(entrance):
		return
	var direction := Vector2.DOWN
	pending_entrance = entrance
	set_click_target(entrance.global_position + direction * 70.0)
	pending_entrance = entrance

## 메뉴 취소 등으로 예약된 건물 접근을 멈춘다.
func cancel_pending_interaction() -> void:
	pending_entrance = null
	has_click_target = false
	velocity = Vector2.ZERO
