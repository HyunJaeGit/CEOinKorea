## 서울·인천 압축 야외 지도와 출입구 상호작용을 구성한다.
extends Node2D
const MAP_RECT := Rect2(100.0, 70.0, 1700.0, 820.0)
const INTERACTION_DISTANCE := 190.0
const ENEMY_ACTOR_SCRIPT := preload("res://game/world/enemy/enemy_actor.gd")
const ENTRANCE_PATHS: Array[NodePath] = [
	NodePath("WorldObjects/SeoulOffice/Entrance"),
	NodePath("WorldObjects/SeoulHall/Entrance"),
	NodePath("WorldObjects/IncheonHall/Entrance"),
	NodePath("WorldObjects/SuwonHall/Entrance"),
	NodePath("WorldObjects/CheonanHall/Entrance"),
]
@onready var player: CharacterBody2D = $WorldObjects/Player
@onready var status_label: Label = $UI/TopBar/Rows/Status
@onready var region_button: Button = $UI/TopBar/Rows/RegionSwitch
@onready var interaction_panel: PanelContainer = $UI/InteractionMenu
var region_id: String
var entrance_nodes: Array[Area2D] = []
var selected_entrance: Area2D
var hovered_entrance: Area2D
var hovered_region_label: Label
var reference_route_length := 0.0
var position_sync_seconds := 0.0
const SAFE_ROUTE_SECONDS := 11.25
const SAFE_ROUTE_METERS := 30000
const BRIDGE_RECT := Rect2(610, 375, 210, 85)

func _ready() -> void:
	region_id = GameSession.current_region
	_build_map_details()
	_build_walkable_map()
	_setup_map()
	player.global_position = GameSession.player_position
	for entrance_path in ENTRANCE_PATHS:
		var entrance := get_node_or_null(entrance_path) as Area2D
		if entrance == null:
			_interaction_log("entrance_missing path=%s" % entrance_path)
			continue
		entrance_nodes.append(entrance)
		entrance.input_pickable = true
		_prepare_hover_highlight(entrance)
	region_button.pressed.connect(_switch_region)
	$UI/InteractionMenu/Rows/Enter.pressed.connect(_enter_selected_building)
	$UI/InteractionMenu/Rows/Cancel.pressed.connect(_close_interaction_menu)
	player.entrance_menu_requested.connect(_open_interaction_menu)
	player.moved_distance.connect(_on_player_moved_distance)
	_build_parked_vehicle_markers()
	interaction_panel.visible = false
	call_deferred("_finish_navigation_setup")
	_update_hud()
	_interaction_log("ready region=%s entrance_count=%d" % [region_id, entrance_nodes.size()])

func _process(_delta: float) -> void:
	if interaction_panel.visible:
		_set_hovered_entrance(null)
		_set_hovered_region_label(null)
		return
	_update_building_hover()
	if is_instance_valid(player.pending_entrance):
		status_label.text = "%s에 접근 중" % player.pending_entrance.get_meta("label")
		return
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world_point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		_interaction_log("unhandled_click screen=%s world=%s in_map=%s" % [event.position, world_point, MAP_RECT.has_point(world_point)])
		if MAP_RECT.has_point(world_point):
			get_viewport().set_input_as_handled()
			var parked_vehicle := _parked_vehicle_at(world_point)
			if parked_vehicle != null:
				var recovery := GameSession.recover_parked_vehicle(str(parked_vehicle.get_meta("vehicle_id")), region_id, world_point)
				if recovery.ok:
					parked_vehicle.queue_free()
					_update_vehicle_speed()
					status_label.text = "차량을 회수했습니다. 거래 화물이 실려 있을 때만 이동 비용이 발생합니다."
				else:
					status_label.text = "차량 회수 불가: %s" % recovery.get("reason", "확인 필요")
				return
			var clicked_entrance := _entrance_at(world_point)
			if clicked_entrance != null:
				_interaction_log("building_hit=%s" % clicked_entrance.get_meta("label"))
				_select_entrance(clicked_entrance)
			else:
				_interaction_log("ground_hit; assign_click_target")
				_close_interaction_menu()
				player.set_click_target(world_point)
				interaction_panel.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		var hovered_path := str(hovered.get_path()) if hovered != null else "none"
		_interaction_log("input_click screen=%s gui_control=%s" % [event.position, hovered_path])

func _physics_process(_delta: float) -> void:
	if not player.navigation_ready:
		return
	GameSession.enemy_grace_seconds_remaining = maxf(0.0, GameSession.enemy_grace_seconds_remaining - _delta)
	position_sync_seconds += _delta
	if position_sync_seconds >= 2.0:
		position_sync_seconds = 0.0
		GameSession.update_world_state(region_id, player.global_position)
	var next_region := _closest_region_id(player.global_position)
	if next_region != region_id:
		region_id = next_region
		GameSession.update_world_state(region_id, player.global_position)
		_update_hud()

## 두 도시를 한 지도에 표시한다.
func _setup_map() -> void:
	for path in ["Map/SeoulTown", "Map/IncheonHarbor", "Map/SuwonTown", "Map/CheonanTown", "WorldObjects/SeoulOffice", "WorldObjects/SeoulHall", "WorldObjects/IncheonHall", "WorldObjects/SuwonHall", "WorldObjects/CheonanHall", "Map/RegionDetails/Seoul", "Map/RegionDetails/Incheon", "Map/RegionDetails/Suwon", "Map/RegionDetails/Cheonan"]:
		get_node(path).show()
	player.global_position = GameSession.player_position

## 지형 그림과 충돌·내비게이션이 같은 강/다리/건물 경계를 사용한다.
func _build_walkable_map() -> void:
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 18.0
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(_rect_points(MAP_RECT))
	var river: Polygon2D = $Map/River
	for points in Geometry2D.clip_polygons(river.polygon, _rect_points(BRIDGE_RECT)):
		source.add_obstruction_outline(points)
		_add_solid(points)
	for building_name in ["SeoulOffice", "SeoulHall", "IncheonHall", "SuwonHall", "CheonanHall"]:
		var building: Node2D = get_node("WorldObjects/" + building_name)
		var points := _rect_points(Rect2(building.position + Vector2(-65, -88), Vector2(130, 76)))
		source.add_obstruction_outline(points)
		_add_solid(points)
	for old_blocker in ["OfficeBlocker", "SeoulHallBlocker", "IncheonHallBlocker"]:
		get_node("Map/" + old_blocker).queue_free()
	NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	_interaction_log("baked vertices=%d polygons=%d" % [polygon.vertices.size(), polygon.get_polygon_count()])
	var region := NavigationRegion2D.new()
	region.navigation_polygon = polygon
	add_child(region)
	for path in ["Map/RegionDetails/Seoul/BridgeDeck", "Map/RegionDetails/Seoul/BridgeSurface", "Map/RegionDetails/Seoul/BridgeMarking"]:
		var line: Line2D = get_node(path)
		line.points = PackedVector2Array([Vector2(610, 417), Vector2(820, 417)])
		if not path.ends_with("BridgeMarking"):
			line.width = 85.0 if path.ends_with("BridgeDeck") else 77.0

func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func _add_solid(points: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	body.add_child(shape)
	$Map.add_child(body)

## 기준 경로 길이는 환산 30km로 유지하고 현재 기본 속도는 11.25초 목표에 맞춘다.
func _finish_navigation_setup() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var navigation_map := get_world_2d().navigation_map
	NavigationServer2D.map_set_use_async_iterations(navigation_map, false)
	NavigationServer2D.map_force_update(navigation_map)
	for _sync_frame in 4:
		if NavigationServer2D.map_get_iteration_id(navigation_map) > 0:
			break
		await get_tree().physics_frame
		NavigationServer2D.map_force_update(navigation_map)
	var map := navigation_map
	var route := NavigationServer2D.map_get_path(map, Vector2(1320, 710), Vector2(450, 780), true)
	if route.size() < 2:
		status_label.text = "안전 경로를 만들지 못했습니다. 출력 로그를 확인하세요."
		push_error("서울-인천 내비게이션 경로 생성 실패")
		return
	player.global_position = NavigationServer2D.map_get_closest_point(map, player.global_position)
	$Map/SeoulRoad.points = route
	$Map/SeoulRoadEdge.points = route
	$Map/IncheonRoad.hide()
	$Map/IncheonRoadEdge.hide()
	$Map/RegionDetails/Seoul/OfficeRoad.points = NavigationServer2D.map_get_path(map, Vector2(940, 418), Vector2(1320, 710), true)
	$Map/RegionDetails/Seoul/HallRoad.hide()
	$Map/RegionDetails/Incheon/HallRoad.hide()
	for region_key in ["suwon", "cheonan"]:
		var city_route := NavigationServer2D.map_get_path(map, Vector2(1320, 710), _region_entrance_position(region_key), true)
		if city_route.size() >= 2:
			_create_route_lines("%sRoute" % region_key.capitalize(), city_route)
		else:
			push_error("서울-%s 보행 경로 생성 실패" % region_key)
	for index in range(1, route.size()):
		reference_route_length += route[index - 1].distance_to(route[index])
	if reference_route_length > 0.0:
		player.move_speed = reference_route_length / SAFE_ROUTE_SECONDS
	_update_vehicle_speed()
	player.navigation_ready = true
	_spawn_encounter_enemies()
	GameSession.update_world_state(region_id, player.global_position)
	_interaction_log("navigation_ready length=%.2f speed=%.2f reference_km=30 seconds=11.25" % [reference_route_length, player.move_speed])
	if OS.get_cmdline_user_args().has("--phase5-map-tests"):
		var route_checks_ok := true
		for region_key in ["seoul", "incheon", "suwon", "cheonan"]:
			var city_route := NavigationServer2D.map_get_path(map, Vector2(940, 418), _region_entrance_position(region_key), true)
			if city_route.size() < 2:
				route_checks_ok = false
				printerr("PHASE5_MAP_FAILED: route to %s" % region_key)
		if route_checks_ok:
			print("PHASE5_MAP_OK: four regions have walkable paths")
		get_tree().quit(0 if route_checks_ok else 1)


## 실제 이동 프레임의 거리와 거래 화물 적재 비율로 차량 비용을 정산한다.
func _on_player_moved_distance(distance_px: float, from_position: Vector2, to_position: Vector2) -> void:
	if GameSession.active_vehicle_id.is_empty() or reference_route_length <= 0.0:
		return
	var distance_m := distance_px * float(SAFE_ROUTE_METERS) / reference_route_length
	var result: Dictionary = GameSession.charge_vehicle_distance(distance_m)
	if not result.ok:
		player.global_position = from_position
		player.velocity = Vector2.ZERO
		var parked_region := _closest_region_id(from_position)
		GameSession.park_active_vehicle(parked_region, from_position)
		_update_vehicle_speed()
		status_label.text = "차량 비용을 낼 법인 잔액이 부족해 여기서 차량을 세웠습니다. 걸어서 회수할 수 있습니다."
		_create_parked_vehicle_marker(GameSession.parked_vehicles.back())
		return
	var next_region := _closest_region_id(to_position)
	if next_region != region_id:
		region_id = next_region
		GameSession.update_world_state(region_id, to_position)
		_update_hud()


func _update_vehicle_speed() -> void:
	if reference_route_length <= 0.0:
		return
	var multiplier := float(GameSession.vehicle_definitions.get(GameSession.active_vehicle_id, {}).get("speed_multiplier", 1.0))
	player.move_speed = reference_route_length / SAFE_ROUTE_SECONDS * multiplier


func _region_map_position(region_key: String) -> Vector2:
	var position_data: Dictionary = GameSession.region_definitions.get(region_key, {}).get("map_position", {})
	return Vector2(float(position_data.get("x", 0.0)), float(position_data.get("y", 0.0)))


func _region_entrance_position(region_key: String) -> Vector2:
	for entrance in entrance_nodes:
		if str(entrance.get_meta("region_id", "")) == region_key:
			return entrance.global_position
	return _region_map_position(region_key)


func _closest_region_id(position: Vector2) -> String:
	var closest_entrance_region := ""
	var shortest_entrance := INF
	for entrance in entrance_nodes:
		var distance := position.distance_squared_to(entrance.global_position)
		if distance < shortest_entrance:
			shortest_entrance = distance
			closest_entrance_region = str(entrance.get_meta("region_id", ""))
	if shortest_entrance <= 180.0 * 180.0:
		return closest_entrance_region
	if position.x < 700.0 and position.y > 600.0:
		return "incheon"
	if position.x > 1370.0 and position.y < 690.0:
		return "suwon"
	if position.x > 850.0 and position.x < 1250.0 and position.y > 780.0:
		return "cheonan"
	return "seoul"


## 시청을 잇는 내비게이션 경로를 지도 위 임시 도로로 표시한다.
func _create_route_lines(route_name: String, route: PackedVector2Array) -> void:
	var edge := Line2D.new()
	edge.name = route_name + "Edge"
	edge.points = route
	edge.width = 30.0
	edge.default_color = Color("51483b")
	edge.z_index = 2
	$Map.add_child(edge)
	var road := Line2D.new()
	road.name = route_name
	road.points = route
	road.width = 22.0
	road.default_color = Color("b9a278")
	road.z_index = 3
	$Map.add_child(road)


func _build_parked_vehicle_markers() -> void:
	for parked in GameSession.parked_vehicles:
		_create_parked_vehicle_marker(parked)


func _create_parked_vehicle_marker(parked: Dictionary) -> void:
	if not GameSession.region_definitions.has(str(parked.get("region_id", ""))):
		return
	var marker := Node2D.new()
	marker.name = "ParkedVehicle_" + str(parked.get("vehicle_id", ""))
	marker.position = Vector2(float(parked.get("x", 0.0)), float(parked.get("y", 0.0)))
	marker.set_meta("vehicle_id", str(parked.get("vehicle_id", "")))
	marker.set_meta("region_id", str(parked.get("region_id", "")))
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-26, -10), Vector2(14, -10), Vector2(25, 0), Vector2(20, 10), Vector2(-25, 10)])
	body.color = Color("88a878")
	marker.add_child(body)
	var label := Label.new()
	label.text = "차량"
	label.position = Vector2(-18, -28)
	label.add_theme_font_size_override("font_size", 13)
	marker.add_child(label)
	$WorldObjects.add_child(marker)


func _parked_vehicle_at(world_point: Vector2) -> Node2D:
	for child in $WorldObjects.get_children():
		if child.has_meta("vehicle_id") and child.global_position.distance_to(world_point) <= 36.0 and str(child.get_meta("region_id")) == region_id:
			return child as Node2D
	return null


## 건물과 출입구 주위의 적 감지·추격을 막는다.
func is_position_safe(position: Vector2) -> bool:
	for entrance in entrance_nodes:
		if entrance.global_position.distance_to(position) <= 190.0:
			return true
	return false


## 첫 P1 위험 구간의 초급 약탈단을 지도에 하나 배치한다.
func _spawn_encounter_enemies() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--phase2-tests") or args.has("--phase3-tests") or args.has("--p0-tests") or args.has("--phase4-tests"):
		return
	var enemy: Node2D = CharacterBody2D.new()
	enemy.name = "BridgeRaider"
	enemy.set_script(ENEMY_ACTOR_SCRIPT)
	$WorldObjects.add_child(enemy)
	var patrol: Array[Vector2] = [Vector2(760.0, 475.0), Vector2(815.0, 500.0)]
	enemy.call("configure", "bridge_raiders_01", "beginner_raiders", Vector2(790.0, 480.0), patrol)
	enemy.connect("contact", Callable(self, "_on_enemy_contact"))


## 접촉한 적과 조우 ID를 저장한 뒤 수동 전투 화면으로 이동한다.
func _on_enemy_contact(spawn_id: String, enemy_type_id: String) -> void:
	if GameSession.battle_state.get("active", false) or GameSession.captivity_state.get("active", false):
		return
	var encounter_id := "encounter-%s-%d" % [spawn_id, GameSession.rng_state]
	var result: Dictionary = GameSession.begin_battle(encounter_id, enemy_type_id, spawn_id, region_id, player.global_position)
	if not result.ok:
		status_label.text = "조우를 시작할 수 없습니다: %s" % result.get("reason", "확인 필요")
		return
	GameSession.enemy_grace_seconds_remaining = 0.0
	_interaction_log("enemy_contact spawn=%s encounter=%s type=%s" % [spawn_id, encounter_id, enemy_type_id])
	SceneRouter.enter_battle()

func _entrance_at(world_point: Vector2) -> Area2D:
	var visual_hit := _building_at(world_point)
	if visual_hit != null:
		return visual_hit
	var nearest: Area2D
	var nearest_distance := INTERACTION_DISTANCE
	for entrance in entrance_nodes:
		var distance := entrance.global_position.distance_to(world_point)
		if distance <= nearest_distance:
			nearest = entrance
			nearest_distance = distance
	return nearest

## 화면에 보이는 건물 스프라이트의 실제 영역을 클릭 대상으로 판정한다.
func _building_at(world_point: Vector2) -> Area2D:
	for entrance in entrance_nodes:
		var building := entrance.get_parent().get_node_or_null("Building") as Sprite2D
		if building != null and building.get_rect().has_point(building.to_local(world_point)):
			return entrance
	return null

## 건물 hover 테두리를 준비하고 건물명은 포인터가 올라올 때만 보여준다.
func _prepare_hover_highlight(entrance: Area2D) -> void:
	var building := entrance.get_parent().get_node_or_null("Building") as Sprite2D
	if building == null:
		return
	var building_label := entrance.get_parent().get_node_or_null("Label") as Label
	if building_label != null:
		building_label.visible = false
		entrance.set_meta("hover_label", building_label)
	var highlight := Sprite2D.new()
	highlight.name = "HoverHighlight"
	highlight.texture = building.texture
	highlight.region_enabled = building.region_enabled
	highlight.region_rect = building.region_rect
	highlight.hframes = building.hframes
	highlight.vframes = building.vframes
	highlight.frame = building.frame
	highlight.centered = building.centered
	highlight.offset = building.offset
	highlight.position = building.position
	highlight.scale = building.scale * 1.12
	highlight.modulate = Color(1.0, 0.72, 0.22, 0.9)
	highlight.z_index = building.z_index - 1
	highlight.visible = false
	building.get_parent().add_child(highlight)
	entrance.set_meta("hover_highlight", highlight)

## 건물 그림 위에서 포인터와 금색 외곽 표시를 전환한다.
func _update_building_hover() -> void:
	if get_viewport().gui_get_hovered_control() != null:
		_set_hovered_entrance(null)
		_set_hovered_region_label(null)
		return
	var world_point := get_global_mouse_position()
	var building := _building_at(world_point)
	if building != null:
		_set_hovered_entrance(building)
		_set_hovered_region_label(null)
	else:
		_set_hovered_entrance(null)
		_set_hovered_region_label(_region_label_at(world_point))

func _set_hovered_entrance(entrance: Area2D) -> void:
	var previous_name := str(hovered_entrance.get_meta("label")) if is_instance_valid(hovered_entrance) else "none"
	var next_name := str(entrance.get_meta("label")) if is_instance_valid(entrance) else "none"
	if previous_name != next_name:
		_interaction_log("hover %s -> %s" % [previous_name, next_name])
	if is_instance_valid(hovered_entrance) and hovered_entrance != entrance:
		var previous: Variant = hovered_entrance.get_meta("hover_highlight", null)
		if is_instance_valid(previous):
			previous.visible = false
		var previous_label: Variant = hovered_entrance.get_meta("hover_label", null)
		if is_instance_valid(previous_label):
			previous_label.visible = false
	hovered_entrance = entrance
	if is_instance_valid(hovered_entrance):
		var highlight: Variant = hovered_entrance.get_meta("hover_highlight", null)
		if is_instance_valid(highlight):
			highlight.visible = true
		var building_label: Variant = hovered_entrance.get_meta("hover_label", null)
		if is_instance_valid(building_label):
			building_label.visible = true
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

## 지역 지형 위에서만 지역명을 표시하고 UI 입력은 가로채지 않는다.
func _region_label_at(world_point: Vector2) -> Label:
	for marker_path in ["Map/SeoulTown", "Map/IncheonHarbor", "Map/SuwonTown", "Map/CheonanTown"]:
		var marker := get_node_or_null(marker_path) as Polygon2D
		if marker == null:
			continue
		if Geometry2D.is_point_in_polygon(marker.to_local(world_point), marker.polygon):
			return marker.get_node_or_null("Label") as Label
	return null

## 현재 표시 중인 지역 라벨을 교체하거나 숨긴다.
func _set_hovered_region_label(label: Label) -> void:
	if is_instance_valid(hovered_region_label) and hovered_region_label != label:
		hovered_region_label.visible = false
	hovered_region_label = label
	if is_instance_valid(hovered_region_label):
		hovered_region_label.visible = true

func _select_entrance(entrance: Area2D) -> void:
	if not is_instance_valid(entrance):
		_interaction_log("select_rejected invalid entrance")
		return
	selected_entrance = entrance
	GameSession.set_pause_reason("building_menu", false)
	interaction_panel.visible = false
	player.walk_to_entrance(entrance)
	status_label.text = "%s에 접근 중 · 도착하면 메뉴가 열립니다" % entrance.get_meta("label")
	_interaction_log("selected=%s player=%s target=%s has_target=%s" % [entrance.get_meta("label"), player.global_position, player.click_target, player.has_click_target])

## 출입구까지 직접 걸어온 뒤 건물별 상호작용 메뉴를 표시한다.
func _open_interaction_menu(entrance: Area2D) -> void:
	if not is_instance_valid(entrance):
		_interaction_log("menu_rejected invalid entrance or wrong region")
		return
	region_id = str(entrance.get_meta("region_id"))
	GameSession.update_world_state(region_id, player.global_position)
	_update_hud()
	selected_entrance = entrance
	GameSession.set_pause_reason("building_menu", true)
	var label := str(entrance.get_meta("label"))
	$UI/InteractionMenu/Rows/Title.text = label
	$UI/InteractionMenu/Rows/Enter.text = "%s 내부 보기" % label
	interaction_panel.visible = true
	status_label.text = "%s · 메뉴에서 상호작용을 선택하세요" % label
	_interaction_log("menu_open=%s visible=%s" % [label, interaction_panel.visible])

func _enter_selected_building() -> void:
	if not is_instance_valid(selected_entrance):
		return
	GameSession.set_pause_reason("building_menu", false)
	SceneRouter.enter_building(str(selected_entrance.get_meta("kind")), region_id, selected_entrance.global_position + Vector2(0.0, 48.0))

func _close_interaction_menu() -> void:
	interaction_panel.visible = false
	GameSession.set_pause_reason("building_menu", false)
	selected_entrance = null
	player.cancel_pending_interaction()
	_update_hud()

## 지역 버튼은 반대 도시 시청까지 걸어가는 명령이다.
func _switch_region() -> void:
	var region_ids: Array = GameSession.region_definitions.keys()
	region_ids.sort()
	var current_index := region_ids.find(region_id)
	var next_region := str(region_ids[(current_index + 1) % region_ids.size()]) if not region_ids.is_empty() else "seoul"
	for entrance in entrance_nodes:
		if str(entrance.get_meta("region_id", "")) == next_region:
			_select_entrance(entrance)
			return
	status_label.text = "목적 지역의 시청 출입구를 찾지 못했습니다."

## 도시별 지형 랜드마크와 길 연결을 코드 기반 임시 도형으로 구성한다.
func _build_map_details() -> void:
	if has_node("Map/RegionDetails"):
		return
	var details := Node2D.new()
	details.name = "RegionDetails"
	$Map.add_child(details)
	$Map.move_child(details, 1)
	var seoul := Node2D.new()
	seoul.name = "Seoul"
	details.add_child(seoul)
	var incheon := Node2D.new()
	incheon.name = "Incheon"
	details.add_child(incheon)
	var suwon := Node2D.new()
	suwon.name = "Suwon"
	details.add_child(suwon)
	var cheonan := Node2D.new()
	cheonan.name = "Cheonan"
	details.add_child(cheonan)
	_add_map_polygon(seoul, "HangangPark", Vector2(455, 280), PackedVector2Array([Vector2(-120, 10), Vector2(35, -65), Vector2(155, -5), Vector2(90, 105), Vector2(-55, 120)]), Color("657b56"), 1)
	_add_map_polygon(seoul, "BukhansanRidge", Vector2(1055, 150), PackedVector2Array([Vector2(-130, 70), Vector2(-95, 5), Vector2(-48, 20), Vector2(5, -65), Vector2(46, 4), Vector2(92, -20), Vector2(143, 70), Vector2(80, 103), Vector2(-42, 100)]), Color("71816a"), 1)
	_add_map_polygon(seoul, "BukhansanLightSlope", Vector2(1055, 150), PackedVector2Array([Vector2(-48, 20), Vector2(5, -65), Vector2(46, 4), Vector2(12, -5), Vector2(-5, 22)]), Color("a4a984"), 2)
	_add_map_polygon(seoul, "CentralDistrict", Vector2(1090, 285), PackedVector2Array([Vector2(-125, 8), Vector2(-45, -68), Vector2(98, -42), Vector2(125, 48), Vector2(32, 95), Vector2(-95, 72)]), Color("526b59"), 1)
	_add_map_polygon(seoul, "EastDistrict", Vector2(1450, 465), PackedVector2Array([Vector2(-90, -45), Vector2(25, -75), Vector2(112, -12), Vector2(72, 67), Vector2(-52, 74)]), Color("58705a"), 1)
	_add_tree_cluster(seoul, "ParkTreesA", Vector2(405, 300), 7)
	_add_tree_cluster(seoul, "ParkTreesB", Vector2(525, 330), 6)
	_add_neighborhood_building(seoul, "MidtownBlockA", Vector2(1015, 280), Color("b6a980"))
	_add_neighborhood_building(seoul, "MidtownBlockB", Vector2(1090, 245), Color("c0b38f"))
	_add_neighborhood_building(seoul, "MidtownBlockC", Vector2(1160, 305), Color("a99f80"))
	_add_neighborhood_building(seoul, "EastBlockA", Vector2(1405, 438), Color("b9ad8b"))
	_add_map_line(seoul, "OfficeRoad", PackedVector2Array([Vector2(865, 365), Vector2(910, 350), Vector2(940, 348)]), 13.0, Color("786a54"), 2)
	_add_map_line(seoul, "HallRoad", PackedVector2Array([Vector2(1225, 650), Vector2(1270, 680), Vector2(1320, 710)]), 14.0, Color("786a54"), 2)
	var bridge_points := PackedVector2Array([Vector2(650, 408), Vector2(690, 407), Vector2(735, 414), Vector2(780, 418), Vector2(825, 414)])
	_add_map_line(seoul, "BridgeDeck", bridge_points, 38.0, Color("5d716a"), 2)
	_add_map_line(seoul, "BridgeSurface", bridge_points, 29.0, Color("b9a278"), 3)
	_add_map_line(seoul, "BridgeMarking", bridge_points, 3.0, Color("e1d2ad"), 4)
	_add_map_polygon(incheon, "PortApron", Vector2(240, 515), PackedVector2Array([Vector2(-115, 0), Vector2(5, -48), Vector2(130, -5), Vector2(95, 74), Vector2(-70, 96)]), Color("4e6962"), 1)
	_add_map_polygon(incheon, "WestSeaInlet", Vector2(65, 500), PackedVector2Array([Vector2(-140, -70), Vector2(32, -112), Vector2(128, -36), Vector2(95, 30), Vector2(140, 110), Vector2(20, 155), Vector2(-125, 88)]), Color("3d7181"), 0)
	_add_map_polygon(incheon, "TidalFlat", Vector2(180, 620), PackedVector2Array([Vector2(-90, -12), Vector2(38, -56), Vector2(152, -4), Vector2(110, 58), Vector2(-35, 75)]), Color("78958a"), 1)
	_add_map_polygon(incheon, "PortWarehouseA", Vector2(205, 475), PackedVector2Array([Vector2(-44, 0), Vector2(-18, -30), Vector2(42, -18), Vector2(48, 18), Vector2(-12, 34)]), Color("7c7867"), 2)
	_add_map_polygon(incheon, "PortWarehouseB", Vector2(315, 505), PackedVector2Array([Vector2(-38, 2), Vector2(-12, -28), Vector2(42, -12), Vector2(46, 20), Vector2(-8, 34)]), Color("89816d"), 2)
	_add_map_line(incheon, "PierWest", PackedVector2Array([Vector2(135, 560), Vector2(90, 605), Vector2(25, 625)]), 9.0, Color("786b55"), 4)
	_add_map_line(incheon, "PierEast", PackedVector2Array([Vector2(285, 585), Vector2(350, 625), Vector2(405, 676)]), 9.0, Color("786b55"), 4)
	_add_map_line(incheon, "HallRoad", PackedVector2Array([Vector2(360, 720), Vector2(408, 752), Vector2(450, 780)]), 13.0, Color("786a54"), 2)
	_add_map_polygon(suwon, "IndustrialQuarter", Vector2(1330, 310), PackedVector2Array([Vector2(-95, 0), Vector2(-45, -58), Vector2(65, -46), Vector2(112, 5), Vector2(48, 74), Vector2(-72, 58)]), Color("657663"), 1)
	_add_map_polygon(suwon, "GwanggyoHill", Vector2(1535, 315), PackedVector2Array([Vector2(-105, 42), Vector2(-75, -20), Vector2(-25, -68), Vector2(24, -10), Vector2(71, -42), Vector2(118, 44), Vector2(40, 80), Vector2(-44, 77)]), Color("71836c"), 1)
	_add_map_line(suwon, "HwaseongRampart", PackedVector2Array([Vector2(1350, 373), Vector2(1370, 350), Vector2(1412, 344), Vector2(1450, 362), Vector2(1462, 393), Vector2(1435, 414), Vector2(1390, 412), Vector2(1350, 373)]), 5.0, Color("c3ae82"), 3)
	_add_neighborhood_building(suwon, "FactoryA", Vector2(1320, 305), Color("a89a79"))
	_add_neighborhood_building(suwon, "FactoryB", Vector2(1405, 335), Color("b2a27d"))
	_add_map_polygon(cheonan, "FarmFields", Vector2(1015, 700), PackedVector2Array([Vector2(-115, 0), Vector2(-60, -58), Vector2(60, -50), Vector2(130, 15), Vector2(80, 82), Vector2(-65, 65)]), Color("829065"), 1)
	_add_map_line(cheonan, "FieldRowsA", PackedVector2Array([Vector2(930, 690), Vector2(1065, 780)]), 4.0, Color("a5ad79"), 2)
	_add_map_line(cheonan, "FieldRowsB", PackedVector2Array([Vector2(950, 665), Vector2(1090, 760)]), 4.0, Color("a5ad79"), 2)
	_add_map_line(cheonan, "FieldRowsC", PackedVector2Array([Vector2(980, 640), Vector2(1110, 735)]), 4.0, Color("a5ad79"), 2)
	_add_map_line(cheonan, "HallRoad", PackedVector2Array([Vector2(1025, 795), Vector2(1080, 815), Vector2(1100, 790)]), 13.0, Color("786a54"), 2)

## 지도 장식용 저채도 다각형을 만든다.
func _add_map_polygon(parent: Node2D, node_name: String, node_position: Vector2, points: PackedVector2Array, fill: Color, layer: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.position = node_position
	polygon.polygon = points
	polygon.color = fill
	polygon.z_index = layer
	parent.add_child(polygon)

## 지도 위 도로·부두 표시선을 만든다.
func _add_map_line(parent: Node2D, node_name: String, points: PackedVector2Array, line_width: float, line_color: Color, layer: int) -> void:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.width = line_width
	line.default_color = line_color
	line.z_index = layer
	parent.add_child(line)

## 서울 도심에 작고 읽기 쉬운 아이소메트릭 건물 실루엣을 배치한다.
func _add_neighborhood_building(parent: Node2D, node_name: String, center: Vector2, wall_color: Color) -> void:
	var building := Node2D.new()
	building.name = node_name
	building.position = center
	building.z_index = 2
	parent.add_child(building)
	var walls := Polygon2D.new()
	walls.name = "Walls"
	walls.polygon = PackedVector2Array([Vector2(-18, 2), Vector2(-18, -22), Vector2(-4, -32), Vector2(20, -20), Vector2(20, 5), Vector2(2, 16)])
	walls.color = wall_color
	building.add_child(walls)
	var roof := Polygon2D.new()
	roof.name = "Roof"
	roof.polygon = PackedVector2Array([Vector2(-18, -22), Vector2(-4, -32), Vector2(20, -20), Vector2(5, -10)])
	roof.color = Color("657467")
	roof.z_index = 1
	building.add_child(roof)
	for window_index in 2:
		var window := Polygon2D.new()
		window.name = "Window%d" % window_index
		var left := -11.0 + float(window_index) * 13.0
		window.polygon = PackedVector2Array([Vector2(left, -16), Vector2(left + 6, -13), Vector2(left + 6, -5), Vector2(left, -8)])
		window.color = Color("6b9790")
		window.z_index = 2
		building.add_child(window)

## 공원에 반복 가능한 수목 임시 도형을 배치한다.
func _add_tree_cluster(parent: Node2D, node_name: String, center: Vector2, count: int) -> void:
	var cluster := Node2D.new()
	cluster.name = node_name
	parent.add_child(cluster)
	for index in count:
		var crown := Polygon2D.new()
		crown.name = "Tree%02d" % index
		crown.position = center + Vector2((index % 3) * 24.0 - 24.0, (float(index) / 3.0) * 22.0 - 10.0)
		crown.polygon = PackedVector2Array([Vector2(-12, 0), Vector2(-7, -10), Vector2(1, -14), Vector2(10, -7), Vector2(12, 3), Vector2(4, 10), Vector2(-7, 8)])
		crown.color = Color("82936a") if index % 2 == 0 else Color("71885e")
		crown.z_index = 2
		cluster.add_child(crown)


func _exit_tree() -> void:
	GameSession.set_pause_reason("building_menu", false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(player) and not SceneRouter.entering_building:
		GameSession.update_world_state(region_id, player.global_position, false)

func _update_hud() -> void:
	var region_name := str(GameSession.region_definitions.get(region_id, {}).get("name", region_id))
	var region_ids: Array = GameSession.region_definitions.keys()
	region_ids.sort()
	var current_index := region_ids.find(region_id)
	var next_region := str(region_ids[(current_index + 1) % region_ids.size()]) if not region_ids.is_empty() else region_id
	var next_name := str(GameSession.region_definitions.get(next_region, {}).get("name", next_region))
	status_label.text = "%s · 방향키 또는 지면 클릭" % region_name
	region_button.text = "%s시청까지 걷기" % next_name
	$UI/BottomBar/Hint.text = "방향키 이동  ·  지면 클릭 이동  ·  건물 클릭 후 방문"

## F5 디버그 실행에서 건물 상호작용 경로를 Output 패널에 기록한다.
func _interaction_log(message: String) -> void:
	if OS.is_debug_build():
		print("[BUILDING_INTERACTION] %s" % message)
