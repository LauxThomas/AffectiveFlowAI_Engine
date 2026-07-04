extends RefCounted
class_name AdaptationParams

# ─── Safe ranges ───────────────────────────────────────────
const MIN_SPEED_MULT := 0.6
const MAX_SPEED_MULT := 1.5
const MIN_SPAWN_MULT := 0.6
const MAX_SPAWN_MULT := 1.8
const MAX_DIFFICULTY := 4
const MAX_HINT_LEVEL := 2

var speed_mult: float = 1.0
var spawn_mult: float = 1.0
var difficulty: int = 1
var hint_level: int = 0
var assist: bool = false

func clamp_values() -> void:
	speed_mult = clampf(speed_mult, MIN_SPEED_MULT, MAX_SPEED_MULT)
	spawn_mult = clampf(spawn_mult, MIN_SPAWN_MULT, MAX_SPAWN_MULT)
	difficulty = clampi(difficulty, 0, MAX_DIFFICULTY)
	hint_level = clampi(hint_level, 0, MAX_HINT_LEVEL)

# named to avoid shadowing Object.duplicate()
func duplicate_params() -> AdaptationParams:
	var copy := AdaptationParams.new()
	copy.speed_mult = speed_mult
	copy.spawn_mult = spawn_mult
	copy.difficulty = difficulty
	copy.hint_level = hint_level
	copy.assist = assist
	return copy

func is_close_to(other: AdaptationParams, epsilon: float) -> bool:
	if other == null:
		return false
	return (
		absf(speed_mult - other.speed_mult) < epsilon
		and absf(spawn_mult - other.spawn_mult) < epsilon
		and difficulty == other.difficulty
		and hint_level == other.hint_level
		and assist == other.assist
	)

func to_debug_string() -> String:
	return "speed x%.2f  spawn x%.2f  diff %d  hint %d  assist:%s" % [
		speed_mult, spawn_mult, difficulty, hint_level, assist
	]
