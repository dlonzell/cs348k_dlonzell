# SAM 3D Realization Service

This folder defines the remote service contract for the RoleplAR SAM 3D bridge.

The visionOS app sends an `InteractionWorldPlan` to:

```text
POST /realize-scene
```

and expects back object-level realization metadata plus downloadable visual assets. In the first real version, this service should run on a Linux/NVIDIA GPU machine with Meta's SAM 3D Objects environment installed. The app remains local; the heavy generation/reconstruction work happens remotely.

## Why A Remote Service

Meta's SAM 3D Objects setup currently targets `linux-64` with an NVIDIA GPU. The Vision Pro app should not try to run SAM 3D inference locally. Instead:

```text
RoleplAR visionOS app
  -> POST generated plan to GPU service
  -> service generates/segments/reconstructs
  -> service returns .ply splat URLs + transforms/proxy metadata
  -> app caches assets and reloads the reconciled plan
```

## App Request

The Swift app sends this shape:

```json
{
  "scenario": {
    "id": "cafe_counter_hello_world",
    "setting": "Japanese cafe counter",
    "learnerRole": "customer",
    "sceneGoal": "Order a drink and pastry, then pay",
    "localContext": "The learner is standing at the counter...",
    "targetInteractions": ["..."],
    "expectedObjectCategories": ["..."]
  },
  "plan": {
    "id": "cafe_counter_generated_attempt_1",
    "scenario": {},
    "objects": [
      {
        "id": "coffee_cup",
        "displayName": "Coffee Cup",
        "description": "A cup of coffee",
        "kind": { "type": "cup" },
        "position": [0.0, 0.78, -0.8],
        "size": [0.12, 0.16, 0.12],
        "color": "cyan",
        "isInteractive": true
      }
    ],
    "tasks": []
  }
}
```

## Service Response

The app expects:

```json
{
  "jobId": "uuid",
  "generatedImageURL": "https://example.com/generated_scene.png",
  "objects": [
    {
      "objectId": "coffee_cup",
      "status": "realized",
      "visualFormat": "gaussianSplatPLY",
      "assetURL": "https://example.com/assets/coffee_cup.ply",
      "position": [0.0, 0.78, -0.8],
      "size": [0.12, 0.16, 0.12],
      "proxyShape": {
        "type": "cylinder",
        "size": [0.12, 0.16, 0.12]
      },
      "notes": "Segmented and reconstructed"
    }
  ],
  "notes": "optional run notes"
}
```

Allowed values:

```text
status: realized | missing | failed | fallbackPrimitive
visualFormat: gaussianSplatPLY | usdz | primitiveProxy
```

The app only downloads assets for objects with:

```text
status == realized
assetURL != null
```

## Run The Mock Service

The mock service does not run SAM 3D. It creates tiny placeholder `.ply` files so you can test the RoleplAR bridge end-to-end.

```bash
cd /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service
python3 mock_service.py --host 127.0.0.1 --port 8010
```

Then in RoleplAR:

```text
Interaction World
  -> Generate Plan or Load Baseline
  -> SAM 3D Bridge URL: http://127.0.0.1:8010
  -> Realize Current Plan
```

Expected result: the app caches fake `.ply` files, reloads the plan with `visualAsset` metadata, and keeps the RealityKit primitive proxies interactive.

## Run The Bridge With A Real SAM 3D Artifact

After running the real SAM 3D smoke test, you can reuse the generated Gaussian splat `.ply` while keeping the same app-side bridge contract:

```bash
cd /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service
python3 mock_service.py \
  --host 127.0.0.1 \
  --port 8010 \
  --real-asset real_assets/livingroom_index14_splat.ply
```

In this mode the service returns `visualFormat: gaussianSplatPLY` and serves the real SAM 3D `.ply` for each realized object. RoleplAR currently caches the asset and reloads the plan with `WorldObjectSpec.visualAsset`, while the visible/interactive object remains a primitive RealityKit proxy. This is the checkpoint bridge demo path; direct splat rendering is a later step.

See [CHECKPOINT_2_SAM3D_BRIDGE.md](CHECKPOINT_2_SAM3D_BRIDGE.md) for the full runbook and checkpoint wording.

## Test SAM 3D Layout Transfer

The layout signal test asks whether SAM 3D's per-object pose and scale outputs can initialize object placement in RoleplAR. It runs several masks from the same SAM 3D example image, writes a report, creates a visual comparison PNG, and emits a `roleplar_layout_plan.json` that the app can load through the bridge service.

On the GPU VM, after activating the SAM 3D environment:

```bash
cd ~/sam-3d-objects

export CONDA_PREFIX="$HOME/.local/share/mamba/envs/sam3d-objects"
export PY_NV="$CONDA_PREFIX/lib/python3.11/site-packages/nvidia"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$PY_NV/cublas/lib:$PY_NV/cudnn/lib:$PY_NV/cuda_runtime/lib:$PY_NV/cusparse/lib:$PY_NV/cufft/lib:$PY_NV/curand/lib:$PY_NV/nvjitlink/lib:${LD_LIBRARY_PATH:-}"

python /path/to/RoleplAR-fastvlm-test/tools/sam3d_service/layout_signal_test.py \
  --sam3d-root ~/sam-3d-objects \
  --sample-dir ~/sam-3d-objects/notebook/images/137444513_Livingroom-graphic81 \
  --mask-indices 1,4,10,14 \
  --out-dir ~/sam-3d-objects/outputs/layout_signal_livingroom_clean \
  --disable-cudnn
```

Expected outputs:

```text
layout_signal_report.json
layout_signal_summary.csv
layout_signal_debug.png
roleplar_layout_plan.json
mask_1.ply, mask_4.ply, ...
```

The runner writes cleaned binary masks before calling SAM 3D. This is important for the bundled example masks, where the object foreground is represented by non-white pixels on a white background. Using raw nonzero pixels treats almost the entire image as foreground.

To load the resulting layout in RoleplAR, copy `roleplar_layout_plan.json` and `layout_signal_debug.png` back to this folder, then run:

```bash
cd /Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service
python3 mock_service.py \
  --host 127.0.0.1 \
  --port 8010 \
  --layout-plan layout_signal_outputs/roleplar_layout_plan.json
```

In RoleplAR:

```text
Interaction World -> SAM 3D Bridge -> Load SAM3D Layout Plan -> Open Micro-world
```

Then compare the `layout_signal_debug.png` source-mask overlay against the micro-world proxy layout. The evaluation question is whether left/right order, rough relative size, and near/far organization survive the SAM 3D-to-RoleplAR normalization.

## Real SAM 3D Implementation Hook

The real GPU-backed service should replace the mock object realization step with:

```text
1. Build a scene-image prompt from the plan's object inventory.
2. Generate a scene image.
3. Segment/link planned object IDs to masks.
4. Run SAM 3D Objects on each mask.
5. Export each object as a Gaussian splat .ply.
6. Return per-object asset URLs plus position/size/proxy metadata.
```

Keep the app response contract unchanged. That lets the RoleplAR app remain stable while we iterate on the reconstruction backend.

For the first real backend spike, start with one image and one mask rather than the full `/realize-scene` pipeline:

[SPIKE_1_REAL_SAM3D.md](SPIKE_1_REAL_SAM3D.md)

The helper runner is:

[real_single_object.py](real_single_object.py)
