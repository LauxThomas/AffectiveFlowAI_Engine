# Paused-game self-report overlay - a lightweight NASA-TLX-style check-in
# (1-9 scale per dimension, not the official 21-point form) that produces
# real ground-truth labels for the estimator's own load/state guesses,
# alongside the same feature snapshot AffectiveEngine already ticks. Opened
# manually via the small button in the main HUD, not on a timer - unlike the
# CLT QuestionOverlay, this isn't gameplay content, so it should never
# interrupt play uninvited.
extends CanvasLayer
class_name SelfReportOverlay

# ratings is a Dictionary[String, int] on submit, or null if skipped.
signal finished(ratings: Variant)

const DIMENSIONS: Array[Dictionary] = [
	{"key": "mental_demand", "label": "Mental Demand", "low": "Low", "high": "High"},
	{"key": "physical_demand", "label": "Physical Demand", "low": "Low", "high": "High"},
	{"key": "temporal_demand", "label": "Time Pressure", "low": "Low", "high": "High"},
	{"key": "performance", "label": "Performance", "low": "Perfect", "high": "Failure"},
	{"key": "effort", "label": "Effort", "low": "Low", "high": "High"},
	{"key": "frustration", "label": "Frustration", "low": "Low", "high": "High"},
]
const DEFAULT_VALUE := 5.0

@onready var panel: PanelContainer = $Panel
@onready var dimensions_container: VBoxContainer = $Panel/VBox/Scroll/DimensionsContainer
@onready var submit_button: Button = $Panel/VBox/Actions/SubmitButton
@onready var skip_button: Button = $Panel/VBox/Actions/SkipButton

var _sliders: Dictionary = {}       # String key -> HSlider
var _value_labels: Dictionary = {}  # String key -> Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 96   # above QuestionOverlay's 95 - if both could show at once, self-report wins, but in
	             # practice the button that opens this can't be pressed while another overlay is up.
	panel.visible = false
	submit_button.pressed.connect(_on_submit_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	for dim in DIMENSIONS:
		_build_row(dim)

func is_showing() -> bool:
	return panel.visible

func show_report() -> void:
	for key in _sliders.keys():
		var slider := _sliders[key] as HSlider
		slider.value = DEFAULT_VALUE
		(_value_labels[key] as Label).text = str(int(DEFAULT_VALUE))
	panel.visible = true

func _build_row(dim: Dictionary) -> void:
	var row := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = String(dim["label"])
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)

	var low_label := Label.new()
	low_label.text = String(dim["low"])
	low_label.add_theme_font_size_override("font_size", 11)
	low_label.custom_minimum_size = Vector2(44, 0)
	slider_row.add_child(low_label)

	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 9
	slider.step = 1
	slider.value = DEFAULT_VALUE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_child(slider)

	var high_label := Label.new()
	high_label.text = String(dim["high"])
	high_label.add_theme_font_size_override("font_size", 11)
	high_label.custom_minimum_size = Vector2(44, 0)
	slider_row.add_child(high_label)

	var value_label := Label.new()
	value_label.text = str(int(DEFAULT_VALUE))
	value_label.custom_minimum_size = Vector2(20, 0)
	value_label.add_theme_font_size_override("font_size", 14)
	slider_row.add_child(value_label)

	row.add_child(slider_row)
	dimensions_container.add_child(row)

	var key := String(dim["key"])
	_sliders[key] = slider
	_value_labels[key] = value_label
	slider.value_changed.connect(func(v: float) -> void: value_label.text = str(int(v)))

func _on_submit_pressed() -> void:
	var ratings: Dictionary = {}
	for key in _sliders.keys():
		ratings[key] = int((_sliders[key] as HSlider).value)
	panel.visible = false
	finished.emit(ratings)

func _on_skip_pressed() -> void:
	panel.visible = false
	finished.emit(null)
