# AffectiveFlowAI MVP — build log

Running log of what's implemented, appended per commit. See project plan for
the full spec and acceptance criteria.

## C0 — Reorg
Moved the 4 existing runner scripts/scenes into `game/`. No behavior change.

## C1 — AffectiveEngine stub + Debug HUD skeleton
Added the `AffectiveEngine` autoload (façade, no `class_name` — would collide
with its own autoload name), `AffectiveTypes` (state/event enums), and
`AdaptationParams` (typed, clamped struct). Added the Debug HUD (`ui/`),
toggled with F3, showing a hardcoded FLOW state and neutral params — nothing
live yet, this lands in C3/C4. `AffectiveEngine`'s telemetry/estimator/policy
pipeline is empty on purpose; wired up incrementally in later commits.

## C2 — Telemetry instrumentation (report-only)
Added `TelemetryCollector` (capped ring buffer + lifetime counter). Instrumented
`player.gd`: lane switches and swipes (now tracking real duration, velocity,
path straightness via `InputEventScreenDrag`/`InputEventMouseMotion`), and
idle detection (no meaningful input for 3s). Instrumented `main.gd`: HIT
events on obstacle collision, plus a "decision zone" mechanic that reuses the
existing `"scroll"` group loop to time reaction latency and count direction
reversals (hesitation) as obstacles approach the player row — bundled into
one DECISION event per obstacle, fired at collision or off-screen escape.
Zero new fields on `obstacle.gd`/`coin.gd`; zone bookkeeping lives entirely in
`main.gd` via node metadata. Nothing consumes this data yet (no FeatureWindow
until C3) — the Debug HUD's new raw event counter is the only visible effect.

## C3 — FeatureWindow + live tick
Added `FeatureWindow` (6s/20-event rolling window -> 8 normalized [0,1]
features) and a child `Timer` (150ms) inside `AffectiveEngine` that pulls new
events each tick and re-extracts the feature vector. No estimator yet (state
is still hardcoded FLOW, that's C4) - this commit is purely "raw telemetry in,
normalized numbers out." The Debug HUD now shows a live bar per feature,
visibly reacting to swipe speed/hesitation/hits/idling in real time.

## C4 — HeuristicLoadModel + dwell-gated state
Added `ICognitiveLoadModel` (swappable seam) and `HeuristicLoadModel`: fuses
the normalized features into a Cognitive Load Index via documented weights,
squashes through a sigmoid to get `load`, and classifies BOREDOM/FLOW/OVERWHELM
from load level + idle ratio (a documented v1 simplification of the full
challenge/skill 2D balance, which needs a difficulty history that only exists
once C6 wires AdaptationParams into gameplay). No personal baseline yet (C5)
- features feed the formula directly. `AffectiveEngine` now dwell-gates state
transitions (a predicted state must hold for ~600ms before it's accepted),
satisfying "sustained condition, not per-frame flicker" without a full HMM.
The Debug HUD's state label now really changes color, and shows a live load
meter + confidence percentage (confidence scales with window sample count).

## C5 — UserBaseline (per-user z-scoring)
Added `UserBaseline`: EWMA mean/variance per feature, epsilon-guarded so a
near-zero-variance early session can't blow up a z-score, persisted to
`user://baseline.json` and reloaded at startup. `HeuristicLoadModel` now
fuses clamped z-scores (deviation from this player's own rolling norm)
instead of the raw fixed-range-normalized features from C4 - same formula
shape, personalized input. Verified end-to-end: ran headless twice back to
back, confirmed `baseline.json` is written (~7.5s cadence) and correctly
reloaded/continued-adapting on the second run (mean/variance shifted as
expected with more accumulated samples, no errors).

## C6 — RuleBasedPolicy live in gameplay
Added `IAdaptationPolicy`/`RuleBasedPolicy`: targets a FLOW band, rate-limits
speed/spawn drift per tick (smooth, not jumpy), cooldowns on hint increments,
slow long-term progression while sustained in FLOW. `AffectiveEngine.get_params()`
now returns live values. `main.gd`'s original speed control migrates to
`_base_speed` (the natural pre-adaptation accel/hit-slowdown), with the final
`speed` = `_base_speed * params.speed_mult`; obstacle spawn gap divides by
`params.spawn_mult`; the 1-vs-2-lane block chance now scales with
`params.difficulty`. `player.gd` gained a pulsing hint beacon over the safe
lane when `hint_level > 0`, driven by a lane computed in `main.gd`'s spawn
logic. No game-over design preserved throughout. Verified via headless
import, Web export, and a 12s runtime smoke test (with no player input, the
stationary player accumulates hits, which exercised the OVERWHELM/hint path
under real conditions) - all clean.

## C7 — SessionLogger (GDPR-safe)
Added `SessionLogger`: opt-in, defaults OFF, anonymous UUID session id (not
tied to any identity), appends one JSON line per estimator tick to
`user://sessions/<uuid>.jsonl` (features, predicted state, load, confidence,
params, and per-tick HIT/ANSWER outcomes as labels for future training),
flushing each line since Web's IDBFS sync isn't instant. `list_sessions()`/
`export_session()`/`delete_all_sessions()` are ready for the consent UI
landing in C12; for now the Debug HUD has a dev-only F4 toggle (consent
still defaults off) showing a live "ticks logged" counter. Verified by
temporarily forcing consent on for a 10s run: confirmed a well-formed
65-line JSONL file with all expected fields and sensible values tracking
the live state/load/params (params visibly dipped toward OVERWHELM minimums
as hits accumulated, exactly as C6 designed), then confirmed a normal run
with consent left off creates zero session files.

## C8 — ContentPackLoader + sample Math Tunnels pack
Added `ContentPackLoader` (merges `res://content/` bundled packs, listed via
a committed `manifest.json` rather than DirAccess - unreliable for plain
files in an exported PCK/Web build - with `user://content/` authored packs
via real DirAccess; merge key is pack id, whole-pack replace) and the sample
`math_basics.json` pack (8 questions across difficulty tiers 0-4, 3 answers
each matching LANE_COUNT). `validate_pack()` is shared and ready for both
the game's load-time checks and the Content Editor's save-time checks in
C11. Not wired into gameplay yet (C9). The Debug HUD shows a "Packs loaded"
line. Verified with a temporary print statement that the bundled pack loads
correctly with all fields intact (JSON numbers arrive as floats - already
`int()`-cast in `validate_pack`), then removed it - clean import/export/
runtime.

## C9 — Math Tunnels live in-game
Added `AnswerToken` (neutral-looking until resolved - revealing correctness
upfront would defeat the point; only the hint beacon may reveal the correct
lane) and the `GameSession` autoload (holds `forced_pack_id` for the future
Play-test button). `main.gd` now spawns answer-gates on their own distance
accumulator, picking a question matching the current adaptation difficulty
tier (falling back to the whole pool if none match), spanning all 3 lanes
with no free pass (a deliberate, commented divergence from the obstacle
fairness invariant - every lane holds one answer). Passing the correct lane
reports an ANSWER telemetry event with correctness and time-to-answer; wrong
answers are telemetry-only (no HIT_FACTOR speed penalty - avoids double-
dipping between two separate error mechanics). `GATE_CLEARANCE_PX` keeps
obstacles/coins out of a gate's footprint. A new `QuestionLabel` shows the
current question text. Verified end-to-end: a 20s run with logging
temporarily forced on captured 4 ANSWER outcomes in the JSONL, correctly
independent from HIT outcomes, with state/load/params responding exactly as
C6 designed (confirmed one line with `assist:true`, `hint_level:1` under
sustained high error_rate) - then reverted the test hook and re-verified
clean import/export.

## C10 — Debug HUD complete
Replaced the raw "Events: N" counter with a real scrolling `RichTextLabel`
event log in `AffectiveEngine`: state transitions, HIT/ANSWER outcomes, and
hint/assist activations each append a timestamped line (capped at 15),
surfaced via `debug_event_log()`. Removed `TelemetryCollector.total_recorded()`
now that nothing reads it. The HUD (F3) now shows the full spec 4.8 picture:
color-coded state, load meter, confidence, 8 feature bars, live params,
logging/packs status, and the scrolling log. Verified by temporarily forcing
the panel visible for a 15s run and printing the log contents: confirmed a
readable, demo-ready sequence ("ANSWER correct" -> "HIT" -> "State ->
OVERWHELM" -> "Assist triggered" -> "Hint level -> 1" -> ...) before
reverting both temp changes - clean import/export.

## C11 — Content Editor + Main Menu
Added a minimal main menu (Play / Edit Content / Settings, the latter a
placeholder panel C12 fills in) and the Content Editor: pack list
(new/duplicate/delete - delete only works on authored `user://content/`
packs, bundled packs can only be overridden), pack meta fields (id/subject/
grade), question list (add/remove), and a question editor (text, 3 answers
matching LANE_COUNT with a shared-`ButtonGroup` correct-answer checkbox,
difficulty tier). Validation reuses `ContentPackLoader.validate_pack()` -
the same rules the game enforces at load time - surfaced as an inline red
message. Play-test saves first (so a scene change never loses in-progress
edits), then hands the pack to the runner via `GameSession.forced_pack_id`.
Import/Export use a desktop `FileDialog` in filesystem mode, explicitly
disabled with a tooltip on Web (it would otherwise silently browse the
sandboxed `user://` filesystem instead of the visitor's real disk).
`project.godot`'s `run/main_scene` now points at the menu - its second and
final change. Verified end-to-end: clean import/export/runtime with the
menu as main scene; separately pointed main scene at the editor and, since
headless can't click buttons, called its own handler methods directly to
simulate a full New Pack -> add question -> fill fields -> Save cycle -
confirmed the file was created, reloaded correctly with every field intact,
and deleted cleanly; then confirmed the validation path correctly rejects
a question with no correct answer marked (clear inline message, no file
written) - reverted the test hook and the temporary main-scene override.

## C12 — Consent UI (final commit)
The main menu's Settings panel now has the real, user-facing consent
checkbox (defaults unchecked, matching `SessionLogger`'s own default-off),
a live "N session(s) on disk" status line, an Export Sessions button
(desktop `FileDialog`, disabled+tooltipped on Web, bundles every session's
content into one JSON file), and a Delete All Sessions button gated behind
a `ConfirmationDialog` (irreversible, so it asks first). This replaces the
C7 dev-only F4 HUD toggle, which is removed - the HUD still shows live
logging status, just no longer toggles it. Verified end-to-end since
`AffectiveEngine`'s tick Timer runs regardless of which scene is active:
enabled consent, waited 2s, confirmed a session file appeared and the
status label updated; exported and confirmed the bundle contained the
session's real content; deleted and confirmed zero sessions remained;
disabled consent and confirmed it reports off again - all via the same
handler methods the UI buttons call. Clean import/export/runtime with the
temporary test code fully reverted (diff is purely additive).

This is the last of the 13 planned commits - the full AffectiveFlowAI MVP
loop (telemetry -> features -> heuristic estimator -> per-user baseline ->
rule-based adaptation -> Math Tunnels -> session logging -> debug HUD ->
content editor -> consent UI) is wired up end-to-end and has been verified
after every single commit via headless import, Web export, and targeted
runtime checks.

## Post-MVP tuning - reduced on-screen clutter
Feedback: the default playfield felt too crowded (obstacles, coins, and
answer-gates all spawning independently). Coins turned out to be the
biggest contributor - they had no connection to the telemetry/adaptation
loop at all (just a score counter) yet spawned roughly twice as often as
obstacles. Rather than removing obstacles (they feed the HIT-based
error_rate signal the estimator relies on), tuned spacing instead: coins
are now a rare bonus (500-900px gap, up from 150-300 - roughly a 3x
reduction, confirmed empirically via a temporary spawn counter: 14 coins
vs 5 over the same 15s window), obstacles get noticeably more breathing
room (340px gap floor and a steeper speed factor, up from 240/0.55), and
the clearance around Math Tunnels gates widened (340px, up from 260) for a
cleaner stage. Verified clean import/export/runtime after reverting all
temporary comparison instrumentation.
