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

var _current_state: AffectiveTypes.CognitiveState = AffectiveTypes.CognitiveState.FLOW
var _current_params: AdaptationParams = AdaptationParams.new()

func report_event(_event_type: AffectiveTypes.EventType, _payload: Dictionary) -> void:
	pass

func get_params() -> AdaptationParams:
	return _current_params.duplicate_params()

func current_state() -> AffectiveTypes.CognitiveState:
	return _current_state
