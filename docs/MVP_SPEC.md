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

## Post-MVP: obstacles off by default, ESC pause menu, question-repeat fix
Three follow-up changes:

- **Obstacles removed by default**, with a "Enable obstacles" checkbox in
  Settings (`GameSession.obstacles_enabled`, defaults false) to bring them
  back. Since this drops the HIT-based error signal for most players,
  `FeatureWindow.error_rate` now also counts wrong ANSWER events (the spec
  already calls these "an error signal"; only HIT was wired in before) -
  Math Tunnels alone still drives the error/decision signal.
- **ESC pause menu** (`ui/pause_menu.gd`/`.tscn`, instanced in `game/main.tscn`):
  toggles `get_tree().paused` and shows a Resume/Main Menu overlay. The
  overlay's `process_mode` is `ALWAYS` so it (and its buttons) keep
  receiving input while everything else - obstacles/coins/gates,
  AffectiveEngine's tick - correctly freezes.
- **Fixed a real bug: questions stopped changing.** `_spawn_answer_gate`
  filtered candidates to the current difficulty tier and called
  `pick_random()` with no memory - fine with a big pool, but since
  `RuleBasedPolicy` only moves the difficulty tier while sustained in
  BOREDOM/OVERWHELM (not FLOW, where most casual play sits), difficulty
  gets "stuck," and this pack has only 2 questions at the default tier (1).
  Independent random draws from a pool of 2 produced long runs of the same
  question by chance. Replaced with a shuffled-bag (`_pick_next_question`):
  never repeats a question until every other one in the matched pool (or
  the whole pack, as a fallback) has been asked, and avoids an immediate
  repeat right after a bag reset too.

Verified: forced `_pick_next_question(1)` ten times in a row and confirmed
zero consecutive repeats (`15-8=? / 6+7=? / 15-8=? / ...` alternating,
vs. the old code's unbounded-repeat risk); confirmed `obstacles_enabled`
defaults false; simulated an ESC keypress via `Input.parse_input_event`
twice and confirmed `get_tree().paused` toggled true then false. Clean
import/export/runtime after reverting all test instrumentation.

## feature/live-cognitive-load-chart branch (from main): live load history chart
User wanted to see current and past cognitive-load status live, not just an
instant reading. `AffectiveEngine` now keeps a rolling history (`MAX_HISTORY
= 600`, ~90s at 150ms/tick) of `load` paired with the accepted (dwell-gated)
state each tick, exposed via `debug_load_history()`/`debug_state_history()`.
New `ui/load_chart.gd` (`class_name LoadChart`, plain `Control` with a custom
`_draw()`) plots it as a line graph, color-coded per segment by the state at
that point (same colors as the rest of the HUD), with dashed reference lines
at the BOREDOM/OVERWHELM thresholds so the FLOW band is visible at a glance.
Wired into the Debug HUD (F3) right under the load meter; the HUD's panel
also gained a `ScrollContainer` wrapper since it was getting tall.

Verified by forcing the HUD panel visible and running for ~14s: confirmed
`load_history`/`state_history` grow in lockstep every tick (0 -> 94 entries),
values stayed sane (bounded in [0,1], visible movement as the estimator
reacted to real headless play), and zero runtime errors from the chart's
`_draw()` processing real accumulated data - confirms the draw code (segment
coloring via `AffectiveTypes.STATE_COLOR`, threshold lines) is sound. Clean
import/export/runtime after reverting the test instrumentation. Built on a
fresh branch off `main` (not the still-unmerged CLT/randomize branch) since
it doesn't touch any of the same files.
## fix/randomize-math-questions branch: real "same question" bug + always-center-lane bug
User report: questions were always "3+4=?" and "9-5=?", and the correct
answer was always in the center lane. Two root causes, both now fixed:

- `_pick_next_question`'s difficulty filter was a hard filter applied
  BEFORE checking what's unseen - since `RuleBasedPolicy` only moves the
  difficulty tier during sustained BOREDOM/OVERWHELM (never during normal
  FLOW play, and real play often drifts down to/gets stuck at low
  difficulty), the candidate pool could shrink to exactly the 2 questions
  tagged difficulty 0 ("3+4=?"/"9-5=?" in the sample pack) - the previous
  commit's anti-repeat bag was scoped to that same narrow 2-item pool, so
  it could alternate between them but never break out. Rewired: the
  shuffled-bag now runs over the WHOLE pack first (guaranteeing every
  distinct question surfaces before any repeat), with difficulty applied
  only as a preference within the not-yet-shown set.
- The correct answer's lane was just whatever slot it happened to occupy
  in the pack's `answers` array - the sample data has `correct_index: 1`
  on 6 of 8 questions (including both difficulty-0 ones), so it visually
  always landed center. `_spawn_answer_gate` now shuffles a per-spawn lane
  permutation so the correct answer's on-screen lane is randomized every
  time, independent of what the underlying data says.

Verified by calling `_pick_next_question(0)` twenty times in a row
(deliberately simulating the reported stuck-at-difficulty-0 scenario):
all 8 distinct pack questions appeared, and a parallel lane-shuffle check
showed the correct answer landing in all 3 lanes across the same 20 draws.
Clean import/export/runtime after reverting test instrumentation. Done on
a feature branch (not main), per updated workflow preference - the user
merges branches by hand.

## Same branch: retired lane-based answer-gates for a paused Cognitive Load Theory question overlay
Feedback: the lane-gate questions were far too fast for real content, and
the user wants to track flow state and show progressively more complex
Cognitive Load Theory questions (not math) with flow-state-driven
scaffolding, on a configurable interval (default 60s), pausing the game in
an overlay rather than requiring a lane dodge.

- Retired the whole lane-based mechanic: removed `AnswerToken` (deleted
  the script/scene entirely), the gate spawn-distance accumulator, and
  `GATE_SPAWN_MIN/MAX_GAP`/`GATE_CLEARANCE_PX`. Decision-zone tracking is
  now obstacle-only (the only remaining "scroll" member that needs it).
- New sample pack `content/cognitive_load_theory.json` (9 real CLT
  questions - Sweller's three load types, worked-example/split-attention/
  expertise-reversal effects, working-memory capacity - across difficulty
  0-4, each with an optional `hint` field), now the default active pack.
  `content_pack_loader.gd`'s schema quietly grew that optional `hint`
  field; the Content Editor got a matching Hint text field.
- New `ui/question_overlay.gd`/`.tscn` (`class_name QuestionOverlay`,
  `process_mode ALWAYS`): `main.gd` now runs a time accumulator (not a
  distance one) up to `GameSession.question_interval_sec` (default 60,
  adjustable via a new Settings SpinBox), then pauses the tree and calls
  `show_question(item, hint_level)`, reusing the existing shuffled-bag
  `_pick_next_question`. Scaffolding is driven by the live
  `AdaptationParams.hint_level` snapshotted at that moment: 0 = plain 3
  answers; 1 = adds the per-question hint text plus a subtle highlight on
  the correct answer; 2 = also removes one random wrong answer (down to 2
  choices). Answering reports the ANSWER telemetry event same as before,
  then unpauses.
- `ui/pause_menu.gd`'s ESC handler now checks `QuestionOverlay.is_showing()`
  first and no-ops if it's up, so the two paused-overlay systems can't
  fight over `get_tree().paused`.
- Main game HUD: replaced the "Treffer: N" hit counter with the live flow
  state (`State: FLOW/BOREDOM/OVERWHELM`, color-coded via the same
  `AffectiveTypes.STATE_COLOR` the debug HUD uses) - the `hits` counter
  itself was removed since nothing else read it.
- `FeatureWindow.error_rate`'s denominator now also counts `answer_count`
  (not just `decision_count`), since obstacles are off by default and
  gates are gone - `decision_count` alone would trend to 0 for most
  players and leave the ratio undefined.

Verified end-to-end in one run: pack loaded (9 items), state label showed
"State: FLOW | 430 px/s"; triggered the overlay directly at hint_level 0
(3 full answers, no hint, game paused), confirmed ESC during the overlay
correctly did nothing (guarded), answered it and confirmed the game
resumed; triggered at hint_level 1 (hint text appeared with real content,
still 3 answers) and hint_level 2 (down to 2 answers); confirmed ESC with
no overlay active correctly paused the game via the normal pause menu.
Clean import/export/runtime (game, menu, and content editor scenes) after
reverting all test instrumentation.

## fix/idle-reflects-missed-opportunities branch (from main): idle no longer means "game had nothing for you"
User feedback: `idle_ratio` was measured as "no input for 3s," regardless of
whether there was anything on screen to react to. With obstacles off by
default, that meant long ordinary stretches of play got flagged as
disengagement through no fault of the player - the game just wasn't asking
for anything.

Redefined idle to be about missed *opportunities*, not wall-clock silence:
- Removed the whole time-based idle timer from `player.gd`
  (`IDLE_THRESHOLD_USEC`, `_last_input_usec`, `_idle_reported`,
  `_mark_input_active()`) and `AffectiveTypes.EventType.IDLE` itself - both
  now fully unused.
- `main.gd`'s decision-zone tracking already recorded `latency_usec = -1`
  when a real obstacle's zone closed with zero input the whole time it was
  open (a genuine "ignored it" case) - `FeatureWindow.extract()` now derives
  `idle_ratio` directly from that: the fraction of actual decision-zone
  opportunities with no response at all, defaulting to a neutral 0 when
  there were no opportunities yet (same pattern as `answer_correct_rate`).

Verified: with obstacles off (default), 4s of zero input still measured
`idle_ratio = 0.0` (previously this would have climbed); with obstacles
forced on and zero input, `idle_ratio = 1.0` once real decision zones opened
and closed unanswered - confirming the signal now tracks genuine missed
opportunities instead of ordinary silence. Clean import/export/runtime.
Branched fresh off `main`.

## feature/self-report-mode branch (from main): manual NASA-TLX-style check-in
The technical brief's path to a trained model (§5) names a self-report pilot
as step 1 - real ground-truth labels to train/validate against, alongside
the behavioral telemetry. This branch builds the check-in itself, not the
pilot logistics around it.

- New `ui/self_report_overlay.gd`/`.tscn` (`class_name SelfReportOverlay`,
  `process_mode ALWAYS`, same paused-overlay pattern as `QuestionOverlay`):
  a lightweight NASA-TLX (1-9 scale, not the official 21-point form) - 6
  rows (Mental Demand, Physical Demand, Time Pressure, Performance, Effort,
  Frustration), each an `HSlider` with low/high anchor labels, built
  programmatically in `_ready()` from a typed `DIMENSIONS` const rather than
  hand-placed in the `.tscn`, since the set is fixed and this keeps the
  scene file small. Submit emits `finished(ratings)`; Skip emits
  `finished(null)` - one exit path either way, `main.gd` unpauses on both.
  Sliders reset to a neutral 5 every time it's opened.
- `main.tscn`'s `UI` layer gained a small, deliberately unobtrusive
  `SelfReportButton` ("Check-in", bottom-right corner, font size 11,
  `modulate` alpha 0.55) - manually triggered, not on a timer, since unlike
  the CLT question overlay this isn't gameplay content and shouldn't
  interrupt play uninvited. Being a normal child of `UI` (default
  `process_mode`), it naturally stops receiving input whenever the tree is
  already paused by the question overlay or pause menu - no extra guard
  needed for that direction. The reverse direction (ESC while self-report is
  open) needed one: `pause_menu.gd`'s ESC handler now also checks
  `SelfReportOverlay.is_showing()`, same pattern as its existing
  `QuestionOverlay` guard.
- `SessionLogger.log_self_report()` (new) writes a `"kind": "self_report"`
  JSONL line - ratings plus the estimator's own `state`/`load`/`confidence`/
  `features` snapshot at that same moment, so the two can be compared
  directly. `log_tick()` gained a matching `"kind": "tick"` field so the two
  line types are unambiguous when parsing a session file. Same file, same
  opt-in consent gate as regular tick logging - the overlay itself always
  works (useful as self-reflection even with logging off), only persists if
  `SessionLogger.is_enabled()`. `AffectiveEngine.log_self_report(ratings)` is
  the new façade method `main.gd` calls; it forwards the engine's own
  `_last_state`/`_last_load`/`_last_confidence`/`_last_features` rather than
  recomputing anything.

Verified via a temporary headless SceneTree test script (`-s` entry point,
autoloads referenced via `get_node("/root/AffectiveEngine")` since bare
autoload identifiers aren't resolved for a script that IS the main loop):
instanced `main.tscn`, forced logging consent on, confirmed all 6 sliders
build, pressed the check-in button and confirmed the overlay shows and the
tree pauses, set two slider values, submitted, confirmed the overlay hides
and the tree unpauses, then read the session file back and confirmed a
`kind: self_report` line exists with the exact submitted ratings intact.
Deleted only that one test-created session file (not a blanket
`delete_all_sessions()` - there's no real accumulated session data on this
machine yet, confirmed first, but the distinction matters for anyone running
this test with real data present). Clean headless import and Web export.
Branched fresh off `main`.

## Same branch: optional pilot-study upload (Supabase) - IMPORTANT: changes the "no network calls" claim
User asked how to actually get pilot/evaluation data off-device, since
`SessionLogger` only writes to `user://` (manual Export button is the only
existing path). Added an opt-in upload path, scoped as narrowly as possible:

- New `affective/pilot_upload_service.gd` (autoload `PilotUploadService`, no
  `class_name`): holds a Supabase project URL + anon key (entered by the
  researcher in Settings, persisted to `user://pilot_config.json`, not
  committed to git - the repo ships with zero credentials in it), and an
  `enabled` flag. `is_enabled()` requires both a saved config AND the
  checkbox on - inert otherwise.
- **Deliberately uploads self-report check-ins only, never the per-150ms
  tick log.** A check-in is a handful of values the player chose to submit;
  the full tick stream is continuous behavioral telemetry and stays
  local-only exactly as before. `AffectiveEngine.log_self_report()` now
  calls both `_logger.log_self_report()` (existing, local, unchanged) and
  `PilotUploadService.upload_self_report()` (new, additional, no-ops unless
  configured+enabled) - the local save was never conditional on the remote
  one, so a failed/offline upload can't lose the local copy.
- Upload is a single fire-and-forget `HTTPRequest` POST to
  `<url>/rest/v1/pilot_sessions`, keyed by a persistent-but-anonymous
  per-install participant id (`user://pilot_participant_id.txt`, generated
  once, unrelated to `SessionLogger`'s own per-session UUIDs) so a
  researcher can correlate one participant's check-ins across multiple play
  sessions.
- Settings gained a "Pilot study upload" section: URL/key fields (key field
  is `secret = true`), a Save button, an upload checkbox, and a status
  label. Text explicitly says this is for researchers/pilot testers and
  requires session logging to also be on.

**This measurably changes a claim in `docs/TECHNICAL_BRIEF.md`** ("no
network calls anywhere in the codebase... a hard architectural constraint").
That's no longer literally true once this ships - it's now true of the
*default* configuration, not the codebase unconditionally. The brief needs a
correction, not just an addition; flagged to the user directly rather than
silently patched, since this was stated as a hard technical/investor claim.

Verified: headless import and Web export both clean (`PilotUploadService`
registers as an autoload with no errors). Runtime test (temporary `-s`
script, same `get_node("/root/...")` pattern as the self-report test):
confirmed default state is unconfigured/disabled, confirmed
`set_config()`/`set_enabled()` round-trip through `is_configured()`/
`is_enabled()`, and confirmed calling `log_self_report()` with a pointed-at
a non-existent Supabase project doesn't throw or block (fire-and-forget, as
designed) - then reset the local config back to empty so no test state was
left in `user://`.
