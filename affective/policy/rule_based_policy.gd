# v1 rule-based scaffolding policy: targets a FLOW band, deterministic and
# documented. A future RL agent implements the same decide(state, load, dt)
# signature and drops in without touching game/ code.
extends IAdaptationPolicy
class_name RuleBasedPolicy

const MAX_STEP_PER_TICK := 0.03      # rate-limits speed/spawn drift - smooth, not jumpy
const HINT_COOLDOWN_SEC := 15.0      # hints don't spam
const DIFFICULTY_COOLDOWN_SEC := 4.0 # difficulty tier moves at most once per cooldown
const PROGRESSION_RATE := 0.01       # slow long-term creep while sustained in FLOW
const ASSIST_LOAD_THRESHOLD := 0.85  # brief slow-mo only at extreme overwhelm

var _params: AdaptationParams = AdaptationParams.new()
var _hint_cooldown_remaining: float = 0.0
var _difficulty_cooldown_remaining: float = 0.0

func decide(state: AffectiveTypes.CognitiveState, load: float, dt: float) -> AdaptationParams:
	var target: AdaptationParams = _params.duplicate_params()
	var difficulty_step := 0

	match state:
		AffectiveTypes.CognitiveState.BOREDOM:
			target.speed_mult = AdaptationParams.MAX_SPEED_MULT
			target.spawn_mult = AdaptationParams.MAX_SPAWN_MULT
			target.hint_level = maxi(target.hint_level - 1, 0)
			target.assist = false
			difficulty_step = 1
		AffectiveTypes.CognitiveState.OVERWHELM:
			target.speed_mult = AdaptationParams.MIN_SPEED_MULT
			target.spawn_mult = AdaptationParams.MIN_SPAWN_MULT
			target.assist = load > ASSIST_LOAD_THRESHOLD
			if _hint_cooldown_remaining <= 0.0:
				target.hint_level = mini(target.hint_level + 1, AdaptationParams.MAX_HINT_LEVEL)
				_hint_cooldown_remaining = HINT_COOLDOWN_SEC
			difficulty_step = -1
		AffectiveTypes.CognitiveState.FLOW:
			target.assist = false
			target.hint_level = maxi(target.hint_level - 1, 0)
			target.speed_mult = minf(target.speed_mult + PROGRESSION_RATE * dt, AdaptationParams.MAX_SPEED_MULT)

	_hint_cooldown_remaining = maxf(_hint_cooldown_remaining - dt, 0.0)
	_difficulty_cooldown_remaining = maxf(_difficulty_cooldown_remaining - dt, 0.0)
	if difficulty_step != 0 and _difficulty_cooldown_remaining <= 0.0:
		target.difficulty = clampi(target.difficulty + difficulty_step, 0, AdaptationParams.MAX_DIFFICULTY)
		_difficulty_cooldown_remaining = DIFFICULTY_COOLDOWN_SEC
	else:
		target.difficulty = _params.difficulty

	_params.speed_mult = _step_toward(_params.speed_mult, target.speed_mult, MAX_STEP_PER_TICK)
	_params.spawn_mult = _step_toward(_params.spawn_mult, target.spawn_mult, MAX_STEP_PER_TICK)
	_params.difficulty = target.difficulty
	_params.hint_level = target.hint_level
	_params.assist = target.assist
	_params.clamp_values()

	return _params.duplicate_params()

func _step_toward(current: float, target: float, max_step: float) -> float:
	return current + clampf(target - current, -max_step, max_step)
