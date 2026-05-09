Github Token: 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

# From Scenario to Scene: Generating Interactive Language-Learning Practice Scenes for Vision Pro

CS348K Project · Danilo Lonzell

---

## Project

### Aspiration

An LLMR-equivalent for language learning on Apple Vision Pro: a system that takes a scenario card describing a language-learning practice situation and produces an executable interactive scene the learner can act in. The class project is the first step — implementing the generation pipeline and characterizing where it succeeds and fails on a benchmark of real learner-generated scenarios.

### Question

Given a scenario card describing a language-learning practice situation, can a structured-output LLM pipeline generate a runnable interactive scene against a typed primitive vocabulary suited to native visionOS input — and where does it succeed, where does it fail, and what failure modes are most common?

### Relationship to LLMR

LLMR (De La Torre et al., 2023) demonstrated that LLMs can generate arbitrary interactive 3D worlds in real time by writing C# code that compiles and executes inside Unity. Their Planner-Builder-Inspector architecture is the conceptual ancestor of this project. We have three main differences:

- **Structured plan output instead of code.** Most platforms restrict runtime code execution. Instead, we'll produce JSON conforming to a typed plan schema; the runtime generates objects, parses, validates, and renders.
- **Typed interaction instead of open Unity APIs.** Interactions are drawn from a closed set aligned with native visionOS input.
- **Domain-specific application.** Language-learning practice rather than the general scene and intearction scope of LLMR.

### Pipeline

```
ScenarioCard
  → [Step 1 — LLM call] objects with positions, sizes, colors, descriptions
  → [Step 2 — object rendering] RealityKit entities generated using some model (using primitives for this checkpoint) 
  → [Step 3 — LLM call] tasks with typed primitives against object IDs
  → [Step 4 — validation] structural checks
  → [Step 5 — runtime] render and process interaction events
```

### Interaction primitives

The typed primitive set, aligned with native visionOS input:

- `indicate(objectId)`, `tap(objectId)` — gaze-pinch selection
- `drag(objectId)` — pinch-and-move
- `place(objectId, targetId)` — drag with proximity check at release
- `gesture(GestureKind, targetId?)` — recognized hand gestures (wave, point, thumbsUp, openPalm)

### Scenario benchmark

9 scenarios across 3 settings, drawn from learner-generated scenarios collected in the prior GELLI study (N=43 Japanese learners). Drawing from real learner data — rather than authoring scenarios — addresses a methodological concern: researcher-authored scenarios would bias toward what the system can already handle.

### Evaluation

The evaluation is mostly manual, supported by automatic infrastructure for validation, runtime checks, and pipeline metrics.

#### Automatic measurements.

Validation outcomes: did the assembled plan parse and pass validate(_:)? 
Pipeline metrics: generation time per scenario, number of regeneration attempts before validation passed (max 3), per-stage success rates.

#### Manual ratings against a rubric. For each generated plan, I'll manually rate:

Step 1 — object specification: did the LLM produce objects covering what the scenario implies, at plausible positions and sizes? 
Step 3 — task wiring: for each task, does the implementation faithfully represent the natural-language interaction described in the prompt?
Step 5 — runtime: did the validated plan execute correctly when loaded in the simulator? 

#### Coverage analysis. 

Aggregating across all scenarios and tasks: what fraction of target interactions mapped faithfully, required compromise, or just didn't work entirely. This characterizes the boundaries of the native-input-aligned interaction vocabulary for language-learning practice.

---

## Checkpoint (May 8)

### What is running

A basic version of the pipeline excluding the LLM generation steps:

- **Data model:** `ScenarioCard`, `InteractionWorldPlan`, `WorldObjectSpec`, `InteractionTask`, `InteractionKind`, `GestureKind`, validation error types, manual evaluation types.
- **Validation** (`InteractionWorldRuntime.validate(_:)`): catches duplicate IDs, missing object references, unsupported interaction kinds. Throws typed errors that map directly to failure-mode categories.
- **Runtime:** processes interaction events, advances task queue on match, logs events, records completion.
- **Renderer:** renders an `InteractionWorldPlan` as a RealityKit scene with primitive entities, input target components, and interaction handlers.
- **Hand-authored cafe scenario:** one fully-specified scenario (Japanese cafe counter, 7 objects, 5 tasks) serving as the upper-bound baseline. Renders correctly in the visionOS simulator and supports end-to-end task completion.
- **Automatic evaluation:** structural checks reported as `InteractionEvaluationResult`.
- **Manual evaluation UI:** per-task ratings across five metrics with yes/partial/no/unset.
- **Tests:** validation, event processing, task progression. All passing.

This version uses a hand-authored cafe scenario plays through end-to-end in the simulator: scene renders, all five tasks can be completed by the tester (wave, indicate menu, point at pastry case, place cup on tray, tap card reader), evaluation surfaces results. Broken plans (duplicate IDs, missing object references, unsupported primitives) are correctly rejected by the validator.


### What is not yet implemented

- Steps 1 and 3 (the LLM calls). Generation does not yet exist.
- The remaining 8 scenario cards. Currently only the cafe scenario; others to be drawn from existing study data analysis.
- The renderer needs to be extended to handle objects with arbitrary descriptions outside the existing closed `WorldObjectKind` enum (current renderer maps a fixed set of kinds to primitives; generated plans will produce open-description objects).

### Next steps

1. Implement Step 1: LLM call producing objects with positions, sizes, colors, and descriptions.
2. Implement Step 3: LLM call producing tasks with typed primitives against generated object IDs.
3. Extend the renderer to handle open-description objects via primitive fallback.
4. Analyze GELLI study data to draw 8 additional scenarios; format as `ScenarioCard` instances.
5. Run the full pipeline on all 9 scenarios; collect per-stage evaluation data.
6. Aggregate failure modes; produce coverage matrix and taxonomy figures.

### Risks

- **LLM reliability for structured output.** Mitigation: up to 3 attempts per generation step; failures after 3 attempts are recorded as a failure mode rather than blocking the experiment.
- **Scenario authoring time.** Mitigation: keep scenario cards short; lean on existing study data structure; reduce to 6 scenarios if necessary without changing methodology.
- **Manual evaluation scope.** Mitigation: stages measurable from generated artifacts (Steps 1, 3, 4) are fast; behavioral testing (Step 5) is the slow one and can be done on a subset, with the writeup explicit about which scenarios got behavioral testing.

### Code


Open RoleplAR.xcodeproj

Run the RoleplAR scheme on an Apple Vision Pro simulator.

In the main menu, click Interaction World: MainMenuView.swift (line 34)

Click Open Micro-world, then complete the cafe task queue with:

Mock Wave, tap/select menu, Mock Point, drag cup to tray, tap/select card reader.



Evaluation UI


The visible evaluation panel is in InteractionWorldView.swift (line 254).

It reports automated counts: object coverage, handler coverage, completed tasks.

The manual rubric is in InteractionWorldView.swift (line 270): object ratings, spatial layout, scenario fidelity, primitive faithfulness, and per-task yes/partial/no checks.

Metric definitions live in InteractionWorldModels.swift (line 344).



Automated tests / evaluation code


Runtime evaluation: InteractionWorldRuntime.swift (line 99)

Generation-stage evaluation/failure modes: GenerationEvaluation.swift (line 3)

Tests:

InteractionWorldRuntimeTests.swift (line 6)

InteractionWorldGenerationTests.swift (line 6)

---

## References

De La Torre, F., Fang, C. M., Huang, H., Banburski-Fahey, A., Amores Fernandez, J., & Lanier, J. (2023). LLMR: Real-time Prompting of Interactive Worlds using Large Language Models.
