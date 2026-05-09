# May 8 Checkpoint: Interaction World First Slice

## Goal

This slice reframes the LLMR-style pipeline for RoleplAR. Instead of generating arbitrary runtime code, the system uses a structured interaction-world plan over native RealityKit interaction primitives. The first question is whether a generated/local plan can produce the objects, affordances, and task queue needed to evaluate embodied language-learning practice.

## Implemented Vertical Slice

Input scenario card:

```json
{
  "id": "cafe_counter_hello_world",
  "setting": "Japanese cafe counter",
  "learnerRole": "customer",
  "sceneGoal": "Order a drink and pastry, then pay",
  "localContext": "The learner is standing at the counter with a menu, pastry display, tray, cup, and card reader in reach.",
  "targetInteractions": [
    "get the barista's attention",
    "indicate the menu",
    "point at the pastry display",
    "place the drink on the tray",
    "tap the payment terminal"
  ]
}
```

Fixture Builder output:

- Objects: counter, menu, pastry case, coffee cup, tray, card reader, barista marker.
- Task queue:
  1. Wave to the barista.
  2. Indicate the menu.
  3. Point at the pastry display.
  4. Place the coffee cup on the tray.
  5. Tap the card reader.

## System Shape

- `ScenarioCard` and `InteractionWorldPlan` represent the planned world.
- `InteractionWorldRuntime` owns the current task, event log, completion state, validation, and evaluation summary.
- `InteractionWorldTestView` shows the task queue, mock gesture controls, event log, and coverage report.
- `InteractionWorldImmersiveView` renders the plan as primitive RealityKit objects and handles native select, drag, and place events.

## Current Primitive Set

- `indicate(objectId)` through native select/tap.
- `tap(objectId)` through native select/tap.
- `place(objectId, targetId)` through drag end plus distance threshold.
- `gesture(.wave, targetId)` through mock event injection for Friday.
- `gesture(.point, targetId)` through mock event injection or selecting the target while the pointing task is active.

## Evaluation Code

Unit tests in `RoleplARTests/InteractionWorld/InteractionWorldRuntimeTests.swift` check:

- The cafe plan validates.
- Every task references existing objects.
- Every task has a supported handler.
- A simulated five-event sequence completes the whole task queue.
- Wrong or out-of-order events do not advance the queue.

Expected report after completing the demo:

- Object coverage: `7/7`
- Handler coverage: `5/5`
- Completed tasks: `5/5`

## Manual Test

1. Open RoleplAR in Xcode.
2. Run the app.
3. Click `Interaction World` from the main menu.
4. Click `Open Micro-world`.
5. Complete the queue:
   - Press `Wave`.
   - Select/tap `menu`.
   - Press `Point` or select/tap `pastry_case`.
   - Drag `coffee_cup` onto `tray`.
   - Select/tap `card_reader`.
6. Confirm the event log and evaluation report show all tasks complete.

## Verification Notes

- `plutil -lint RoleplAR.xcodeproj/project.pbxproj` passes.
- Swift package resolution succeeds with full Xcode selected.
- The new InteractionWorld Swift files pass `swiftc -parse`.
- `xcodebuild build` passes for the explicit visionOS 26.2 Apple Vision Pro simulator.
- `xcodebuild test` passes for the same simulator, including all six `InteractionWorldRuntimeTests`.
- The app target no longer links the experimental `mlx-swift-lm` package in this branch. `FastVLMAnalyzer` already has a `canImport` fallback path, and the Friday slice is intentionally native/mock-driven rather than real VLM-driven.
