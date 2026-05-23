# Spike 1: One Real SAM 3D Object

Goal:

```text
one RGB image + one object mask
  -> SAM 3D Objects inference
  -> one Gaussian splat .ply
  -> one RoleplAR-compatible object metadata JSON
```

This spike does **not** solve scene-wide generation, segmentation, object linking, or visionOS splat rendering. It only proves that we can produce a real `.ply` object that the RoleplAR bridge can later download.

## Hardware Reality

Run this on a Linux/NVIDIA GPU machine. The official SAM 3D setup currently asks for:

```text
linux-64
NVIDIA GPU with at least 32 GB VRAM
Hugging Face access to facebook/sam-3d-objects checkpoints
```

Your local Mac should stay responsible for RoleplAR/Xcode. The GPU box should run this reconstruction spike.

## 1. Set Up SAM 3D Objects On The GPU Box

```bash
git clone https://github.com/facebookresearch/sam-3d-objects.git
cd sam-3d-objects
```

Follow the official setup:

```bash
mamba env create -f environments/default.yml
mamba activate sam3d-objects

export PIP_EXTRA_INDEX_URL="https://pypi.ngc.nvidia.com https://download.pytorch.org/whl/cu121"
pip install -e '.[dev]'
pip install -e '.[p3d]'

export PIP_FIND_LINKS="https://nvidia-kaolin.s3.us-east-2.amazonaws.com/torch-2.5.1_cu121.html"
pip install -e '.[inference]'
./patching/hydra
```

Request access to the Hugging Face model, authenticate, then download checkpoints:

```bash
pip install 'huggingface-hub[cli]<1.0'
hf auth login

TAG=hf
hf download \
  --repo-type model \
  --local-dir checkpoints/${TAG}-download \
  --max-workers 1 \
  facebook/sam-3d-objects
mv checkpoints/${TAG}-download/checkpoints checkpoints/${TAG}
rm -rf checkpoints/${TAG}-download
```

## 2. Prepare One Image And One Mask

For the first run, use any RGB image plus a binary mask where the object is white/nonzero and the background is black/transparent.

Example file layout:

```text
/workspace/roleplar_spike_inputs/
  cafe_counter.png
  coffee_cup_mask.png
```

The mask can come from any segmentation tool for now. It does not need to be automatic for this spike.

## 3. Copy The Runner To The GPU Box

Copy:

```text
/Users/dlonzell/Desktop/dev/RoleplAR-fastvlm-test/tools/sam3d_service/real_single_object.py
```

to the GPU machine, or run it from a clone of the RoleplAR repo.

## 4. Run One Reconstruction

```bash
python real_single_object.py \
  --sam3d-root /workspace/sam-3d-objects \
  --image /workspace/roleplar_spike_inputs/cafe_counter.png \
  --mask /workspace/roleplar_spike_inputs/coffee_cup_mask.png \
  --object-id coffee_cup \
  --out-dir /workspace/roleplar_sam3d_outputs \
  --position 0.0,0.75,-0.8 \
  --size 0.12,0.16,0.12
```

Expected files:

```text
/workspace/roleplar_sam3d_outputs/
  coffee_cup.ply
  coffee_cup.roleplar.json
```

Expected JSON shape:

```json
{
  "objectId": "coffee_cup",
  "status": "realized",
  "visualFormat": "gaussianSplatPLY",
  "assetURL": null,
  "localAssetPath": "/workspace/roleplar_sam3d_outputs/coffee_cup.ply",
  "position": [0.0, 0.75, -0.8],
  "size": [0.12, 0.16, 0.12],
  "proxyShape": {
    "type": "box",
    "size": [0.12, 0.16, 0.12]
  },
  "durationSeconds": 0.0,
  "notes": "Real SAM 3D single-object reconstruction..."
}
```

## 5. Make The Result Downloadable

For the RoleplAR app bridge, the `.ply` needs to be downloadable over HTTP. A quick temporary server is enough:

```bash
cd /workspace/roleplar_sam3d_outputs
python -m http.server 8020
```

Then the asset URL would be:

```text
http://<gpu-host>:8020/coffee_cup.ply
```

Once this works, the next step is to wrap this runner inside `/realize-scene` so the app can request reconstruction directly.

## Success Criteria

This spike succeeds when:

```text
coffee_cup.ply exists
coffee_cup.roleplar.json exists
the .ply can be downloaded over HTTP
the RoleplAR mock/bridge contract can be populated with that asset URL
```

It does not need to render in Vision Pro yet. That is Spike 2.

