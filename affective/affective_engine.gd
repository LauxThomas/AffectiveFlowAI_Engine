# Autoload "AffectiveEngine" (see project.godot [autoload]).
# Deliberately NO class_name here: it would conflict with the autoload's
# own global identifier of the same name.
#
# Game-agnostic façade: game/ code must only ever call report_event(),
# get_params(), current_state(), and listen to the signals below — never
# reach into affective/ internals directly. This commit is a stub: the
# telemetry/estimator/policy pipeline is wired up incrementally in later
# commits, but the public API surface is final from here on.
extends Node

signal state_changed(new_state: AffectiveTypes.CognitiveState)
signal params_changed(new_params: AdaptationParams)

# Mid-band of the 100-200ms target loop-latency cadence. A child Timer runs
# this, not a hand-rolled _process accumulator: Timer can't drift over a long
# session and never piles up missed ticks after a frame hitch.
const TICK_INTERVAL := 0.15

# A predicted state must persist this many ticks (~600ms) before it's
# accepted as the new current_state - satisfies "sustained condition, not a
# per-frame flicker" without a full HMM (spec's own dwell-gated alternative).
const MIN_DWELL_TICKS := 4

# How often the per-user baseline is flushed to disk - frequent enough that a
# "quit and relaunch" manual test sees the carried-over baseline quickly.
const BASELINE_SAVE_INTERVAL_TICKS := 50   # ~7.5s at 150ms/tick

const MAX_LOG_LINES := 15   # Debug HUD's scrolling event log (spec 4.8)

const MAX_HISTORY := 600   # ~90s of ticks at 150ms/tick - Debug HUD's live load chart

var _current_state: AffectiveTypes.CognitiveState = AffectiveTypes.CognitiveState.FLOW
var _current_params: AdaptationParams = AdaptationParams.new()
var _telemetry: TelemetryCollector = TelemetryCollector.new()
var _window: FeatureWindow = FeatureWindow.new()
var _baseline: UserBaseline
var _model: ICognitiveLoadModel
var _policy: IAdaptationPolicy = RuleBasedPolicy.new()
var _logger: SessionLogger = SessionLogger.new()
var _last_tick_usec: int = 0
var _last_features: Dictionary = {}
var _last_load: float = 0.0
var _last_confidence: float = 0.0
var _pending_state: AffectiveTypes.CognitiveState = AffectiveTypes.CognitiveState.FLOW
var _pending_state_ticks: int = 0
var _ticks_since_save: int = 0
var _event_log: Array[String] = []
var _prev_assist: bool = false
var _prev_hint_level: int = 0
var _load_history: Array[float] = []
var _state_history: Array[int] = []

func _ready() -> void:
	_baseline = UserBaseline.load_or_create()
	_model = HeuristicLoadModel.new(_baseline)
	_last_tick_usec = Time.get_ticks_usec()
	var tick_timer := Timer.new()
	tick_timer.wait_time = TICK_INTERVAL
	tick_timer.one_shot = false
	tick_timer.autostart = true
	add_child(tick_timer)
	tick_timer.timeout.connect(_on_tick)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_baseline.save()
		_logger.set_consent(false)   # flushes and closes the session file cleanly

func report_event(event_type: AffectiveTypes.EventType, payload: Dictionary) -> void:
	_telemetry.record(event_type, payload)
	match event_type:
		AffectiveTypes.EventType.HIT:
			_log("HIT (error signal)")
		AffectiveTypes.EventType.ANSWER:
			_log("ANSWER %s" % ("correct" if bool(payload.get("correct", false)) else "incorrect"))

func get_params() -> AdaptationParams:
	return _current_params.duplicate_params()

func current_state() -> AffectiveTypes.CognitiveState:
	return _current_state

func debug_event_log() -> Array[String]:
	return _event_log.duplicate()

# Live + past status for the Debug HUD's chart - a rolling window, oldest
# first, capped at MAX_HISTORY. Parallel arrays (same index = same tick).
func debug_load_history() -> Array[float]:
	return _load_history.duplicate()

func debug_state_history() -> Array[int]:
	return _state_history.duplicate()

func debug_features() -> Dictionary:
	return _last_features

func debug_load() -> float:
	return _last_load

func debug_confidence() -> float:
	return _last_confidence

func set_logging_consent(enabled: bool) -> void:
	_logger.set_consent(enabled)

func is_logging_enabled() -> bool:
	return _logger.is_enabled()

func debug_logged_ticks() -> int:
	return _logger.ticks_logged()

# Self-report ratings are paired with the estimator's own current reading,
# not a fresh recompute - the player is rating how the last stretch of play
# felt, and _last_* is that same stretch's live output already on hand.
func log_self_report(ratings: Dictionary) -> void:
	_logger.log_self_report(ratings, _current_state, _last_load, _last_confidence, _last_features)

func _on_tick() -> void:
	var new_events: Array[Dictionary] = _telemetry.events_since(_last_tick_usec)
	_window.push_events(new_events)
	_last_features = _window.extract()

	var outcome_hit := false
	var outcome_answer_correct: Variant = null
	for event in new_events:
		var event_type: int = int(event["type"])
		if event_type == AffectiveTypes.EventType.HIT:
			outcome_hit = true
		elif event_type == AffectiveTypes.EventType.ANSWER:
			outcome_answer_correct = bool(event.get("correct", false))

	var prediction: Dictionary = _model.predict(_last_features)
	var predicted_state: AffectiveTypes.CognitiveState = prediction.get("state")
	_last_load = float(prediction.get("load", 0.0))
	_last_confidence = float(prediction.get("confidence", 0.0))

	if predicted_state == _pending_state:
		_pending_state_ticks += 1
	else:
		_pending_state = predicted_state
		_pending_state_ticks = 1

	if _pending_state_ticks >= MIN_DWELL_TICKS and _pending_state != _current_state:
		_current_state = _pending_state
		state_changed.emit(_current_state)
		_log("State -> %s" % AffectiveTypes.state_name(_current_state))

	# Chart history: the continuous raw load, paired with the accepted
	# (dwell-gated) state rather than the raw per-tick guess, so the
	# chart's color-coding matches what's shown everywhere else.
	_load_history.append(_last_load)
	_state_history.append(int(_current_state))
	if _load_history.size() > MAX_HISTORY:
		_load_history.pop_front()
		_state_history.pop_front()

	# Two independent consumers (main.gd via get_params(), the HUD via this
	# signal) each get their own duplicated copy - never the shared instance.
	var next_params: AdaptationParams = _policy.decide(_current_state, _last_load, TICK_INTERVAL)
	var params_changed_flag := not next_params.is_close_to(_current_params, 0.01)
	_current_params = next_params
	if params_changed_flag:
		params_changed.emit(_current_params.duplicate_params())
		if _current_params.assist and not _prev_assist:
			_log("Assist triggered (slow-mo)")
		if _current_params.hint_level > _prev_hint_level:
			_log("Hint level -> %d" % _current_params.hint_level)
		_prev_assist = _current_params.assist
		_prev_hint_level = _current_params.hint_level

	_logger.log_tick(_current_state, prediction, _current_params, _last_features, outcome_hit, outcome_answer_correct)

	_ticks_since_save += 1
	if _ticks_since_save >= BASELINE_SAVE_INTERVAL_TICKS:
		_baseline.save()
		_ticks_since_save = 0

	_last_tick_usec = Time.get_ticks_usec()

func _log(line: String) -> void:
	var timestamp_sec: float = float(Time.get_ticks_usec()) / 1_000_000.0
	_event_log.append("[%.1fs] %s" % [timestamp_sec, line])
	if _event_log.size() > MAX_LOG_LINES:
		_event_log.pop_front()
