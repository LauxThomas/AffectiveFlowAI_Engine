extends RefCounted
class_name IAdaptationPolicy

# Swappable seam: a future RL agent implements this same
# decide(state, load, dt) -> AdaptationParams signature and drops in without
# touching game/ code.
func decide(_state: AffectiveTypes.CognitiveState, _load: float, _dt: float) -> AdaptationParams:
	assert(false, "IAdaptationPolicy.decide() must be overridden")
	return AdaptationParams.new()
