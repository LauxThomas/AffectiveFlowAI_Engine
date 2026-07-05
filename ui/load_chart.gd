# Live + past cognitive-load line chart for the Debug HUD. Plots
# AffectiveEngine's rolling load history (oldest to newest, left to right),
# color-coded per point by the accepted (dwell-gated) state at that tick,
# with dashed reference lines at the BOREDOM/OVERWHELM thresholds so the
# FLOW band is visible at a glance.
extends Control
class_name LoadChart

const LOW_THRESHOLD := 0.35    # must match HeuristicLoadModel.LOW_LOAD_THRESHOLD
const HIGH_THRESHOLD := 0.65   # must match HeuristicLoadModel.HIGH_LOAD_THRESHOLD
const BACKGROUND_COLOR := Color(0.08, 0.09, 0.11, 0.9)
const THRESHOLD_COLOR := Color(0.6, 0.6, 0.6, 0.5)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.06)

var _load_history: Array[float] = []
var _state_history: Array[int] = []

func update_data(load_history: Array[float], state_history: Array[int]) -> void:
	_load_history = load_history
	_state_history = state_history
	queue_redraw()

func _draw() -> void:
	var size: Vector2 = get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)

	for frac in [0.25, 0.5, 0.75]:
		draw_line(Vector2(0.0, size.y * frac), Vector2(size.x, size.y * frac), GRID_COLOR, 1.0)

	_draw_dashed_hline(size.y * (1.0 - LOW_THRESHOLD), size.x, THRESHOLD_COLOR)
	_draw_dashed_hline(size.y * (1.0 - HIGH_THRESHOLD), size.x, THRESHOLD_COLOR)

	if _load_history.size() < 2:
		return

	var step: float = size.x / float(maxi(_load_history.size() - 1, 1))
	for i in range(1, _load_history.size()):
		var p0 := Vector2(float(i - 1) * step, size.y * (1.0 - clampf(_load_history[i - 1], 0.0, 1.0)))
		var p1 := Vector2(float(i) * step, size.y * (1.0 - clampf(_load_history[i], 0.0, 1.0)))
		var state: int = _state_history[i] if i < _state_history.size() else AffectiveTypes.CognitiveState.FLOW
		var color: Color = AffectiveTypes.STATE_COLOR.get(state, Color.WHITE) as Color
		draw_line(p0, p1, color, 2.5)

func _draw_dashed_hline(y: float, width: float, color: Color) -> void:
	var dash := 6.0
	var gap := 5.0
	var x := 0.0
	while x < width:
		draw_line(Vector2(x, y), Vector2(minf(x + dash, width), y), color, 1.0)
		x += dash + gap
