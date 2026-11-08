## 월 기념일 기준의 게임 날짜를 실제 실행 시간만으로 계산한다.
extends RefCounted

const REAL_SECONDS_PER_MONTH := 600.0
const SECONDS_PER_DAY := 86400.0

var start_date: Dictionary = {"year": 2025, "month": 1, "day": 20, "hour": 0, "minute": 0, "second": 0}
var elapsed_real_seconds: float = 0.0
var processed_through_day: int

func _init() -> void:
	processed_through_day = get_day_start_timestamp(_start_timestamp())

## 누적 실제 플레이 시간에 따라 월 기념일 사이 날짜를 선형 보간한다.
func current_timestamp() -> float:
	var month_index := floori(elapsed_real_seconds / REAL_SECONDS_PER_MONTH)
	var segment_seconds := fposmod(elapsed_real_seconds, REAL_SECONDS_PER_MONTH)
	var start := anniversary_timestamp(month_index)
	var next := anniversary_timestamp(month_index + 1)
	return float(start) + float(next - start) * segment_seconds / REAL_SECONDS_PER_MONTH

func advance(active_real_seconds: float) -> void:
	elapsed_real_seconds += maxf(active_real_seconds, 0.0)

func get_current_date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(floor(current_timestamp())))

func get_current_day_start() -> int:
	return get_day_start_timestamp(int(floor(current_timestamp())))

func get_date_string(timestamp: int = -1) -> String:
	var stamp := int(floor(current_timestamp())) if timestamp < 0 else timestamp
	var date := Time.get_datetime_dict_from_unix_time(stamp)
	return "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]

func anniversary_timestamp(month_index: int) -> int:
	var month_offset := int(start_date["month"]) - 1 + month_index
	var year := int(start_date["year"]) + floori(float(month_offset) / 12.0)
	var month := posmod(month_offset, 12) + 1
	var day := mini(int(start_date["day"]), days_in_month(year, month))
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0})

func next_unprocessed_day() -> int:
	return processed_through_day + int(SECONDS_PER_DAY)

func mark_day_processed(timestamp: int) -> void:
	processed_through_day = get_day_start_timestamp(timestamp)

func is_month_anniversary(timestamp: int, contract_day: int, contract_start_timestamp: int) -> bool:
	var date := Time.get_datetime_dict_from_unix_time(timestamp)
	return timestamp > contract_start_timestamp and int(date["day"]) == mini(contract_day, days_in_month(int(date["year"]), int(date["month"])))

func save_state() -> Dictionary:
	return {"start_date": start_date.duplicate(true), "elapsed_real_seconds": elapsed_real_seconds, "processed_through_day": processed_through_day}

func load_state(state: Dictionary) -> bool:
	var candidate: Variant = state.get("start_date", {})
	if not candidate is Dictionary or not candidate.has("year") or not candidate.has("month") or not candidate.has("day"):
		return false
	var year := int(candidate["year"])
	var month := int(candidate["month"])
	var day := int(candidate["day"])
	if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month):
		return false
	start_date = {"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0}
	elapsed_real_seconds = maxf(float(state.get("elapsed_real_seconds", 0.0)), 0.0)
	processed_through_day = int(state.get("processed_through_day", get_day_start_timestamp(_start_timestamp())))
	return true

static func days_in_month(year: int, month: int) -> int:
	match month:
		4, 6, 9, 11: return 30
		2: return 29 if is_leap_year(year) else 28
		_: return 31

static func is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)

static func get_day_start_timestamp(timestamp: int) -> int:
	return floori(float(timestamp) / SECONDS_PER_DAY) * int(SECONDS_PER_DAY)

func _start_timestamp() -> int:
	return Time.get_unix_time_from_datetime_dict(start_date)
