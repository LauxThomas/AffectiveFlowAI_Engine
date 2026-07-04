extends RefCounted
class_name TelemetryCollector

const MAX_EVENTS := 64   # hard cap on the live buffer; window sizing is FeatureWindow's job

var _events: Array[Dictionary] = []
var _total_recorded := 0

func record(event_type: AffectiveTypes.EventType, payload: Dictionary) -> void:
	var event: Dictionary = payload.duplicate()
	event["type"] = event_type
	event["t_usec"] = Time.get_ticks_usec()
	_events.append(event)
	_total_recorded += 1
	if _events.size() > MAX_EVENTS:
		_events.pop_front()

func events_since(t_usec: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _events:
		if int(event["t_usec"]) > t_usec:
			out.append(event)
	return out

# Lifetime count, unlike _events.size() which is capped by MAX_EVENTS -
# used by the debug HUD's raw event counter.
func total_recorded() -> int:
	return _total_recorded
