extends Node2D

# ─── Tuning ────────────────────────────────────────────────
const LANE_COUNT  := 3
const START_SPEED := 430.0   # vertikale Scrollgeschwindigkeit (px/s)
const MAX_SPEED   := 1050.0
const SPEED_GAIN  := 14.0     # wird über Zeit schneller
const HIT_FACTOR  := 0.6      # speed *= HIT_FACTOR bei Treffer
const MIN_SPEED   := 190.0    # Untergrenze -> stoppt nie
const SCORE_RATE  := 0.02
const DECISION_ZONE_Y := 300.0   # px lead distance above the player row
const OBSTACLE_GAP_FLOOR := 340.0   # px, up from 240 - fewer waves on screen at once
const OBSTACLE_GAP_SPEED_FACTOR := 0.65   # up from 0.55 - gap grows faster with speed
const COIN_GAP_MIN := 500.0   # up from 150 - coins are a rare bonus, not a constant stream
const COIN_GAP_MAX := 900.0   # up from 300

const OBSTACLE := preload("res://game/obstacle.tscn")
const COIN     := preload("res://game/coin.tscn")

# Hindernis-Presets: Breite / Höhe (Breite < Lane-Breite!)
const OB_PRESETS := [
	{ "w": 130, "h": 150 },   # "Zug"
	{ "w": 130, "h": 74 },    # Barriere
	{ "w": 96,  "h": 96 },    # Kiste
]

# ─── State ─────────────────────────────────────────────────
var _base_speed := START_SPEED   # natural pre-adaptation speed; final speed = _base_speed * params.speed_mult
var speed := START_SPEED
var score := 0.0
var coins := 0
var _dist_ob := 400.0
var _dist_coin := 500.0
var _scroll := 0.0
var _player_y := 0.0
var _lanes: Array[float] = []
var _open_zone: Node2D = null
var _hint_free_lane: int = -1
var _pack_items: Array = []
var _asked_questions: Array[String] = []   # shuffled-bag: no repeat until the pool is exhausted
var _question_timer_accum: float = 0.0   # counts up to GameSession.question_interval_sec

@onready var player: Node2D = $Player
@onready var score_label: Label = $UI/ScoreLabel
@onready var coins_label: Label = $UI/CoinsLabel
@onready var state_label: Label = $UI/StateLabel
@onready var self_report_button: Button = $UI/SelfReportButton
@onready var question_overlay: QuestionOverlay = $QuestionOverlay
@onready var self_report_overlay: SelfReportOverlay = $SelfReportOverlay

func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	_player_y = vp.y - 150.0
	for i in LANE_COUNT:
		_lanes.append(_lane_x(i, vp.x))
	player.position = Vector2(_lanes[1], _player_y)
	if player.has_method("setup"):
		player.setup(_lanes, 1)
	if player.has_signal("lane_switched"):
		player.lane_switched.connect(_on_player_lane_switched)
	question_overlay.answer_chosen.connect(_on_overlay_answer_chosen)
	self_report_button.pressed.connect(_on_self_report_button_pressed)
	self_report_overlay.finished.connect(_on_self_report_finished)
	_load_active_pack()
	_update_ui()

func _on_self_report_button_pressed() -> void:
	get_tree().paused = true
	self_report_overlay.show_report()

func _on_self_report_finished(ratings: Variant) -> void:
	if ratings != null:
		AffectiveEngine.log_self_report(ratings as Dictionary)
	get_tree().paused = false

func _load_active_pack() -> void:
	var forced_id: String = GameSession.consume_forced_pack()
	if not forced_id.is_empty():
		GameSession.active_pack_id = forced_id
	var packs: Dictionary = ContentPackLoader.load_merged_packs()
	var pack: Variant = packs.get(GameSession.active_pack_id, {})
	if typeof(pack) != TYPE_DICTIONARY:
		return
	var items: Variant = (pack as Dictionary).get("items", [])
	if typeof(items) == TYPE_ARRAY:
		_pack_items = items as Array

func _lane_x(i: int, w: float) -> float:
	return w * (float(i) + 0.5) / float(LANE_COUNT)

func _process(delta: float) -> void:
	var params: AdaptationParams = AffectiveEngine.get_params()

	_base_speed = minf(_base_speed + SPEED_GAIN * delta, MAX_SPEED)
	speed = _base_speed * params.speed_mult
	var move := speed * delta
	score += move * SCORE_RATE
	_scroll += move
	var vp := get_viewport_rect().size

	# alles Scrollende nach unten bewegen + aufräumen
	for node in get_tree().get_nodes_in_group("scroll"):
		var n := node as Node2D
		if n == null:
			continue
		var prev_y := n.position.y
		n.position.y += move
		if n.is_in_group("decision_zone"):
			_update_zone_tracking(n, prev_y, n.position.y)
		if n.position.y > vp.y + 160.0:
			_close_zone(n)   # "avoided harmlessly" resolution path
			n.queue_free()

	# Hindernisse - off by default (Settings toggle); Math Tunnels gates
	# alone still drive the decision/error signal.
	if GameSession.obstacles_enabled:
		_dist_ob -= move
		if _dist_ob <= 0.0:
			_spawn_obstacles(params.difficulty)
			var gap: float = maxf(OBSTACLE_GAP_FLOOR, speed * OBSTACLE_GAP_SPEED_FACTOR) / maxf(params.spawn_mult, 0.01)
			_dist_ob = gap + randf_range(60.0, 260.0)

	# Münzen - a rare bonus, not a constant stream (no telemetry purpose,
	# so kept sparse deliberately to reduce on-screen clutter)
	_dist_coin -= move
	if _dist_coin <= 0.0:
		_spawn_coin()
		_dist_coin = randf_range(COIN_GAP_MIN, COIN_GAP_MAX)

	if player.has_method("set_hint_lane"):
		player.set_hint_lane(_hint_free_lane if params.hint_level > 0 else -1)

	# Periodic paused question overlay - interval adjustable in Settings.
	# _process stops running entirely once the tree is paused, so this
	# can't re-trigger while the overlay is already up.
	_question_timer_accum += delta
	if _question_timer_accum >= GameSession.question_interval_sec:
		_question_timer_accum = 0.0
		_trigger_question_overlay(params.difficulty, params.hint_level)

	_update_ui()
	queue_redraw()

func _spawn_obstacles(difficulty: int) -> void:
	# 1 oder 2 Lanes blockieren -> es bleibt IMMER mind. 1 Lane frei.
	# 2-lane chance scales with the adaptation difficulty tier (denser/harder
	# when the estimator pushes toward BOREDOM's higher difficulty).
	var two_lane_chance: float = clampf(0.2 + 0.15 * float(difficulty), 0.1, 0.7)
	var count := 2 if randf() < two_lane_chance else 1
	var lanes: Array[int] = [0, 1, 2]
	lanes.shuffle()
	for k in count:
		var lane := lanes[k]
		var p: Dictionary = OB_PRESETS.pick_random()
		var ob := OBSTACLE.instantiate() as Obstacle
		ob.body_width = float(p.w)
		ob.body_height = float(p.h)
		ob.position = Vector2(_lanes[lane], -float(p.h))
		ob.add_to_group("scroll")
		ob.add_to_group("decision_zone")
		ob.hit.connect(_on_obstacle_hit.bind(ob))
		add_child(ob)
	_hint_free_lane = lanes[count] if count < LANE_COUNT else -1

func _spawn_coin() -> void:
	var lane := randi() % LANE_COUNT
	var c := COIN.instantiate() as Coin
	c.position = Vector2(_lanes[lane], -40.0)
	c.add_to_group("scroll")
	c.collected.connect(_on_coin_collected)
	add_child(c)

# Shuffled-bag question selection over the WHOLE pack: guarantees every
# distinct question is shown before any repeat. Difficulty is a soft
# preference applied only within the not-yet-shown set, never a hard
# filter - an earlier version filtered candidates down to an exact
# difficulty match first, which could shrink the pool to just 1-2
# questions whenever the adaptation policy's difficulty tier got stuck
# (RuleBasedPolicy only moves it while sustained in BOREDOM/OVERWHELM, not
# FLOW, where most casual play sits) - so the player kept seeing the same
# couple of questions and it read as "the questions never change."
func _pick_next_question(difficulty: int) -> Dictionary:
	var unseen: Array = _pack_items.filter(
		func(item_variant: Variant) -> bool:
			return typeof(item_variant) == TYPE_DICTIONARY and not _asked_questions.has(String((item_variant as Dictionary).get("question", "")))
	)
	if unseen.is_empty():
		var last_question: String = _asked_questions.back() if not _asked_questions.is_empty() else ""
		_asked_questions.clear()
		unseen = _pack_items.filter(
			func(item_variant: Variant) -> bool:
				return typeof(item_variant) == TYPE_DICTIONARY and String((item_variant as Dictionary).get("question", "")) != last_question
		) if _pack_items.size() > 1 else _pack_items

	var matched: Array = unseen.filter(
		func(item_variant: Variant) -> bool:
			return int((item_variant as Dictionary).get("difficulty", 0)) == difficulty
	)
	var pool: Array = matched if not matched.is_empty() else unseen

	var chosen_variant: Variant = pool.pick_random()
	if typeof(chosen_variant) != TYPE_DICTIONARY:
		return {}
	var chosen: Dictionary = chosen_variant as Dictionary
	_asked_questions.append(String(chosen.get("question", "")))
	return chosen

# Pauses the game and shows the periodic question overlay - scaffolding
# (hint text, answer elimination, correct-answer highlight) is driven by
# the live hint_level snapshotted here, same idea as the old lane-hint
# beacon. Resolution comes back via the overlay's answer_chosen signal.
func _trigger_question_overlay(difficulty: int, hint_level: int) -> void:
	if _pack_items.is_empty():
		return
	var item: Dictionary = _pick_next_question(difficulty)
	if item.is_empty():
		return
	get_tree().paused = true
	question_overlay.show_question(item, hint_level)

func _on_overlay_answer_chosen(correct: bool, question_id: String, time_to_answer_ms: float) -> void:
	AffectiveEngine.report_event(AffectiveTypes.EventType.ANSWER, {
		"question_id": question_id,
		"correct": correct,
		"time_to_answer_ms": time_to_answer_ms,
	})
	# Wrong answers are a telemetry-only error signal - they do NOT also
	# trigger HIT_FACTOR's speed penalty (avoids double-dipping between two
	# separate error mechanics; scaffolding comes purely through the
	# AdaptationEngine reacting to the resulting OVERWHELM-leaning state).
	get_tree().paused = false

func _on_obstacle_hit(ob: Obstacle) -> void:
	_close_zone(ob)
	AffectiveEngine.report_event(AffectiveTypes.EventType.HIT, {})
	_base_speed = maxf(_base_speed * HIT_FACTOR, MIN_SPEED)   # abbremsen statt stoppen
	if player.has_method("flash"):
		player.flash()
	_update_ui()

func _on_coin_collected() -> void:
	coins += 1
	_update_ui()

# ─── Decision zone: reaction latency + hesitation ──────────
# v1 simplification: tracks one open zone at a time via Node metadata
# (obstacle.gd/answer_token.gd stay untouched). Spawn gaps are wider than
# DECISION_ZONE_Y, so overlapping zones are rare; the rare case is skipped
# defensively rather than handled.
func _update_zone_tracking(n: Node2D, prev_y: float, new_y: float) -> void:
	var threshold: float = _player_y - DECISION_ZONE_Y
	if prev_y < threshold and new_y >= threshold and not n.has_meta("_zone_entered_usec"):
		if _open_zone != null:
			return
		n.set_meta("_zone_entered_usec", Time.get_ticks_usec())
		n.set_meta("_zone_first_input_usec", 0)
		n.set_meta("_zone_last_dir", 0)
		n.set_meta("_zone_reversals", 0)
		_open_zone = n

func _on_player_lane_switched(dir: int, usec: int) -> void:
	if _open_zone == null:
		return
	var last_dir: int = int(_open_zone.get_meta("_zone_last_dir"))
	if last_dir != 0 and dir == -last_dir:
		_open_zone.set_meta("_zone_reversals", int(_open_zone.get_meta("_zone_reversals")) + 1)
	_open_zone.set_meta("_zone_last_dir", dir)
	if int(_open_zone.get_meta("_zone_first_input_usec")) == 0:
		_open_zone.set_meta("_zone_first_input_usec", usec)

func _close_zone(n: Node2D) -> void:
	if not n.has_meta("_zone_entered_usec"):
		return
	var entered_usec: int = int(n.get_meta("_zone_entered_usec"))
	var first_input_usec: int = int(n.get_meta("_zone_first_input_usec"))
	# -1 = zero input the whole time this zone was open - a real obstacle
	# was there and got ignored. FeatureWindow uses this (not wall-clock
	# silence) to compute idle_ratio.
	var latency_usec: int = (first_input_usec - entered_usec) if first_input_usec > 0 else -1
	AffectiveEngine.report_event(AffectiveTypes.EventType.DECISION, {
		"latency_usec": latency_usec,
		"hesitation_reversals": int(n.get_meta("_zone_reversals")),
		"zone_kind": "obstacle",   # the only decision-zone member now that answer-gates are retired
	})
	if _open_zone == n:
		_open_zone = null

func _update_ui() -> void:
	score_label.text = "Score: %d" % int(score)
	coins_label.text = "Coins: %d" % coins
	var state: AffectiveTypes.CognitiveState = AffectiveEngine.current_state()
	state_label.text = "State: %s  |  %d px/s" % [AffectiveTypes.state_name(state), int(speed)]
	state_label.add_theme_color_override("font_color", AffectiveTypes.STATE_COLOR[state] as Color)

# ─── Straße zeichnen ───────────────────────────────────────
# Colors match the project-wide identity (ui/app_theme.gd): AppTheme.INK_2
# for the asphalt (slightly lighter than pure UI black, keeps the game
# world visually distinct from UI chrome) and AppTheme.GOLD for the edges,
# already what this drew before the identity pass formalized it.
func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), AppTheme.INK_2)               # Asphalt
	draw_rect(Rect2(0, 0, 6, vp.y), AppTheme.GOLD)                   # Rand links
	draw_rect(Rect2(vp.x - 6, 0, 6, vp.y), AppTheme.GOLD)            # Rand rechts

	# gestrichelte Lane-Trenner, nach unten scrollend
	var period := 74.0
	var off := fmod(_scroll, period)
	for d in range(1, LANE_COUNT):
		var line_x := vp.x * float(d) / float(LANE_COUNT)
		var y := -period + off
		while y < vp.y:
			draw_rect(Rect2(line_x - 3.0, y, 6.0, 44.0), AppTheme.PAPER)
			y += period
