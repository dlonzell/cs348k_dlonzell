# Checkpoint 2 SAM 3D Bridge Demo

## What This Spike Proves

This spike connects the RoleplAR interaction-world pipeline to a real SAM 3D artifact without requiring full splat rendering inside RealityKit yet.

Confirmed on May 22, 2026:

| Stage | Result |
| --- | --- |
| Cloud VM | GCP `g2-standard-4` with NVIDIA L4 |
| SAM 3D install | Success |
| Model load | Success, cold load `793.8s` |
| Input | SAM 3D sample RGB image + mask |
| Inference | Success, `37.6s` |
| Output | `livingroom_index14_splat.ply`, `9.3 MB` |
| RoleplAR bridge | App can attach downloadable `gaussianSplatPLY` metadata to `WorldObjectSpec` and keep primitive interaction proxies |

The current RoleplAR renderer still displays primitive RealityKit proxies. The generated SAM 3D asset is associated with the object and cached by the app, but not rendered as splat geometry yet.

## May 22 Layout Signal Update

After the single-object smoke test, I ran a four-object layout signal test using cleaned masks from the same SAM 3D example scene:

| Output | Result |
| --- | --- |
| Masks | `1`, `4`, `10`, `14` cleaned as non-white foreground |
| Generated assets | `mask_1.ply`, `mask_4.ply`, `mask_10.ply`, `mask_14.ply` |
| Report | `results/checkpoint2/sam3d_layout_signal/layout_signal_report.json` |
| Compact table | `results/checkpoint2/sam3d_layout_signal/layout_signal_summary.csv` |
| RoleplAR plan | `results/checkpoint2/sam3d_layout_signal/roleplar_layout_plan.json` |

The derived plan loads in RoleplAR through `GET /layout-plan` and renders four SAM3D-backed primitive proxies. The result is technically successful as a bridge, but the proxy placement is not accurate enough to claim reliable layout transfer yet. This is now an explicit spatial-layout failure mode for the final evaluation.

## Why This Is Still Useful

The architectural claim for the checkpoint is:

```text
ScenarioCard
  -> generated InteractionWorldPlan
  -> interactive primitive RealityKit scene
  -> SAM 3D bridge returns realized visual asset URLs
  -> RoleplAR caches assets and reloads the plan with visualAsset metadata
  -> interactions remain testable through typed proxy colliders
```

This keeps visual generation and interaction execution decoupled. The splat/mesh can become the visible skin later; the typed collider/proxy remains the reliable interaction target.

## Copy The Real SAM 3D Artifact Back To The Mac

If the VM is stopped, start it first:

```bash
gcloud compute instances start roleplar-sam3d-l4 --zone=us-east1-d
```

From a local Mac terminal with `gcloud` configured, copy the artifact into the RoleplAR service folder:

```bash
mkdir -p /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service/real_assets

gcloud compute scp   roleplar-sam3d-l4:~/sam-3d-objects/outputs/sam3d_smoke/livingroom_index14_splat.ply   /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service/real_assets/livingroom_index14_splat.ply   --zone=us-east1-d
```

Then stop the VM again:

```bash
gcloud compute instances stop roleplar-sam3d-l4 --zone=us-east1-d
```

If `gcloud` is not configured on the Mac, copy the file to Cloud Shell first and use the Cloud Shell web UI download action, then place it at:

```text
/Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service/real_assets/livingroom_index14_splat.ply
```

## Run The Local Bridge Service With The Real Artifact

```bash
cd /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service
python3 mock_service.py   --host 127.0.0.1   --port 8010   --real-asset real_assets/livingroom_index14_splat.ply
```

Expected console output:

```text
Mock SAM 3D service running at http://127.0.0.1:8010
SAM 3D bridge mode: real artifact (.../livingroom_index14_splat.ply)
```

## Run In RoleplAR

1. Open `RoleplAR.xcodeproj`.
2. Run the RoleplAR scheme on the Apple Vision Pro simulator.
3. Open `Interaction World`.
4. Generate or load a plan.
5. In `SAM 3D Bridge`, use:

```text
http://127.0.0.1:8010
```

6. Click `Realize Current Plan`.
7. Open the micro-world.
8. Capture a screenshot showing:
   - generated/loaded interactive scene,
   - task queue,
   - `SAM 3D Bridge` result counts,
   - `Cached splats > 0`,
   - status text saying the SAM 3D realization loaded with primitive interaction proxies.

## Checkpoint Claim To Use

> I implemented the scene-generation and runtime-evaluation path in RoleplAR, then added a SAM 3D visual-realization bridge. The current renderer still uses primitive proxies for interaction, but the bridge can attach and cache real SAM 3D Gaussian splat assets. A GCP L4 feasibility run produced a real `9.3 MB` splat from an image and mask with `37.6s` inference after a cold `793.8s` model load.

## Remaining Work

- Render SAM 3D assets directly in the visionOS scene.
- Prefer mesh/USDZ conversion if available; otherwise add/borrow a Gaussian splat renderer.
- Replace the temporary bridge service with a persistent GPU service that loads SAM 3D once.
- Add image generation, segmentation, and object-to-plan linking before SAM 3D reconstruction.
