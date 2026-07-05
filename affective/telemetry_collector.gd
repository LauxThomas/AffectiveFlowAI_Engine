extends RefCounted
class_name TelemetryCollector

const MAX_EVENTS := 64   # hard cap on the live buffer; window sizing is FeatureWindow's job

var _events: Array[Dictionary] = []

func record(event_type: AffectiveTypes.EventType, payload: Dictionary) -> void:
	var event: Dictionary = payload.duplicate()
	event["type"] = event_type
	event["t_usec"] = Time.get_ticks_usec()
	_events.append(event)
	if _events.size() > MAX_EVENTS:
		_events.pop_front()

func events_since(t_usec: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _events:
		if int(event["t_usec"]) > t_usec:
			out.append(event)
	return out
