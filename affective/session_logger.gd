# GDPR-safe session logging: opt-in (default OFF), anonymous session id (not
# tied to any identity), all on-device, nothing leaves the machine. This is
# the labelled dataset a future trained model would learn from - outcomes
# (hits, answers) double as labels for the estimator's own predictions.
extends RefCounted
class_name SessionLogger

const SESSIONS_DIR := "user://sessions/"

var _enabled: bool = false
var _file: FileAccess = null
var _ticks_logged: int = 0

func set_consent(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if enabled:
		_start_session()
	else:
		_close_session()

func is_enabled() -> bool:
	return _enabled

func ticks_logged() -> int:
	return _ticks_logged

func log_tick(
	state: AffectiveTypes.CognitiveState,
	prediction: Dictionary,
	params: AdaptationParams,
	features: Dictionary,
	outcome_hit: bool,
	outcome_answer_correct: Variant
) -> void:
	if not _enabled or _file == null:
		return
	var line: Dictionary = {
		"kind": "tick",
		"t": Time.get_ticks_usec(),
		"features": features,
		"predicted_state": int(state),
		"load": float(prediction.get("load", 0.0)),
		"confidence": float(prediction.get("confidence", 0.0)),
		"params": {
			"speed_mult": params.speed_mult,
			"spawn_mult": params.spawn_mult,
			"difficulty": params.difficulty,
			"hint_level": params.hint_level,
			"assist": params.assist,
		},
		"outcome_hit": outcome_hit,
		"outcome_answer_correct": outcome_answer_correct,
	}
	_file.store_line(JSON.stringify(line))
	_file.flush()   # Web's IDBFS sync isn't instant on abrupt close - flush each line to reduce (not eliminate) loss risk
	_ticks_logged += 1

# The real ground-truth label for a future trained model: a NASA-TLX-style
# self-report (see ui/self_report_overlay.gd), paired with the estimator's
# own reading at that same moment so the two can be compared/trained against
# directly. Same file, same consent gate as log_tick - a "kind" field is what
# tells the two apart when parsing the JSONL later.
func log_self_report(
	ratings: Dictionary,
	state: AffectiveTypes.CognitiveState,
	load: float,
	confidence: float,
	features: Dictionary
) -> void:
	if not _enabled or _file == null:
		return
	var line: Dictionary = {
		"kind": "self_report",
		"t": Time.get_ticks_usec(),
		"ratings": ratings,
		"predicted_state": int(state),
		"load": load,
		"confidence": confidence,
		"features": features,
	}
	_file.store_line(JSON.stringify(line))
	_file.flush()

func _start_session() -> void:
	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	var session_id: String = _generate_uuid()
	_file = FileAccess.open(SESSIONS_DIR + session_id + ".jsonl", FileAccess.WRITE)
	_ticks_logged = 0

func _close_session() -> void:
	if _file != null:
		_file.close()
		_file = null

func _generate_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts: Array[String] = []
	for i in 4:
		parts.append("%08x" % rng.randi())
	return "-".join(parts)

static func list_sessions() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SESSIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".jsonl"):
			out.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out

static func export_session(session_id: String) -> String:
	return FileAccess.get_file_as_string(SESSIONS_DIR + session_id)

static func delete_all_sessions() -> void:
	var dir := DirAccess.open(SESSIONS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()
