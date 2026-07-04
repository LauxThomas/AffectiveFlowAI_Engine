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
