# v1 heuristic cognitive-load model. This is NOT a trained model - it's a
# transparent, documented formula behind the ICognitiveLoadModel seam so a
# real classifier can replace it later without touching game/ code.
#
# This commit fuses FeatureWindow's fixed-range-normalized features directly
# (a stand-in "personal signal"); C5 swaps that input for real per-user
# z-scores from UserBaseline without changing this formula's shape.
#
# Why this resists naive cloning: the formula shape here is not the moat (it's
# ordinary signal-fusion + logistic squashing, publishable). The moat is (a)
# the accumulated labelled dataset SessionLogger builds, (b) the per-user
# adaptive baseline that only forms from real interaction history, and (c)
# the weights/thresholds below once tuned on a validated study - a cloner
# copying this file gets an untuned, unpersonalized guess.
extends ICognitiveLoadModel
class_name HeuristicLoadModel

# ─── Stage 4: fusion weights (exported config constants, tuned later) ──────
const W_REACTION_LATENCY := 1.0
const W_HESITATION := 1.0
const W_SWIPE_VAR := 0.8
const W_ERROR_RATE := 1.2
const W_ANSWER_INCORRECT := 1.0
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

func predict(features: Dictionary) -> Dictionary:
	var cli_raw: float = _fuse_features(features)
	var load: float = 1.0 / (1.0 + exp(-GAIN_K * cli_raw))
	var sample_count: int = int(features.get("sample_count", 0))
	var confidence: float = clampf(float(sample_count) / float(FeatureWindow.MAX_EVENTS), 0.0, 1.0)
	var state: AffectiveTypes.CognitiveState = _classify(load, features)
	return {"state": state, "load": load, "confidence": confidence}

func _fuse_features(f: Dictionary) -> float:
	var swipe_velocity_mean: float = float(f.get("swipe_velocity_mean", 0.0))
	var lane_switch_rate: float = float(f.get("lane_switch_rate", 0.0))
	var throughput: float = clampf((swipe_velocity_mean + lane_switch_rate) * 0.5, 0.0, 1.0)
	var answer_correct_rate: float = float(f.get("answer_correct_rate", 1.0))

	return (
		W_REACTION_LATENCY * float(f.get("reaction_latency_mean", 0.0))
		+ W_HESITATION * float(f.get("hesitation_rate", 0.0))
		+ W_SWIPE_VAR * float(f.get("swipe_velocity_var", 0.0))
		+ W_ERROR_RATE * float(f.get("error_rate", 0.0))
		+ W_ANSWER_INCORRECT * (1.0 - answer_correct_rate)
		+ W_IDLE * float(f.get("idle_ratio", 0.0))
		- W_THROUGHPUT * throughput
	)

func _classify(load: float, features: Dictionary) -> AffectiveTypes.CognitiveState:
	var idle_ratio: float = float(features.get("idle_ratio", 0.0))
	if load < LOW_LOAD_THRESHOLD and idle_ratio > BOREDOM_IDLE_THRESHOLD:
		return AffectiveTypes.CognitiveState.BOREDOM
	if load > HIGH_LOAD_THRESHOLD:
		return AffectiveTypes.CognitiveState.OVERWHELM
	return AffectiveTypes.CognitiveState.FLOW
