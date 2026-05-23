#!/usr/bin/env python3
"""Run one real SAM 3D Objects reconstruction and emit RoleplAR metadata.

This script is meant to be run on a Linux/NVIDIA GPU machine inside the
sam3d-objects environment from facebookresearch/sam-3d-objects. It is deliberately
not imported by the mock service so the local RoleplAR repo remains lightweight.

Example:
    python real_single_object.py \
      --sam3d-root /workspace/sam-3d-objects \
      --image /workspace/examples/cafe_counter.png \
      --mask /workspace/examples/coffee_cup_mask.png \
      --object-id coffee_cup \
      --out-dir /workspace/roleplar_sam3d_outputs \
      --public-base-url https://your-host.example/assets
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any


def parse_size(value: str) -> list[float]:
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("size must be width,height,depth")
    return [float(part) for part in parts]


def import_sam3d(sam3d_root: Path) -> tuple[Any, Any, Any]:
    notebook_dir = sam3d_root / "notebook"
    if not notebook_dir.exists():
        raise FileNotFoundError(f"Could not find SAM 3D notebook dir: {notebook_dir}")

    sys.path.insert(0, str(notebook_dir))

    from inference import Inference, load_image, load_mask  # type: ignore

    return Inference, load_image, load_mask


def save_gaussian_splat(output: dict[str, Any], output_path: Path) -> None:
    """Handle the output keys used by the public demo/notebook code."""
    if "gs" in output:
        output["gs"].save_ply(str(output_path))
        return

    if "gaussian" in output:
        gaussian = output["gaussian"]
        if isinstance(gaussian, list):
            gaussian = gaussian[0]
        gaussian.save_ply(str(output_path))
        return

    raise KeyError(f"SAM 3D output did not contain 'gs' or 'gaussian'. Keys: {list(output.keys())}")


def roleplar_response(
    *,
    object_id: str,
    output_path: Path,
    asset_url: str | None,
    position: list[float],
    size: list[float],
    duration_seconds: float,
    notes: str,
) -> dict[str, Any]:
    return {
        "objectId": object_id,
        "status": "realized",
        "visualFormat": "gaussianSplatPLY",
        "assetURL": asset_url,
        "localAssetPath": str(output_path),
        "position": position,
        "size": size,
        "proxyShape": {
            "type": "box",
            "size": size,
        },
        "durationSeconds": duration_seconds,
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sam3d-root", required=True, type=Path)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--mask", required=True, type=Path)
    parser.add_argument("--object-id", required=True)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--tag", default="hf")
    parser.add_argument("--seed", default=42, type=int)
    parser.add_argument("--compile", action="store_true")
    parser.add_argument("--position", default="0.0,0.75,-0.8", type=parse_size)
    parser.add_argument("--size", default="0.15,0.15,0.15", type=parse_size)
    parser.add_argument(
        "--public-base-url",
        default=None,
        help="Optional URL prefix where out-dir files are served, e.g. https://host/assets",
    )
    args = parser.parse_args()

    start = time.time()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    config_path = args.sam3d_root / "checkpoints" / args.tag / "pipeline.yaml"
    if not config_path.exists():
        raise FileNotFoundError(
            f"Could not find checkpoint config: {config_path}. "
            "Download SAM 3D checkpoints first."
        )

    Inference, load_image, load_mask = import_sam3d(args.sam3d_root)
    inference = Inference(str(config_path), compile=args.compile)

    image = load_image(str(args.image))
    mask = load_mask(str(args.mask))
    output = inference(image, mask, seed=args.seed)

    output_path = args.out_dir / f"{args.object_id}.ply"
    save_gaussian_splat(output, output_path)

    asset_url = None
    if args.public_base_url:
        asset_url = f"{args.public_base_url.rstrip('/')}/{output_path.name}"

    metadata = roleplar_response(
        object_id=args.object_id,
        output_path=output_path,
        asset_url=asset_url,
        position=args.position,
        size=args.size,
        duration_seconds=time.time() - start,
        notes="Real SAM 3D single-object reconstruction. Position/size are supplied by caller for the first spike.",
    )

    metadata_path = args.out_dir / f"{args.object_id}.roleplar.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()

