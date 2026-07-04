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
