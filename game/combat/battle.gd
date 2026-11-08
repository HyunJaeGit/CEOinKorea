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
	$Card/Rows/Result.text = "명령 적용" if result.ok else "명령을 사용할 수 없습니다: %s" % result.get("reason", "확인 필요")
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
	$Card/Rows/Title.text = "야외 조우 · %s전투" % ("" if battle.get("result", "").is_empty() else "결과 · ")
	$Card/Rows/Party.text = "%s · 체력 %d/%d · 방어 %d · 속도 %d\n턴 %d · 고유기 재사용 상태는 명령창에서 확인" % [mercenary_def.get("name", "출전 용병"), mercenary.get("hp", 0), mercenary_def.get("max_hp", 0), mercenary_def.get("defense", 0), mercenary_def.get("speed", 0), battle.get("turn", 1)]
	var enemies_text := "상대\n"
	for enemy in battle.get("enemies", []):
		enemies_text += "%s · 체력 %d/%d\n" % [enemy.get("name", "적"), enemy.get("hp", 0), enemy.get("max_hp", 0)]
	$Card/Rows/Enemies.text = enemies_text
	$Card/Rows/Log.text = "\n".join(PackedStringArray(battle.get("log", [])))
	var skill_id := str(mercenary_def.get("skill_id", ""))
	var skill_label: String = str({"strike":"강타", "protect":"보호", "disrupt":"교란"}.get(skill_id, "고유기"))
	$Card/Rows/Commands/Skill.text = "고유기 · %s" % skill_label
	var last_use := int(battle.get("skill_used_turn", {}).get(active_id, -1000))
	$Card/Rows/Commands/Skill.disabled = skill_id.is_empty() or int(battle.get("turn", 1)) - last_use < int(mercenary_def.get("skill_cooldown", 3))
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
