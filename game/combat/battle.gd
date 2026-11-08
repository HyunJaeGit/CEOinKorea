## 저장된 BattleState를 읽고 매 턴 하나의 수동 명령을 제출한다.
extends Control

func _ready() -> void:
	$Card/Rows/Commands/Attack.pressed.connect(_command.bind("attack"))
	$Card/Rows/Commands/Skill.pressed.connect(_command.bind("skill"))
	$Card/Rows/Commands/Defend.pressed.connect(_command.bind("defend"))
	$Card/Rows/Commands/Switch.pressed.connect(_command.bind("switch"))
	$Card/Rows/Commands/Escape.pressed.connect(_command.bind("escape"))
	GameSession.state_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if GameSession.state_changed.is_connected(_refresh):
		GameSession.state_changed.disconnect(_refresh)


func _command(command: String) -> void:
	var target_id := ""
	if command == "switch":
		if $Card/Rows/Commands/Reserve.item_count == 0:
			$Card/Rows/Result.text = "교체할 수 있는 용병이 없습니다."
			return
		target_id = str($Card/Rows/Commands/Reserve.get_item_metadata($Card/Rows/Commands/Reserve.selected))
	var result: Dictionary = GameSession.select_battle_command(command, target_id)
	$Card/Rows/Result.text = "턴이 끝났습니다." if result.ok else _reason_text(str(result.get("reason", "")))
	_refresh()
	if result.ok and not GameSession.battle_state.get("active", false):
		call_deferred("_finish_scene")


func _finish_scene() -> void:
	SceneRouter.finish_battle()


func _refresh() -> void:
	if not is_node_ready() or GameSession.battle_state.is_empty():
		return
	var battle: Dictionary = GameSession.battle_state
	var active_id := str(battle.get("active_mercenary_id", ""))
	var mercenary: Dictionary = GameSession.mercenaries.get(active_id, {})
	var mercenary_def: Dictionary = GameSession.mercenary_definitions.get(str(mercenary.get("type_id", "")), {})
	$Card/Rows/Title.text = "전투  ·  턴 %d" % int(battle.get("turn", 1))
	$Card/Rows/Party.text = "%s  ·  HP %d/%d  ·  방어 %d  ·  속도 %d" % [mercenary_def.get("name", "출전 용병"), mercenary.get("hp", 0), mercenary_def.get("max_hp", 0), mercenary_def.get("defense", 0), mercenary_def.get("speed", 0)]
	var enemies_text := "상대 팀\n"
	for enemy in battle.get("enemies", []):
		enemies_text += "%s · 체력 %d/%d\n" % [enemy.get("name", "적"), enemy.get("hp", 0), enemy.get("max_hp", 0)]
	$Card/Rows/Enemies.text = enemies_text
	$Card/Rows/Log.text = "\n".join(PackedStringArray(battle.get("log", [])))
	var skill_id := str(mercenary_def.get("skill_id", ""))
	var skill_label: String = str({"strike":"강타", "protect":"보호", "disrupt":"교란"}.get(skill_id, "고유기"))
	$Card/Rows/Commands/Skill.text = "고유기 · %s" % skill_label
	var last_use := int(battle.get("skill_used_turn", {}).get(active_id, -1000))
	var turns_until_skill := maxi(0, int(mercenary_def.get("skill_cooldown", 3)) - (int(battle.get("turn", 1)) - last_use))
	$Card/Rows/Commands/Skill.disabled = skill_id.is_empty() or turns_until_skill > 0
	$Card/Rows/Commands/Skill.tooltip_text = "바로 사용할 수 있습니다." if turns_until_skill == 0 else "%d턴 뒤 다시 사용할 수 있습니다." % turns_until_skill
	var reserve := $Card/Rows/Commands/Reserve
	var previous := str(reserve.get_item_metadata(reserve.selected)) if reserve.item_count > 0 else ""
	reserve.clear()
	for mercenary_id in GameSession.mercenary_roster:
		if mercenary_id == active_id or int(GameSession.mercenaries.get(mercenary_id, {}).get("hp", 0)) <= 0:
			continue
		var type_id := str(GameSession.mercenaries[mercenary_id]["type_id"])
		reserve.add_item(str(GameSession.mercenary_definitions[type_id]["name"]))
		reserve.set_item_metadata(reserve.get_item_count() - 1, mercenary_id)
		if mercenary_id == previous: reserve.select(reserve.get_item_count() - 1)
	$Card/Rows/Commands/Switch.disabled = reserve.item_count == 0

func _reason_text(reason: String) -> String:
	return {
		"invalid_command": "이 행동은 사용할 수 없습니다.", "invalid_switch": "교체할 용병을 다시 선택해주세요.",
		"skill_unavailable": "고유기를 아직 사용할 수 없습니다.", "battle_not_active": "전투가 이미 끝났습니다."
	}.get(reason, "명령을 사용할 수 없습니다. 다른 행동을 선택해주세요.")
