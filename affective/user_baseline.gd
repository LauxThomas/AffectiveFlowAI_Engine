# Per-user adaptive baseline [KEY DIFFERENTIATOR, spec Stage 3]. Absolute
# feature values differ wildly by person/device/age, so "high load" is
# defined as deviation from THIS player's own rolling norm, not a global
# threshold. This is part of why the model resists naive cloning: a cloned
# formula with no accumulated personal history is just an unpersonalized
# guess (see heuristic_load_model.gd's docstring).
extends RefCounted
class_name UserBaseline

const SAVE_PATH := "user://baseline.json"
const EWMA_ALPHA := 0.05
const MIN_VARIANCE := 0.0001   # epsilon guard: near-zero variance would blow up z-scores

var _mean: Dictionary = {}       # feature key (String) -> float
var _variance: Dictionary = {}   # feature key (String) -> float

static func load_or_create() -> UserBaseline:
	var baseline := UserBaseline.new()
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text.is_empty():
		return baseline
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return baseline
	var data: Dictionary = parsed as Dictionary
	var mean_data: Variant = data.get("mean", {})
	var variance_data: Variant = data.get("variance", {})
	if typeof(mean_data) == TYPE_DICTIONARY:
		baseline._mean = (mean_data as Dictionary).duplicate()
	if typeof(variance_data) == TYPE_DICTIONARY:
		baseline._variance = (variance_data as Dictionary).duplicate()
	return baseline

# EWMA mean/variance update (Welford-style exponential variant) - cheap
# enough to run every estimator tick, no historical sample storage needed.
func update(key: String, value: float) -> void:
	if not _mean.has(key):
		_mean[key] = value
		_variance[key] = MIN_VARIANCE
		return
	var prev_mean: float = float(_mean[key])
	var diff: float = value - prev_mean
	var new_mean: float = prev_mean + EWMA_ALPHA * diff
	var prev_variance: float = float(_variance.get(key, MIN_VARIANCE))
	var new_variance: float = (1.0 - EWMA_ALPHA) * (prev_variance + EWMA_ALPHA * diff * diff)
	_mean[key] = new_mean
	_variance[key] = maxf(new_variance, MIN_VARIANCE)

func z_score(key: String, value: float) -> float:
	if not _mean.has(key):
		return 0.0
	var mean_value: float = float(_mean[key])
	var variance_value: float = maxf(float(_variance.get(key, MIN_VARIANCE)), MIN_VARIANCE)
	var std_dev: float = sqrt(variance_value)
	return (value - mean_value) / std_dev

func save() -> void:
	var data: Dictionary = {"mean": _mean, "variance": _variance}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()
