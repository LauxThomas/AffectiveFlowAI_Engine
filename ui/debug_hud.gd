extends CanvasLayer

const FEATURE_KEYS: Array[String] = [
	"swipe_velocity_mean", "swipe_velocity_var", "reaction_latency_mean", "hesitation_rate",
	"error_rate", "answer_correct_rate", "lane_switch_rate", "idle_ratio",
]

@onready var panel: PanelContainer = $Panel
@onready var state_label: Label = $Panel/Scroll/VBoxContainer/StateLabel
@onready var load_meter: ProgressBar = $Panel/Scroll/VBoxContainer/LoadRow/LoadMeter
@onready var confidence_label: Label = $Panel/Scroll/VBoxContainer/ConfidenceLabel
@onready var load_chart: LoadChart = $Panel/Scroll/VBoxContainer/LoadChart
@onready var params_label: Label = $Panel/Scroll/VBoxContainer/ParamsLabel
@onready var feature_bars: GridContainer = $Panel/Scroll/VBoxContainer/FeatureBars
@onready var logging_label: Label = $Panel/Scroll/VBoxContainer/LoggingLabel
@onready var packs_label: Label = $Panel/Scroll/VBoxContainer/PacksLabel
@onready var event_log: RichTextLabel = $Panel/Scroll/VBoxContainer/EventLog

var _last_log: Array[String] = []

func _ready() -> void:
	layer = 100
	panel.visible = false
	AffectiveEngine.state_changed.connect(_on_state_changed)
	AffectiveEngine.params_changed.connect(_on_params_changed)
	_on_state_changed(AffectiveEngine.current_state())
	_on_params_changed(AffectiveEngine.get_params())
	_refresh_packs_label()

func _refresh_packs_label() -> void:
	var packs: Dictionary = ContentPackLoader.load_merged_packs()
	var ids: Array[String] = []
	for key in packs.keys():
		ids.append(String(key))
	packs_label.text = "Packs loaded: %d (%s)" % [ids.size(), ", ".join(ids)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			panel.visible = not panel.visible

func _process(_delta: float) -> void:
	if not panel.visible:
		return
	load_meter.value = AffectiveEngine.debug_load() * 100.0
	confidence_label.text = "Confidence: %d%%" % int(AffectiveEngine.debug_confidence() * 100.0)
	load_chart.update_data(AffectiveEngine.debug_load_history(), AffectiveEngine.debug_state_history())
	var features: Dictionary = AffectiveEngine.debug_features()
	for key in FEATURE_KEYS:
		var bar := feature_bars.get_node_or_null(key) as ProgressBar
		if bar != null:
			bar.value = float(features.get(key, 0.0)) * 100.0
	if AffectiveEngine.is_logging_enabled():
		logging_label.text = "Logging: ON - %d ticks (toggle in Settings)" % AffectiveEngine.debug_logged_ticks()
	else:
		logging_label.text = "Logging: off (toggle in Settings)"
	var log_lines: Array[String] = AffectiveEngine.debug_event_log()
	if log_lines != _last_log:
		_last_log = log_lines
		event_log.text = "\n".join(log_lines)

func _on_state_changed(new_state: AffectiveTypes.CognitiveState) -> void:
	state_label.text = AffectiveTypes.state_name(new_state)
	var state_color: Color = AffectiveTypes.STATE_COLOR[new_state] as Color
	state_label.add_theme_color_override("font_color", state_color)
	# Mirrors the load chart's own per-state coloring instead of the theme's
	# generic gold fill - the meter and the chart should read as one signal.
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = state_color
	fill_style.set_corner_radius_all(3)
	load_meter.add_theme_stylebox_override("fill", fill_style)

func _on_params_changed(new_params: AdaptationParams) -> void:
	params_label.text = new_params.to_debug_string()
