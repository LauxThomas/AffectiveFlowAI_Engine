extends RefCounted
class_name ICognitiveLoadModel

# Swappable seam: a future trained model (e.g. ONNX-backed) implements this
# same predict(features) -> {state, load, confidence} signature and drops in
# without any change to AffectiveEngine or game/ code.
func predict(_features: Dictionary) -> Dictionary:
	assert(false, "ICognitiveLoadModel.predict() must be overridden")
	return {"state": AffectiveTypes.CognitiveState.FLOW, "load": 0.5, "confidence": 0.0}
