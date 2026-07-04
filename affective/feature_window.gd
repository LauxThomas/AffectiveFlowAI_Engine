extends RefCounted
class_name FeatureWindow

# Rolling window: the ONLY thing the estimator sees, per the design's
# game-agnostic seam. Bounded by both wall-clock span and event count so a
# burst of rapid input can't blow past a sane processing cost per tick.
const WINDOW_USEC := 6_000_000     # 6s rolling window
const MAX_EVENTS := 20

# Expected ranges used to normalize raw features into [0,1] - v1 heuristic
# constants (not learned), documented here since tuning them later is part
# of the model's IP. Feature order matches spec 4.2.
const RANGE_SWIPE_VELOCITY := 2500.0        # px/s
const RANGE_REACTION_LATENCY_MS := 1500.0
const RANGE_LANE_SWITCH_RATE := 3.0         # switches/sec
const IDLE_EVENT_SPAN_SEC := 3.0            # must match player.gd's IDLE_THRESHOLD_USEC

var _events: Array[Dictionary] = []

func push_events(events: Array[Dictionary]) -> void:
	for event in events:
		_events.append(event)
	_trim()

func _trim() -> void:
	var cutoff: int = Time.get_ticks_usec() - WINDOW_USEC
	while _events.size() > 0 and int(_events[0]["t_usec"]) < cutoff:
		_events.pop_front()
	while _events.size() > MAX_EVENTS:
		_events.pop_front()

func extract() -> Dictionary:
	var swipe_velocities: Array[float] = []
	var lane_dirs: Array[int] = []
	var latencies_norm: Array[float] = []
	var hit_count := 0
	var decision_count := 0
	var answer_count := 0
	var answer_correct_count := 0
	var idle_count := 0

	for event in _events:
		var event_type: int = int(event["type"])
		match event_type:
			AffectiveTypes.EventType.SWIPE:
				if bool(event.get("accepted", false)):
					swipe_velocities.append(float(event.get("velocity", 0.0)))
			AffectiveTypes.EventType.LANE_SWITCH:
				lane_dirs.append(int(event.get("dir", 0)))
			AffectiveTypes.EventType.DECISION:
				decision_count += 1
				var latency_usec: int = int(event.get("latency_usec", -1))
				var latency_ms: float = RANGE_REACTION_LATENCY_MS if latency_usec < 0 else float(latency_usec) / 1000.0
				latencies_norm.append(clampf(latency_ms / RANGE_REACTION_LATENCY_MS, 0.0, 1.0))
			AffectiveTypes.EventType.HIT:
				hit_count += 1
			AffectiveTypes.EventType.ANSWER:
				answer_count += 1
				if bool(event.get("correct", false)):
					answer_correct_count += 1
			AffectiveTypes.EventType.IDLE:
				idle_count += 1

	var window_sec: float = maxf(float(WINDOW_USEC) / 1_000_000.0, 0.001)

	var swipe_velocity_mean := 0.0
	var swipe_velocity_var := 0.0
	if not swipe_velocities.is_empty():
		var norm_velocities: Array[float] = []
		for v in swipe_velocities:
			norm_velocities.append(clampf(v / RANGE_SWIPE_VELOCITY, 0.0, 1.0))
		swipe_velocity_mean = _mean(norm_velocities)
		# variance of values in [0,1] is bounded by 0.25 - scale by 4 to fill [0,1]
		swipe_velocity_var = clampf(_variance(norm_velocities, swipe_velocity_mean) * 4.0, 0.0, 1.0)

	var reversals := 0
	var last_dir := 0
	for dir in lane_dirs:
		if last_dir != 0 and dir == -last_dir:
			reversals += 1
		last_dir = dir
	var hesitation_rate: float = 0.0 if lane_dirs.is_empty() else clampf(float(reversals) / float(lane_dirs.size()), 0.0, 1.0)

	var reaction_latency_mean: float = 0.0 if latencies_norm.is_empty() else _mean(latencies_norm)
	var error_rate: float = clampf(float(hit_count) / float(maxi(decision_count, 1)), 0.0, 1.0)
	# no answers yet (Knowledge Packs land in C9) -> neutral/no-evidence-of-failure default
	var answer_correct_rate: float = 1.0 if answer_count == 0 else clampf(float(answer_correct_count) / float(answer_count), 0.0, 1.0)
	var lane_switch_rate: float = clampf(float(lane_dirs.size()) / window_sec / RANGE_LANE_SWITCH_RATE, 0.0, 1.0)
	var idle_ratio: float = clampf(float(idle_count) * IDLE_EVENT_SPAN_SEC / window_sec, 0.0, 1.0)

	return {
		"swipe_velocity_mean": swipe_velocity_mean,
		"swipe_velocity_var": swipe_velocity_var,
		"reaction_latency_mean": reaction_latency_mean,
		"hesitation_rate": hesitation_rate,
		"error_rate": error_rate,
		"answer_correct_rate": answer_correct_rate,
		"lane_switch_rate": lane_switch_rate,
		"idle_ratio": idle_ratio,
		"sample_count": _events.size(),
	}

func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())

func _variance(values: Array[float], mean_value: float) -> float:
	if values.size() < 2:
		return 0.0
	var total := 0.0
	for v in values:
		total += (v - mean_value) * (v - mean_value)
	return total / float(values.size())
