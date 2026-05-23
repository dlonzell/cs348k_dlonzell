

# From Scenario to Scene: Generating Interactive Language-Learning Practice Scenes for Vision Pro

CS348K Project · Danilo Lonzell

---

## Project

### Aspiration

An LLMR-equivalent for language learning on Apple Vision Pro: a system that takes a scenario card describing a language-learning practice situation and produces an executable interactive scene the learner can act in. The class project is the first step — implementing the generation pipeline and characterizing where it succeeds and fails on a benchmark of real learner-generated scenarios.

### Question

Given a scenario card describing a language-learning practice situation, can a structured-output LLM pipeline generate a runnable interactive scene against a typed primitive vocabulary suited to native visionOS input — and where does it succeed, where does it fail, and what failure modes are most common?

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

9 scenarios across 3 settings, drawn from learner-generated scenarios collected in the prior GELLI study (N=43 Japanese learners).

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

## Checkpoint (May 22)

Detailed checkpoint writeup: [CHECKPOINT_MAY22.md](CHECKPOINT_MAY22.md)  
Current result artifacts: [results/checkpoint2](results/checkpoint2)

### What is running now

Since the first checkpoint, the missing generation stages have been implemented:

- **Step 1 object/layout generation:** a `ScenarioCard` can be sent to an LLM to produce `WorldObjectSpec` objects with ids, display names, natural-language descriptions, primitive/generic kinds, positions, sizes, colors, and interactivity flags.
- **Step 3 task generation:** the generated object list is used to produce typed `InteractionTask` instances over the fixed primitive vocabulary: `indicate`, `tap`, `drag`, `place`, and `gesture`.
- **Validation and retry path:** generated plans are decoded, retried on malformed output or validation failure, and loaded only if `InteractionWorldRuntime.validate(_:)` passes.
- **Generic primitive rendering:** generated open-description objects can render as primitive RealityKit proxies, so scenes are runnable before realistic assets exist.
- **Manual and automatic evaluation UI:** the simulator exposes automatic runtime counts plus manual ratings for object realization, spatial layout, scenario fidelity, primitive faithfulness, affordance instrumentation, and task completion.

### Refined evaluation question

The evaluation now separates three questions:

1. **Primitive coverage:** is the intended language-learning interaction expressible with the current native-input-aligned primitive vocabulary?
2. **LLM planning quality:** if it is expressible, did the LLM choose the right objects, layout, primitive, target object ids, and task order?
3. **Runtime/realization quality:** once a plan validates, does the app render and execute it, and is the scene visually/spatially sufficient for the practice context?

This lets failures be classified as planning gaps, primitive-vocabulary gaps, visual-realization gaps, spatial-layout gaps, affordance gaps, perception/detection gaps, or runtime gaps.

### Intermediate results

| Result | Evidence | Finding |
| --- | --- | --- |
| Hand-authored cafe baseline | Simulator baseline, 7 objects, 5 tasks | Runtime, task queue, interaction handlers, ordering constraints, and evaluation UI work as an upper-bound baseline. |
| LLM-generated primitive plan path | `InteractionWorldGeneration.swift`, generation UI, generation tests | Steps 1 and 3 are implemented; the system can move from scenario card to validated primitive interaction plan. |
| SAM3D visual-realization | [SAM3D layout artifacts](results/checkpoint2/sam3d_layout_signal) | Four segmented objects produced four `.ply` splats plus pose/scale metadata that can be converted into a layout plan in the user's space for the generated objects. Placement is not yet reliable enough, and I'm working on rendering the splats. |

Once SAM3D is working for getting the splats for objects in a scene along with a reasonable layout, I'll replacie the primitive proxies with generated visual assets while keeping typed proxy colliders for the actual interactions. Then I'll see how well this method can create usable interactive scenes in the final evaluation. Right now, the next steps are 

1) finish converting the splat to render in the vision pro as realitykit entitites that have the primitive interactions supported
2) visually assess how well the items are rendered and layed out, and do some tuning of the layout method. 
3) sample 9 scenarios from the study data and use them to generate scenes
4) do manual evaluation of each scene to investigate where this method falls short and what the gaps are. 

### How to run

1. Open `RoleplAR.xcodeproj`.
2. Run the `RoleplAR` scheme on the Apple Vision Pro simulator.
3. Set `OPENAI_API_KEY` in the Xcode scheme environment to enable live LLM generation.
4. Open `Interaction World`.
5. Use `Generate Plan` / `Generate Cafe Plan` for the generated primitive-plan path, or `Load Baseline` for the hand-authored cafe upper bound.
6. Open the micro-world and use the evaluation panel to inspect automatic counts and manual ratings.

To inspect the SAM3D layout artifact:

```bash
cd tools/sam3d_service
python3 mock_service.py --host 127.0.0.1 --port 8010 --layout-plan layout_signal_outputs/roleplar_layout_plan.json
```

Then in the app:

```text
Interaction World -> Load SAM3D Layout Plan -> Open Micro-world
```

### Verification command

Use full Xcode rather than Command Line Tools:

```bash
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild \
  -project /Users/dlonzell/Documents/New\ project/cs348k_dlonzell/RoleplAR.xcodeproj \
  -scheme RoleplAR \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath /private/tmp/cs348k-checkpoint2-build \
  build
```

The same scheme contains the unit tests for `InteractionWorldRuntimeTests` and `InteractionWorldGenerationTests`.

---

## References

De La Torre, F., Fang, C. M., Huang, H., Banburski-Fahey, A., Amores Fernandez, J., & Lanier, J. (2023). LLMR: Real-time Prompting of Interactive Worlds using Large Language Models.
