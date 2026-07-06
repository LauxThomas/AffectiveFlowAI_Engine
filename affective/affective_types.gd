extends RefCounted
class_name AffectiveTypes

enum CognitiveState { BOREDOM, FLOW, OVERWHELM }
enum EventType { LANE_SWITCH, SWIPE, DECISION, ANSWER, HIT }

const STATE_COLOR: Dictionary = {
	CognitiveState.BOREDOM: Color("4a90d9"),
	CognitiveState.FLOW: Color("4ad991"),
	CognitiveState.OVERWHELM: Color("d94a90"),
}

static func state_name(state: CognitiveState) -> String:
	match state:
		CognitiveState.BOREDOM:
			return "BOREDOM"
		CognitiveState.FLOW:
			return "FLOW"
		CognitiveState.OVERWHELM:
			return "OVERWHELM"
		_:
			return "UNKNOWN"
