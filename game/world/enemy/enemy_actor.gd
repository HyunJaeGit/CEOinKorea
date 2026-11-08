## 야외 약탈단의 배회·감지·추격·접촉 상태를 처리한다.
extends CharacterBody2D

signal contact(spawn_id: String, enemy_type_id: String)

var spawn_id := ""
var enemy_type_id := "beginner_raiders"
var patrol_points: Array[Vector2] = []
var patrol_index := 0
var state := "wandering"
var detection_radius := 145.0
var move_speed := 48.0
var navigation_agent: NavigationAgent2D
var name_label: Label


func _ready() -> void:
	navigation_agent = NavigationAgent2D.new()
	navigation_agent.path_desired_distance = 8.0
	navigation_agent.target_desired_distance = 20.0
	navigation_agent.radius = 12.0
	add_child(navigation_agent)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-10, -14), Vector2(10, -14), Vector2(13, 7), Vector2(0, 14), Vector2(-13, 7)])
	body.color = Color("c66f5b")
	add_child(body)
	name_label = Label.new()
	name_label.text = "!"
	name_label.position = Vector2(-7, -38)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color("fff1cf"))
	add_child(name_label)


func configure(id: String, type_id: String, origin: Vector2, patrol: Array[Vector2]) -> void:
	spawn_id = id
	enemy_type_id = type_id
	position = origin
	patrol_points = patrol


func _physics_process(delta: float) -> void:
	if not is_instance_valid(navigation_agent) or GameSession.battle_state.get("active", false) or GameSession.captivity_state.get("active", false):
		return
	if not GameSession.pause_reasons.is_empty():
		velocity = Vector2.ZERO
		return
	var world := get_parent().get_parent()
	var player := world.get_node_or_null("WorldObjects/Player") as CharacterBody2D
	if player == null:
		return
	var respawn: Dictionary = GameSession.enemy_states.get(spawn_id, {})
	if int(respawn.get("defeated_until", 0)) > int(GameSession.game_clock.current_timestamp()):
		hide()
		return
	show()
	var enemy_safe: bool = world.is_position_safe(global_position)
	var player_safe: bool = world.is_position_safe(player.global_position)
	if enemy_safe or player_safe or GameSession.enemy_grace_seconds_remaining > 0.0:
		if state == "chasing": state = "wandering"
		velocity = Vector2.ZERO
		return
	if state == "wandering" and global_position.distance_to(player.global_position) <= detection_radius:
		state = "chasing"
		name_label.text = "!"
	if state == "chasing":
		navigation_agent.target_position = player.global_position
		if global_position.distance_to(player.global_position) <= 28.0:
			velocity = Vector2.ZERO
			contact.emit(spawn_id, enemy_type_id)
			return
	else:
		if patrol_points.is_empty():
			velocity = Vector2.ZERO
			return
		var target := patrol_points[patrol_index]
		if global_position.distance_to(target) < 12.0:
			patrol_index = (patrol_index + 1) % patrol_points.size()
			target = patrol_points[patrol_index]
		navigation_agent.target_position = target
	var next_point := navigation_agent.get_next_path_position()
	var direction := next_point - global_position
	velocity = direction.normalized() * move_speed if direction.length() > 2.0 else Vector2.ZERO
	move_and_slide()
