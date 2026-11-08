## 야외, 사옥, 시청 장면 전환과 야외 복귀 출입구를 관리한다.
extends Node

const WORLD_SCENE := "res://game/world/korea_world.tscn"
const OFFICE_SCENE := "res://game/office/office.tscn"
const CITY_HALL_SCENE := "res://game/city_hall/city_hall.tscn"
const COMBAT_SCENE := "res://game/combat/battle.tscn"
const CAPTIVITY_SCENE := "res://game/captivity/captivity.tscn"
const MAHJONG_SCENE := "res://game/mahjong/mahjong.tscn"

var return_position: Vector2 = Vector2(930.0, 470.0)
var return_region: String = "seoul"
var entering_building := false

func _ready() -> void:
	return_region = GameSession.current_region
	return_position = GameSession.player_position
	call_deferred("_resume_saved_encounter")


## 재시작 시 진행 중인 전투·피랍 흐름을 같은 저장 상태로 복원한다.
func _resume_saved_encounter() -> void:
	if OS.get_cmdline_user_args().has("--phase4-tests"):
		return
	await get_tree().process_frame
	if GameSession.captivity_state.get("active", false):
		get_tree().change_scene_to_file(CAPTIVITY_SCENE)
	elif GameSession.battle_state.get("active", false):
		get_tree().change_scene_to_file(COMBAT_SCENE)
	elif not GameSession.battle_state.is_empty() and GameSession.battle_state.get("processed", false):
		GameSession.battle_state.clear()
		GameSession.save_game()


## 현재 야외 출입구와 지역을 기억하고 내부 장면으로 이동한다.
func enter_building(building_kind: String, region_id: String, outside_position: Vector2) -> void:
	entering_building = true
	return_region = region_id
	return_position = outside_position
	GameSession.update_world_state(region_id, outside_position)
	var destination := OFFICE_SCENE if building_kind == "office" else CITY_HALL_SCENE
	get_tree().change_scene_to_file(destination)
	await get_tree().process_frame
	entering_building = false


## 직전 야외 지역과 출입구를 복원한 뒤 야외 장면으로 돌아간다.
func exit_building() -> void:
	GameSession.current_region = return_region
	GameSession.player_position = return_position
	get_tree().change_scene_to_file(WORLD_SCENE)


## 시청 작업장 진입 전 지역을 저장하고 연결 제거 장면을 연다.
func enter_mahjong() -> void:
	GameSession.save_game()
	get_tree().change_scene_to_file(MAHJONG_SCENE)


## 작업장을 마치거나 중도 종료하면 같은 지역 시청으로 돌아간다.
func exit_mahjong() -> void:
	GameSession.set_pause_reason("mahjong", false)
	get_tree().change_scene_to_file(CITY_HALL_SCENE)


func enter_battle() -> void:
	get_tree().change_scene_to_file(COMBAT_SCENE)


## 승리·도주는 야외 복귀, 패배는 저장된 피랍 협상 화면으로 보낸다.
func finish_battle() -> void:
	if GameSession.captivity_state.get("active", false):
		get_tree().change_scene_to_file(CAPTIVITY_SCENE)
		return
	GameSession.battle_state.clear()
	GameSession.save_game()
	get_tree().change_scene_to_file(WORLD_SCENE)


## 석방 컷씬 완료 뒤 서울 사옥 내부에 복귀한다.
func return_to_office_after_release() -> void:
	var result: Dictionary = GameSession.complete_captivity_release()
	if not result.ok:
		return
	return_region = "seoul"
	return_position = Vector2(940.0, 418.0)
	get_tree().change_scene_to_file(OFFICE_SCENE)
