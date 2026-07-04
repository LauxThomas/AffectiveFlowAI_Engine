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

var _current_state: AffectiveTypes.CognitiveState = AffectiveTypes.CognitiveState.FLOW
var _current_params: AdaptationParams = AdaptationParams.new()
var _telemetry: TelemetryCollector = TelemetryCollector.new()
var _window: FeatureWindow = FeatureWindow.new()
var _last_tick_usec: int = 0
var _last_features: Dictionary = {}

func _ready() -> void:
	_last_tick_usec = Time.get_ticks_usec()
	var tick_timer := Timer.new()
	tick_timer.wait_time = TICK_INTERVAL
	tick_timer.one_shot = false
	tick_timer.autostart = true
	add_child(tick_timer)
	tick_timer.timeout.connect(_on_tick)

func report_event(event_type: AffectiveTypes.EventType, payload: Dictionary) -> void:
	_telemetry.record(event_type, payload)

func get_params() -> AdaptationParams:
	return _current_params.duplicate_params()

func current_state() -> AffectiveTypes.CognitiveState:
	return _current_state

func debug_event_count() -> int:
	return _telemetry.total_recorded()

func debug_features() -> Dictionary:
	return _last_features

func _on_tick() -> void:
	var new_events: Array[Dictionary] = _telemetry.events_since(_last_tick_usec)
	_window.push_events(new_events)
	_last_features = _window.extract()
	_last_tick_usec = Time.get_ticks_usec()
