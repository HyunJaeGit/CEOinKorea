## 기획안의 수동 턴제 피해·속도·도주 규칙을 계산한다.
extends RefCounted


static func basic_damage(attack: int, defense: int, power_multiplier: float = 1.0) -> int:
	var base := maxi(1, floori(float(attack) - float(defense) * 0.5))
	return maxi(1, floori(float(base) * power_multiplier))


static func escape_chance(player_speed: int, enemy_speed: int, failed_attempts: int) -> float:
	return clampf(0.6 + float(player_speed - enemy_speed) * 0.02 + float(failed_attempts) * 0.1, 0.2, 0.9)


static func action_priority(action: String) -> int:
	match action:
		"defend", "switch", "escape":
			return 1
		"attack", "skill":
			return 0
		_:
			return -1


static func action_precedes(player_action: String, player_speed: int, enemy_speed: int) -> bool:
	var player_priority := action_priority(player_action)
	var enemy_priority := action_priority("attack")
	return player_priority > enemy_priority or (player_priority == enemy_priority and player_speed >= enemy_speed)
