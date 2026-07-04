# v1 heuristic cognitive-load model. This is NOT a trained model - it's a
# transparent, documented formula behind the ICognitiveLoadModel seam so a
# real classifier can replace it later without touching game/ code.
#
# Fuses per-user z-scores (UserBaseline, Stage 3) of the windowed features
# into a Cognitive Load Index, then squashes through a sigmoid (Stage 4).
# "High load" means deviation from THIS player's own rolling norm, not a
# fixed global threshold.
#
# Documented substitutions vs. the full spec (Stage 1/2 signals we don't yet
# compute - jerk, submovement count, ex-Gaussian tau, post-error slowing):
# reaction_latency_mean stands in for RT coefficient-of-variation, and
# swipe_velocity_var stands in for jerk/submovement count - both are cheaper
# per-tick proxies for the same underlying "erratic/corrective movement"
# signal. error_rate stands in for error-burst clustering. These are
# reasonable v1 stand-ins, not the full feature set; a later pass can add the
# richer per-swipe signals without changing this formula's shape.
#
# Why this resists naive cloning: the formula shape here is not the moat (it's
# ordinary signal-fusion + logistic squashing, publishable). The moat is (a)
# the accumulated labelled dataset SessionLogger builds, (b) the per-user
# adaptive baseline below, which only forms from real interaction history,
# and (c) the weights/thresholds once tuned on a validated study - a cloner
# copying this file gets an untuned, unpersonalized guess.
extends ICognitiveLoadModel
class_name HeuristicLoadModel

# Feature keys that get personally baselined via z-scoring. "throughput" is a
# derived composite (not a raw FeatureWindow key), baselined the same way.
const BASELINE_KEYS: Array[String] = [
	"reaction_latency_mean", "hesitation_rate", "swipe_velocity_var", "error_rate", "idle_ratio",
]
const Z_CLAMP := 4.0   # clamp raw z-scores before fusion - keeps an early/noisy
                       # baseline from spiking the sigmoid input to +/-inf

# ─── Stage 4: fusion weights (exported config constants, tuned later) ──────
const W_REACTION_LATENCY := 1.0   # proxy for z(RT_CV)
const W_HESITATION := 1.0
const W_SWIPE_VAR := 0.8          # proxy for z(jerk)/z(submovements)
const W_ERROR_RATE := 1.2         # proxy for z(error_burst)
const W_ANSWER_INCORRECT := 1.0   # not z-scored: already a bounded [0,1] rate
const W_IDLE := 0.4
const W_THROUGHPUT := 0.6   # subtracted - higher throughput lowers load
const GAIN_K := 4.0         # sigmoid steepness

# ─── Stage 5: 3-band classification thresholds ─────────────────────────────
# v1 simplification of the full challenge/skill 2D balance: true Yerkes-Dodson
# challenge-vs-skill modeling needs a difficulty history that only exists
# once AdaptationParams.difficulty is actually driving gameplay (C6+). Until
# then this uses load level + idle/engagement as the boredom/overwhelm split.
# Sustained-state hysteresis (dwell-gating) lives in AffectiveEngine, not here.
const LOW_LOAD_THRESHOLD := 0.35
const HIGH_LOAD_THRESHOLD := 0.65
const BOREDOM_IDLE_THRESHOLD := 0.3

var _baseline: UserBaseline

func _init(baseline: UserBaseline) -> void:
	_baseline = baseline

func predict(features: Dictionary) -> Dictionary:
	var cli_raw: float = _fuse_features(features)
	var load: float = 1.0 / (1.0 + exp(-GAIN_K * cli_raw))
	var sample_count: int = int(features.get("sample_count", 0))
	var confidence: float = clampf(float(sample_count) / float(FeatureWindow.MAX_EVENTS), 0.0, 1.0)
	var state: AffectiveTypes.CognitiveState = _classify(load, features)
	_update_baseline(features)
	return {"state": state, "load": load, "confidence": confidence}

func _z(features: Dictionary, key: String) -> float:
	var value: float = float(features.get(key, 0.0))
	return clampf(_baseline.z_score(key, value), -Z_CLAMP, Z_CLAMP)

func _fuse_features(f: Dictionary) -> float:
	var swipe_velocity_mean: float = float(f.get("swipe_velocity_mean", 0.0))
	var lane_switch_rate: float = float(f.get("lane_switch_rate", 0.0))
	var throughput: float = clampf((swipe_velocity_mean + lane_switch_rate) * 0.5, 0.0, 1.0)
	var answer_correct_rate: float = float(f.get("answer_correct_rate", 1.0))
	var z_throughput: float = clampf(_baseline.z_score("throughput", throughput), -Z_CLAMP, Z_CLAMP)

	return (
		W_REACTION_LATENCY * _z(f, "reaction_latency_mean")
		+ W_HESITATION * _z(f, "hesitation_rate")
		+ W_SWIPE_VAR * _z(f, "swipe_velocity_var")
		+ W_ERROR_RATE * _z(f, "error_rate")
		+ W_ANSWER_INCORRECT * (1.0 - answer_correct_rate)
		+ W_IDLE * _z(f, "idle_ratio")
		- W_THROUGHPUT * z_throughput
	)

func _update_baseline(f: Dictionary) -> void:
	for key in BASELINE_KEYS:
		_baseline.update(key, float(f.get(key, 0.0)))
	var swipe_velocity_mean: float = float(f.get("swipe_velocity_mean", 0.0))
	var lane_switch_rate: float = float(f.get("lane_switch_rate", 0.0))
	var throughput: float = clampf((swipe_velocity_mean + lane_switch_rate) * 0.5, 0.0, 1.0)
	_baseline.update("throughput", throughput)

func _classify(load: float, features: Dictionary) -> AffectiveTypes.CognitiveState:
	var idle_ratio: float = float(features.get("idle_ratio", 0.0))
	if load < LOW_LOAD_THRESHOLD and idle_ratio > BOREDOM_IDLE_THRESHOLD:
		return AffectiveTypes.CognitiveState.BOREDOM
	if load > HIGH_LOAD_THRESHOLD:
		return AffectiveTypes.CognitiveState.OVERWHELM
	return AffectiveTypes.CognitiveState.FLOW
