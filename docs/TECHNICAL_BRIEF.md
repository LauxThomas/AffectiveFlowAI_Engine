# AffectiveFlowAI Engine — Technical Brief

*Last updated: 2026-07-15 (corrected §1/§7 network-calls claim after the optional pilot-upload path was added). This document is kept current as the system evolves — treat it as the canonical external-facing technical description, distinct from `docs/MVP_SPEC.md` (the internal commit-by-commit build log).*

**Visual identity reference:** https://claude.ai/code/artifact/e10daf25-67b5-43b7-b762-8fc7f30dc604 — palette, type, and screen mockups derived from the product's own signal (the live tri-state load chart) and existing in-game colors. A design reference page, not a `.fig` file; intended as direct creative direction for a designer, or as the spec to rebuild from in Figma. Now public. It's also being self-hosted on the project's own GitHub Pages deployment (`<pages-url>/design-reference/`, branch `feature/design-reference-pages`, not yet merged) so it doesn't depend on the artifact link staying reachable — see §11.

## 1. What it is

AffectiveFlowAI Engine is a real-time cognitive-load estimation and adaptive-difficulty layer, built on top of a lane-runner game (Godot 4.7, Web-exportable, mobile-portable). It reads *how* a learner interacts — swipe dynamics, reaction latency, hesitation, error patterns — and uses that to keep them in a flow state while delivering real educational content (currently Cognitive Load Theory itself, taught through the game that's measuring it).

Everything runs **entirely on-device by default**. Out of the box there is no server, no account system, no network call anywhere the game runs, no camera/microphone/biometric hardware. *Correction from an earlier version of this doc, which stated this as an unconditional codebase-wide constraint: as of `feature/self-report-mode`, there is one narrow, explicit exception — see §7.*

## 2. The core loop

```
game input → TelemetryCollector → FeatureWindow → CognitiveLoadEstimator → AdaptationEngine
                                                          ↓                        ↓
                                                   {state, load,          speed / spawn density /
                                                    confidence}           difficulty / hint level
                                                          ↓
                                                   SessionLogger (opt-in, on-device, anonymous)
```

Every ~150ms, the last 6 seconds of interaction get compressed into 8 normalized features, fed through the estimator, and turned into a `{state, load, confidence}` reading. That reading drives the game's difficulty in real time and gates a periodic paused question overlay (Cognitive Load Theory content today), with the amount of scaffolding shown scaled to how loaded the learner currently is.

## 3. Scientific grounding

The estimator's feature set and fusion logic are not arbitrary — they're informed by established findings in cognitive load and motor-control research:

- **Cognitive Load Theory** (Sweller, 1988 onward): the three-way split of intrinsic, extraneous, and germane load, and the idea that instructional scaffolding should track load rather than a fixed difficulty curve, directly motivates the adaptation policy's target: hold the learner in a moderate-load band, not minimize load outright.
- **Yerkes-Dodson law** (inverted-U relationship between arousal/load and performance): the classification isn't "low load = good" — both very low load (BOREDOM) and very high load (OVERWHELM) are treated as states to correct out of, with FLOW as the productive middle band.
- **Reaction-time variability as a load marker**: RT coefficient-of-variation and the exponential tail of the RT distribution (ex-Gaussian τ) are established behavioral markers of attentional lapses and rising cognitive load in the psychology literature. The estimator's `reaction_latency_mean` feature is a v1 proxy for this (a full ex-Gaussian fit is deferred as too heavy for a 150ms tick; a documented simpler substitute is used instead — see §6).
- **Submovements and jerk as uncertainty markers**: motor-control research treats the number of corrective submovements and the jerk (3rd derivative of position) in a movement as indicators of hesitation and reduced confidence, versus a single fast "ballistic" motion when a decision is confident. `swipe_velocity_var` is a v1 proxy for this.

This grounding is documented directly in the source (`affective/models/heuristic_load_model.gd`), not just asserted here.

## 4. Current implementation status — be precise about this

**What exists today is a transparent v1 heuristic, not a trained model.** This is stated plainly in the code and should be stated plainly everywhere else too. Concretely:

- 8 features are extracted per tick: swipe velocity mean/variance, reaction latency, hesitation rate (direction reversals), error rate (obstacle hits + wrong answers), answer-correctness rate, lane-switch rate, and idle ratio (redefined to mean *missed real decision opportunities*, not wall-clock silence — see §7).
- Each feature is compared against **that specific player's own rolling average** (an EWMA baseline, α=0.05, epsilon-guarded against early-session noise), producing a z-score. This personalization is the key differentiator: "high load" is deviation from *your* norm, not a fixed global threshold.
- The z-scores are combined in a fixed weighted sum (weights: reaction latency 1.0, hesitation 1.0, swipe variance 0.8, error rate 1.2, wrong-answer rate 1.0, idle 0.4, throughput −0.6) and squashed through a sigmoid (gain 4.0) to produce a `load` value in [0, 1].
- Classification: `load > 0.65` → OVERWHELM, `load < 0.35` and idle-ratio above threshold → BOREDOM, otherwise FLOW. A predicted state must hold for 4 consecutive ticks (~600ms) before it's accepted, so the displayed state doesn't flicker.
- **The weights above are hand-picked, not learned.** They are a reasonable, literature-informed starting point — nothing more.

## 5. Path to real, on-device machine learning

The architecture was deliberately built with this transition in mind — it is a swap, not a rebuild:

- `ICognitiveLoadModel.predict(features) -> {state, load, confidence}` is already the abstraction the game code depends on. `HeuristicLoadModel` is one implementation; a trained model is another, dropped in without touching game code.
- `SessionLogger` already collects the exact data a future model would train on — the full feature vector, predicted state, load, params, and per-tick outcomes (hit/answer-correct) as candidate labels — opt-in, anonymous UUID session id, on-device only.

**Concrete next steps to get from heuristic to trained model:**

1. Run a small structured pilot (10–30 people) with self-report check-ins (a lightweight, 1–9-scale NASA-TLX — Mental/Physical/Temporal Demand, Performance, Effort, Frustration) during play, to get real ground-truth labels alongside the behavioral telemetry. **Built** (`feature/self-report-mode`): a small manual "Check-in" button in the run HUD, not a periodic auto-prompt — the player decides when to rate, so it never interrupts play uninvited.
2. Train a small model offline (logistic regression, a shallow MLP, or gradient-boosted trees are all plenty for 8 input features — no need for anything heavier).
3. Validate against held-out sessions and report a real correlation number against the self-report instrument.
4. Export just the learned weights (a small array of floats) and implement inference as plain matrix multiplication in GDScript — no ML runtime, no native plugin, no per-platform build complexity. This keeps everything on-device by construction and works identically across desktop, Web, and mobile exports.
5. Swap it in behind the existing `ICognitiveLoadModel` interface; keep the heuristic available as a fallback/comparison baseline.
6. As real usage accumulates via the same opt-in logging pipeline, periodically retrain.

A heavier on-device runtime (ONNX Runtime Mobile, TensorFlow Lite via a native GDExtension) would only become relevant if the model needs to consume raw signals (e.g. full swipe trajectories) instead of hand-engineered features — not needed for the current feature set, and it would cost Web-export simplicity, so it's a later option, not a starting point.

## 6. Documented v1 simplifications (so nobody mistakes them for oversights)

- Ex-Gaussian τ (RT tail parameter) is approximated by `P90(RT) − median(RT)` rather than a full distribution fit, which would be too costly to run every 150ms.
- Jerk and submovement count aren't separately computed yet; `swipe_velocity_var` stands in as a cheaper proxy for the same "erratic/corrective movement" signal.
- The full Yerkes-Dodson challenge-vs-skill 2D balance is simplified to a 3-band load threshold plus an idle/engagement check for boredom specifically, since true challenge-vs-skill modeling needs a difficulty history that only becomes meaningful once adaptive difficulty has been live for a while.

## 7. Data & privacy posture

- **Default build: no network calls, no accounts, no server.** No camera, microphone, or biometric hardware — ever, in any configuration.
- Session logging (the full behavioral telemetry stream) is **opt-in, default off**, uses an anonymous random UUID never tied to identity, and stores data only in the app's local on-device storage (`user://`). This is unconditional — there is no code path that sends the tick log anywhere.
- Users can export or permanently delete all logged sessions from Settings at any time.
- "Idle" in the feature set specifically means *ignored a real in-game decision*, not generic silence — a deliberate fix to avoid mislabeling ordinary quiet play as disengagement.
- **The one exception, added in `feature/self-report-mode`:** an optional pilot-study upload. This project's own pilot Supabase URL + anon key are baked into `pilot_upload_service.gd` as defaults (so testers don't hand-type them), but **uploading itself is still off until someone explicitly turns on the "Upload check-ins to pilot study" checkbox in Settings** — a build with these defaults compiled in sends nothing on its own. Settings can also point it at a different project entirely. When active, it uploads **only self-report check-in ratings** (the values the player explicitly typed in and submitted), each paired with the estimator's own state/load/confidence/feature reading at that moment, plus a persistent-but-anonymous per-install id (unrelated to any identity, exists only to let a researcher group one participant's check-ins together). It never uploads the continuous tick log — that stays exactly as on-device-only as described above. The anon key is Supabase's new "publishable" key type, explicitly meant to be shipped client-side; the actual protection is the `pilot_sessions` table's Row Level Security policy, which grants `anon` insert-only (no select/update/delete) — see the setup below. Practically: this is a pilot-testing tool for a small, explicitly recruited group of participants, not something that activates meaningfully for the general public build (the checkbox still has to be turned on).

Net effect: the general-release build's privacy posture is unchanged from earlier versions of this document. The exception exists to make the §5 pilot study logistically possible, and is scoped as narrowly as the actual research need (a handful of self-reported ratings per session, not raw behavioral data).

## 8. Why this is defensible (the honest version)

The estimator's formula shape is not the moat — it's built on published, citable theory, and a technically sophisticated competitor could replicate the formula shape in an afternoon. The actual moat is:

1. **The accumulated, per-user adaptive baseline** — it only forms from real interaction history with a specific player and cannot be copied without that history.
2. **The labelled dataset** `SessionLogger` is quietly building, which is what a real trained model (§5) will be trained and validated on.
3. **Weights and thresholds once tuned on a validated study** — currently hand-picked; tuning them against real self-report data is exactly the pilot study described in §5.

A cloned formula with no accumulated personalization data behind it is an untuned, unpersonalized guess.

## 9. Architecture summary

- `affective/` — game-agnostic engine (telemetry, feature extraction, estimator, adaptation policy, session logging). Designed to be extractable as a standalone SDK later.
- `game/` — the runner itself, which only ever talks to `affective/` through a single autoload façade (`AffectiveEngine`) and never reaches into its internals.
- Every major component sits behind a swappable interface: `ICognitiveLoadModel` (estimator), `IAdaptationPolicy` (difficulty/scaffolding logic) — both explicitly designed so a trained model / learned policy can replace the current heuristic without touching game code.

## 10. Status snapshot

| Area | Status |
|---|---|
| Telemetry + feature extraction | Live |
| Cognitive load estimator | v1 heuristic, live; not yet trained |
| Per-user baseline personalization | Live |
| Adaptive difficulty / scaffolding | Live |
| Educational content (Cognitive Load Theory) | Live, paused question overlay, flow-state-scaffolded |
| Opt-in on-device data logging | Live |
| Self-report check-in (pilot labels) | Live — manual button, `feature/self-report-mode`, not yet merged |
| Optional pilot-study upload (Supabase) | Live but unconfigured by default — same branch; needs a researcher-provided project, see §7 |
| Trained on-device ML model | Not started — data pipeline ready, needs a labelled pilot (§5) |
| Visual/UI design pass | In progress — `ui/app_theme.gd` Theme system live (branch `feature/visual-identity-theme`, not yet merged); reference doc self-hosting in progress — see §11 |

## 11. Visual identity reference — access note

The reference is now public at the artifact link above, and is additionally being self-hosted at `<pages-url>/design-reference/` via `docs/design-reference/index.html` and a small addition to `.github/workflows/deploy.yml` (branch `feature/design-reference-pages`) — belt-and-suspenders, since an artifact link's public/private state can always be flipped back by whoever owns it, while a copy in this repo's own Pages deployment is not exposed to that.

Separately, `feature/visual-identity-theme` (also not yet merged) took a first pass at applying this reference's palette directly in the game: a programmatically-built Godot `Theme` resource (`ui/app_theme.gd`, applied project-wide via a `ThemeBootstrap` autoload) recolors buttons, panels, the load meter, and the question-overlay scaffolding using the same ink/gold/state-color palette as the reference doc. It covers what Godot's `Theme` system can do without new art assets — no custom icons, sprites, or fonts — so a real designer pass is still the next step, not a replacement for one.
