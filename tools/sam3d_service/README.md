# SAM 3D Realization Service

This folder defines the remote service contract for the RoleplAR SAM 3D bridge.

The visionOS app starts long-running generation by sending an `InteractionWorldPlan` to:

```text
POST /realize-scene-async
```

The service immediately returns a `jobId`, and the app polls:

```text
GET /jobs/{jobId}
```

until the job returns object-level realization metadata plus downloadable visual assets. The older synchronous `POST /realize-scene` endpoint is still available for local/mock testing, but real SAM3D runs should use the async job path because model loading and object generation can exceed HTTPS tunnel request timeouts. In the first real version, this service should run on a Linux/NVIDIA GPU machine with Meta's SAM 3D Objects environment installed. The app remains local; the heavy generation/reconstruction work happens remotely.

## Why A Remote Service

Meta's SAM 3D Objects setup currently targets `linux-64` with an NVIDIA GPU. The Vision Pro app should not try to run SAM 3D inference locally. Instead:

```text
RoleplAR visionOS app
  -> POST generated plan to GPU service as a job
  -> poll until the job completes
  -> service generates an isolated object image
  -> service segments/reconstructs the object with SAM3D
  -> service returns USD/USDA or USDZ mesh assets when conversion succeeds
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

## Async Job Responses

`POST /realize-scene-async` returns quickly:

```json
{
  "jobId": "uuid",
  "status": "queued",
  "pollURL": "https://example.com/jobs/uuid"
}
```

`GET /jobs/{jobId}` returns:

```json
{
  "jobId": "uuid",
  "status": "running",
  "result": null,
  "error": null
}
```

When complete, `result` contains the same realization response shape as the synchronous endpoint.

## Service Result

The completed job result contains:

```json
{
  "jobId": "uuid",
  "generatedImageURL": "https://example.com/generated_scene.png",
  "objects": [
    {
      "objectId": "coffee_cup",
      "status": "realized",
      "visualFormat": "usd",
      "assetURL": "https://example.com/assets/coffee_cup.usda",
      "previewImageURL": "https://example.com/assets/coffee_cup_reference.png",
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
visualFormat: usd | usdz | gaussianSplatPLY | primitiveProxy
```

The app only downloads assets for objects with:

```text
status == realized
assetURL != null
```

## Run The Real SAM3D Service

Run this on the Linux/NVIDIA VM where `sam-3d-objects` and its checkpoints are installed. The service uses generated object images as SAM3D input, writes cleaned binary masks, exports SAM3D mesh output as USD/USDA, preserves mesh vertex colors when SAM3D exposes them, falls back to a representative foreground material color, and serves the files back to RoleplAR.

```bash
eval "$(~/bin/micromamba shell hook -s bash)"
micromamba activate sam3d-objects

cd ~/sam-3d-objects
export OPENAI_API_KEY="YOUR_KEY"
export CONDA_PREFIX="$HOME/.local/share/mamba/envs/sam3d-objects"
export PY_NV="$CONDA_PREFIX/lib/python3.11/site-packages/nvidia"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$PY_NV/cublas/lib:$PY_NV/cudnn/lib:$PY_NV/cuda_runtime/lib:$PY_NV/cusparse/lib:$PY_NV/cufft/lib:$PY_NV/curand/lib:$PY_NV/nvjitlink/lib:${LD_LIBRARY_PATH:-}"

python /path/to/cs348k_dlonzell/tools/sam3d_service/real_service.py \
  --host 0.0.0.0 \
  --port 8010 \
  --sam3d-root ~/sam-3d-objects \
  --out-dir ~/sam-3d-objects/outputs/roleplar_real_service \
  --max-objects 0 \
  --sam3d-input-max-dim 512 \
  --disable-cudnn \
  --preload
```

`--max-objects 0` means "attempt every eligible object" instead of stopping after a small debug subset. Counters/tables/flat surfaces remain RoleplAR layout anchors by default; add `--realize-surfaces` only for an experiment where those anchors should also be sent to SAM3D.

Then expose port `8010` to the Mac through SSH, a VM external IP, or an HTTPS tunnel, and put that URL in the RoleplAR **SAM 3D Bridge** field. Use **Generate Scene + SAM3D Objects** after editing the scenario card. `--preload` pays the SAM3D model load cost before the app starts a job; subsequent objects in the same service process reuse the loaded model.

If `usdzip` is available, `real_service.py` converts `.usda` to `.usdz`; otherwise it returns `.usda`. RoleplAR tries to load both as native RealityKit assets. If SAM3D mesh export is unavailable for an object, the service returns the Gaussian-splat `.ply` and preview image as diagnostic artifacts, but the app will not pretend that PLY is a native Vision Pro mesh.

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
cd "/Users/dlonzell/Documents/New project/cs348k_dlonzell/tools/sam3d_service"
python3 mock_service.py \
  --host 127.0.0.1 \
  --port 8010 \
  --real-asset real_assets/livingroom_index14_splat.ply \
  --real-asset-object-id coffee_cup
```

In this mode the service returns `visualFormat: gaussianSplatPLY` and serves the real SAM 3D `.ply` for the chosen object id while returning placeholder `.ply` files for the rest. RoleplAR caches the asset and reloads the plan with `WorldObjectSpec.visualAsset` metadata, while the visible/interactive object remains a primitive RealityKit proxy at the RoleplAR layout-solver position. This is the first generated-visual-object bridge path; direct splat rendering is a later step.

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
cd "/Users/dlonzell/Documents/New project/cs348k_dlonzell/tools/sam3d_service"
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
6. Return per-object asset URLs plus optional observed position/size/proxy metadata for comparison.
```

Keep the app response contract unchanged. That lets the RoleplAR app remain stable while we iterate on the reconstruction backend.

RoleplAR's stage layout remains the source of truth for interactive object positions. SAM 3D-derived position/scale values should be recorded as metadata unless a layout-transfer experiment explicitly loads a `/layout-plan` artifact.

For the first real backend spike, start with one image and one mask rather than the full `/realize-scene` pipeline:

[SPIKE_1_REAL_SAM3D.md](SPIKE_1_REAL_SAM3D.md)

The helper runner is:

[real_single_object.py](real_single_object.py)
