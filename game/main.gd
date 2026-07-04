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
var hits := 0
var coins := 0
var _dist_ob := 340.0
var _dist_coin := 220.0
var _scroll := 0.0
var _player_y := 0.0
var _lanes: Array[float] = []
var _open_zone: Node2D = null
var _hint_free_lane: int = -1

@onready var player: Node2D = $Player
@onready var score_label: Label = $UI/ScoreLabel
@onready var coins_label: Label = $UI/CoinsLabel
@onready var hits_label: Label = $UI/HitsLabel

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
	_update_ui()

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

	# Hindernisse
	_dist_ob -= move
	if _dist_ob <= 0.0:
		_spawn_obstacles(params.difficulty)
		var gap: float = maxf(240.0, speed * 0.55) / maxf(params.spawn_mult, 0.01)
		_dist_ob = gap + randf_range(40.0, 220.0)

	# Münzen
	_dist_coin -= move
	if _dist_coin <= 0.0:
		_spawn_coin()
		_dist_coin = randf_range(150.0, 300.0)

	if player.has_method("set_hint_lane"):
		player.set_hint_lane(_hint_free_lane if params.hint_level > 0 else -1)

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

func _on_obstacle_hit(ob: Obstacle) -> void:
	_close_zone(ob)
	AffectiveEngine.report_event(AffectiveTypes.EventType.HIT, {})
	hits += 1
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
	var latency_usec: int = (first_input_usec - entered_usec) if first_input_usec > 0 else -1
	AffectiveEngine.report_event(AffectiveTypes.EventType.DECISION, {
		"latency_usec": latency_usec,
		"hesitation_reversals": int(n.get_meta("_zone_reversals")),
		"zone_kind": "obstacle" if n is Obstacle else "answer_gate",
	})
	if _open_zone == n:
		_open_zone = null

func _update_ui() -> void:
	score_label.text = "Score: %d" % int(score)
	coins_label.text = "Coins: %d" % coins
	hits_label.text = "Treffer: %d  |  %d px/s" % [hits, int(speed)]

# ─── Straße zeichnen ───────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color("343841"))          # Asphalt
	draw_rect(Rect2(0, 0, 6, vp.y), Color("f0c419"))             # Rand links
	draw_rect(Rect2(vp.x - 6, 0, 6, vp.y), Color("f0c419"))      # Rand rechts

	# gestrichelte Lane-Trenner, nach unten scrollend
	var period := 74.0
	var off := fmod(_scroll, period)
	for d in range(1, LANE_COUNT):
		var line_x := vp.x * float(d) / float(LANE_COUNT)
		var y := -period + off
		while y < vp.y:
			draw_rect(Rect2(line_x - 3.0, y, 6.0, 44.0), Color("cfd3da"))
			y += period
