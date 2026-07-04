extends CanvasLayer

const FEATURE_KEYS: Array[String] = [
	"swipe_velocity_mean", "swipe_velocity_var", "reaction_latency_mean", "hesitation_rate",
	"error_rate", "answer_correct_rate", "lane_switch_rate", "idle_ratio",
]

@onready var panel: PanelContainer = $Panel
@onready var state_label: Label = $Panel/VBoxContainer/StateLabel
@onready var load_meter: ProgressBar = $Panel/VBoxContainer/LoadRow/LoadMeter
@onready var confidence_label: Label = $Panel/VBoxContainer/ConfidenceLabel
@onready var params_label: Label = $Panel/VBoxContainer/ParamsLabel
@onready var events_label: Label = $Panel/VBoxContainer/EventsLabel
@onready var feature_bars: GridContainer = $Panel/VBoxContainer/FeatureBars

func _ready() -> void:
	layer = 100
	panel.visible = false
	AffectiveEngine.state_changed.connect(_on_state_changed)
	AffectiveEngine.params_changed.connect(_on_params_changed)
	_on_state_changed(AffectiveEngine.current_state())
	_on_params_changed(AffectiveEngine.get_params())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			panel.visible = not panel.visible

func _process(_delta: float) -> void:
	if not panel.visible:
		return
	events_label.text = "Events: %d" % AffectiveEngine.debug_event_count()
	load_meter.value = AffectiveEngine.debug_load() * 100.0
	confidence_label.text = "Confidence: %d%%" % int(AffectiveEngine.debug_confidence() * 100.0)
	var features: Dictionary = AffectiveEngine.debug_features()
	for key in FEATURE_KEYS:
		var bar := feature_bars.get_node_or_null(key) as ProgressBar
		if bar != null:
			bar.value = float(features.get(key, 0.0)) * 100.0

func _on_state_changed(new_state: AffectiveTypes.CognitiveState) -> void:
	state_label.text = AffectiveTypes.state_name(new_state)
	state_label.add_theme_color_override("font_color", AffectiveTypes.STATE_COLOR[new_state] as Color)

func _on_params_changed(new_params: AdaptationParams) -> void:
	params_label.text = new_params.to_debug_string()
