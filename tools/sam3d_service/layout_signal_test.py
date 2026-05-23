#!/usr/bin/env python3
"""Measure SAM 3D multi-object layout signals from one example image.

Run this on the Linux/NVIDIA GPU machine inside the sam3d-objects environment.
It uses one SAM 3D sample folder containing:

  image.png
  0.png, 1.png, ... numbered binary masks

The script reconstructs each requested mask, saves a Gaussian splat .ply, and
writes a compact JSON/CSV report with the signals we care about for RoleplAR:
image-space bbox, SAM 3D translation/scale/rotation, pointmap bounds, and a
simple RoleplAR proxy placement candidate.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
from pathlib import Path
from typing import Any


def parse_indices(value: str) -> list[int]:
    indices: list[int] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        indices.append(int(part))
    if not indices:
        raise argparse.ArgumentTypeError("Provide at least one mask index, e.g. 0,4,14")
    return indices


def import_sam3d(sam3d_root: Path) -> tuple[Any, Any, Any]:
    notebook_dir = sam3d_root / "notebook"
    if not notebook_dir.exists():
        raise FileNotFoundError(f"Could not find SAM 3D notebook dir: {notebook_dir}")

    sys.path.insert(0, str(notebook_dir))

    from inference import Inference, load_image, load_single_mask  # type: ignore

    return Inference, load_image, load_single_mask


def import_numpy_and_pil() -> tuple[Any, Any]:
    import numpy as np  # type: ignore
    from PIL import Image  # type: ignore

    return np, Image


def foreground_mask(mask_path: Path) -> tuple[Any, dict[str, Any]]:
    """Return a boolean object mask, handling SAM3D examples with white backgrounds."""
    np, Image = import_numpy_and_pil()
    image = Image.open(mask_path)
    arr = np.asarray(image)
    candidates: list[tuple[str, Any]] = []

    if arr.ndim == 2:
        candidates.append(("gray_nonzero", arr > 0))
        candidates.append(("gray_not_white", arr < 250))
    else:
        rgb = arr[..., :3]
        candidates.append(("rgb_any_not_white", np.any(rgb < 250, axis=-1)))
        candidates.append(("rgb_any_nonzero", np.any(rgb > 0, axis=-1)))
        if arr.shape[-1] >= 4:
            candidates.append(("alpha_nonzero", arr[..., 3] > 0))

    best_name: str | None = None
    best_mask: Any | None = None
    best_score = float("inf")
    best_stats: dict[str, Any] = {}

    for name, mask in candidates:
        ys, xs = np.nonzero(mask)
        if xs.size == 0 or ys.size == 0:
            continue

        height, width = mask.shape
        area_fraction = float(xs.size) / float(width * height)
        bbox_area = float((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1)) / float(width * height)
        full_image_penalty = 10.0 if area_fraction > 0.9 or bbox_area > 0.95 else 0.0
        tiny_penalty = 2.0 if area_fraction < 0.00001 else 0.0
        score = full_image_penalty + tiny_penalty + bbox_area + (area_fraction * 0.25)

        if score < best_score:
            best_name = name
            best_mask = mask
            best_score = score
            best_stats = {
                "foregroundMethod": name,
                "foregroundAreaFraction": area_fraction,
                "foregroundBBoxAreaFraction": bbox_area,
            }

    if best_mask is None or best_name is None:
        raise ValueError(f"Could not find foreground pixels in mask: {mask_path}")

    return best_mask.astype(bool), best_stats


def write_clean_mask(mask_path: Path, output_path: Path) -> dict[str, Any]:
    np, Image = import_numpy_and_pil()
    mask, stats = foreground_mask(mask_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((mask.astype(np.uint8) * 255), mode="L").save(output_path)
    return stats


def to_numpy(value: Any) -> Any | None:
    if value is None:
        return None
    if hasattr(value, "detach"):
        value = value.detach()
    if hasattr(value, "cpu"):
        value = value.cpu()
    if hasattr(value, "numpy"):
        return value.numpy()
    return value


def to_jsonable(value: Any, max_items: int = 16) -> Any:
    value = to_numpy(value)
    if value is None:
        return None
    if hasattr(value, "tolist"):
        value = value.tolist()
    if isinstance(value, tuple):
        value = list(value)
    if isinstance(value, list):
        if len(value) > max_items:
            return {
                "preview": [to_jsonable(item, max_items=max_items) for item in value[:max_items]],
                "truncatedLength": len(value),
            }
        return [to_jsonable(item, max_items=max_items) for item in value]
    if isinstance(value, dict):
        return {str(key): to_jsonable(item, max_items=max_items) for key, item in value.items()}
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    if isinstance(value, (str, int, bool)):
        return value
    return str(value)


def vector3(value: Any) -> list[float] | None:
    value = to_numpy(value)
    if value is None:
        return None

    try:
        import numpy as np  # type: ignore

        arr = np.asarray(value, dtype=float).reshape(-1)
        if arr.size < 3:
            return None
        return [float(arr[0]), float(arr[1]), float(arr[2])]
    except Exception:
        return None


def mask_bbox(mask_path: Path) -> dict[str, Any]:
    np, Image = import_numpy_and_pil()
    image = Image.open(mask_path)
    arr, foreground_stats = foreground_mask(mask_path)
    ys, xs = np.nonzero(arr)
    width, height = image.size
    if xs.size == 0 or ys.size == 0:
        return {
            "imageWidth": width,
            "imageHeight": height,
            "isEmpty": True,
            **foreground_stats,
        }

    x_min = int(xs.min())
    x_max = int(xs.max())
    y_min = int(ys.min())
    y_max = int(ys.max())
    bbox_width = x_max - x_min + 1
    bbox_height = y_max - y_min + 1
    return {
        "imageWidth": width,
        "imageHeight": height,
        "isEmpty": False,
        "xMin": x_min,
        "xMax": x_max,
        "yMin": y_min,
        "yMax": y_max,
        "width": bbox_width,
        "height": bbox_height,
        "centerX": (x_min + x_max) / 2,
        "centerY": (y_min + y_max) / 2,
        "areaPixels": int(xs.size),
        "areaFraction": float(xs.size) / float(width * height),
        **foreground_stats,
    }


def array_bounds(value: Any) -> dict[str, Any] | None:
    value = to_numpy(value)
    if value is None:
        return None

    try:
        import numpy as np  # type: ignore

        arr = np.asarray(value, dtype=float)
        if arr.size == 0:
            return None
        arr = arr.reshape(-1, arr.shape[-1]) if arr.ndim > 1 else arr.reshape(-1, 1)
        finite = np.all(np.isfinite(arr), axis=1)
        arr = arr[finite]
        if arr.size == 0:
            return None
        mins = arr.min(axis=0)
        maxs = arr.max(axis=0)
        return {
            "count": int(arr.shape[0]),
            "min": [float(x) for x in mins[:3]],
            "max": [float(x) for x in maxs[:3]],
            "extent": [float(x) for x in (maxs - mins)[:3]],
        }
    except Exception as exc:
        return {"error": str(exc)}


def image_plane_roleplar_candidate(bbox: dict[str, Any]) -> dict[str, Any] | None:
    if bbox.get("isEmpty"):
        return None

    image_width = float(bbox["imageWidth"])
    image_height = float(bbox["imageHeight"])
    center_x = float(bbox["centerX"])
    center_y = float(bbox["centerY"])
    width = float(bbox["width"])
    height = float(bbox["height"])

    # A deliberately simple proxy layout: put objects on a tabletop-like plane.
    # X follows image left/right. Z follows image vertical position, with lower
    # image objects closer to the learner.
    x = ((center_x / image_width) - 0.5) * 1.6
    z = -0.55 - (center_y / image_height) * 0.85
    proxy_width = max(0.06, min(0.35, (width / image_width) * 1.1))
    proxy_height = max(0.06, min(0.45, (height / image_height) * 0.9))
    proxy_depth = max(0.06, min(0.35, math.sqrt(float(bbox["areaFraction"])) * 0.7))

    return {
        "position": [x, 0.72 + proxy_height / 2, z],
        "size": [proxy_width, proxy_height, proxy_depth],
        "notes": "Image-plane proxy candidate for RoleplAR coordinate initialization; not metric 3D.",
    }


def apply_sam3d_roleplar_candidates(objects: list[dict[str, Any]]) -> dict[str, Any]:
    """Normalize SAM3D translation/scale outputs into a RoleplAR proxy layout.

    This is the core test for the spike. We keep the transformation simple and
    report the axis choices so the result can be inspected rather than treated
    as ground truth.
    """
    candidates = [item for item in objects if item["sam3D"].get("translation")]
    if not candidates:
        for item in objects:
            item["sam3DRoleplARCandidate"] = item.get("imagePlaneRoleplARCandidate")
        return {
            "source": "imagePlaneFallback",
            "notes": "No usable SAM3D translation values found.",
        }

    translations = [item["sam3D"]["translation"] for item in candidates]
    scales = [
        item["sam3D"].get("scale") or [1.0, 1.0, 1.0]
        for item in candidates
    ]
    x_values = [float(value[0]) for value in translations]
    y_values = [float(value[1]) for value in translations]
    z_values = [float(value[2]) for value in translations]

    y_spread = max(y_values) - min(y_values)
    z_spread = max(z_values) - min(z_values)
    depth_axis = 2 if z_spread >= y_spread else 1
    depth_values = z_values if depth_axis == 2 else y_values

    def normalize(value: float, values: list[float], fallback: float = 0.5) -> float:
        low = min(values)
        high = max(values)
        if abs(high - low) < 1e-5:
            return fallback
        return (value - low) / (high - low)

    scale_magnitudes = [
        max(abs(float(scale[0])), abs(float(scale[1])), abs(float(scale[2])), 1e-5)
        for scale in scales
    ]

    for item in objects:
        translation = item["sam3D"].get("translation")
        scale = item["sam3D"].get("scale") or [1.0, 1.0, 1.0]
        fallback = item.get("imagePlaneRoleplARCandidate")
        if not translation:
            item["sam3DRoleplARCandidate"] = fallback
            continue

        x_norm = normalize(float(translation[0]), x_values)
        depth_norm = normalize(float(translation[depth_axis]), depth_values)
        scale_mag = max(abs(float(scale[0])), abs(float(scale[1])), abs(float(scale[2])), 1e-5)
        scale_norm = normalize(scale_mag, scale_magnitudes)

        proxy_width = 0.08 + 0.22 * scale_norm
        proxy_height = 0.10 + 0.30 * scale_norm
        proxy_depth = 0.08 + 0.22 * scale_norm

        item["sam3DRoleplARCandidate"] = {
            "position": [
                -0.75 + x_norm * 1.5,
                0.72 + proxy_height / 2,
                -0.55 - depth_norm * 0.85,
            ],
            "size": [proxy_width, proxy_height, proxy_depth],
            "rawTranslation": translation,
            "rawScale": scale,
            "depthAxis": "z" if depth_axis == 2 else "y",
            "notes": "Normalized from SAM3D translation/scale; intended for relative layout testing, not metric placement.",
        }

    return {
        "source": "sam3DTranslationScale",
        "depthAxis": "z" if depth_axis == 2 else "y",
        "translationRanges": {
            "x": [min(x_values), max(x_values)],
            "y": [min(y_values), max(y_values)],
            "z": [min(z_values), max(z_values)],
        },
        "scaleMagnitudeRange": [min(scale_magnitudes), max(scale_magnitudes)],
    }


def draw_layout_debug(image_path: Path, objects: list[dict[str, Any]], output_path: Path) -> None:
    _, Image = import_numpy_and_pil()
    from PIL import ImageDraw, ImageFont  # type: ignore

    source = Image.open(image_path).convert("RGB")
    max_left_width = 760
    scale = min(1.0, max_left_width / max(source.size[0], 1))
    if scale != 1.0:
        source = source.resize(
            (int(source.size[0] * scale), int(source.size[1] * scale)),
            Image.Resampling.LANCZOS,
        )

    font = ImageFont.load_default()
    palette = [
        (0, 220, 255),
        (255, 205, 0),
        (255, 93, 93),
        (93, 255, 140),
        (200, 130, 255),
        (255, 150, 80),
        (255, 255, 255),
    ]

    image_draw = ImageDraw.Draw(source)
    for index, item in enumerate(objects):
        bbox = item["maskBBox"]
        if bbox.get("isEmpty"):
            continue
        color = palette[index % len(palette)]
        x0 = int(bbox["xMin"] * scale)
        y0 = int(bbox["yMin"] * scale)
        x1 = int(bbox["xMax"] * scale)
        y1 = int(bbox["yMax"] * scale)
        image_draw.rectangle([x0, y0, x1, y1], outline=color, width=4)
        image_draw.text((x0 + 4, y0 + 4), item["objectId"], fill=color, font=font)

    panel_width = 760
    panel_height = source.size[1]
    panel = Image.new("RGB", (panel_width, panel_height), (22, 24, 28))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.text((24, 18), "SAM3D-derived RoleplAR proxy layout", fill=(240, 240, 240), font=font)
    panel_draw.text((24, 38), "top-down: x left/right, z near/far after normalization", fill=(170, 170, 170), font=font)

    plot_margin = 70
    plot_left = plot_margin
    plot_top = 78
    plot_right = panel_width - plot_margin
    plot_bottom = panel_height - 52
    panel_draw.rectangle([plot_left, plot_top, plot_right, plot_bottom], outline=(80, 84, 92), width=2)

    def map_proxy(x: float, z: float) -> tuple[int, int]:
        x_min, x_max = -0.9, 0.9
        z_near, z_far = -0.45, -1.45
        px = plot_left + (x - x_min) / (x_max - x_min) * (plot_right - plot_left)
        py = plot_top + (z - z_far) / (z_near - z_far) * (plot_bottom - plot_top)
        return int(px), int(py)

    origin_x, origin_y = map_proxy(0.0, -0.45)
    panel_draw.ellipse([origin_x - 6, origin_y - 6, origin_x + 6, origin_y + 6], fill=(255, 255, 255))
    panel_draw.text((origin_x + 10, origin_y - 6), "learner", fill=(220, 220, 220), font=font)

    for index, item in enumerate(objects):
        proxy = item.get("sam3DRoleplARCandidate")
        if not proxy:
            continue
        color = palette[index % len(palette)]
        position = proxy["position"]
        size = proxy["size"]
        px, py = map_proxy(float(position[0]), float(position[2]))
        width = max(10, int(float(size[0]) / 1.8 * (plot_right - plot_left)))
        depth = max(10, int(float(size[2]) / 1.0 * (plot_bottom - plot_top)))
        panel_draw.rectangle(
            [px - width // 2, py - depth // 2, px + width // 2, py + depth // 2],
            outline=color,
            width=3,
        )
        panel_draw.text((px + width // 2 + 4, py - 8), item["objectId"], fill=color, font=font)

    combined = Image.new("RGB", (source.size[0] + panel_width, max(source.size[1], panel_height)), (16, 16, 18))
    combined.paste(source, (0, 0))
    combined.paste(panel, (source.size[0], 0))
    combined.save(output_path)


def roleplar_plan(objects: list[dict[str, Any]], image_path: Path) -> dict[str, Any]:
    colors = ["cyan", "yellow", "red", "green", "purple", "blue", "gray"]
    world_objects = []
    for index, item in enumerate(objects):
        proxy = item.get("sam3DRoleplARCandidate") or item.get("imagePlaneRoleplARCandidate")
        if not proxy:
            continue
        world_objects.append(
            {
                "id": item["objectId"],
                "displayName": f"Mask {item['maskIndex']}",
                "description": f"SAM3D layout-test object from mask {item['maskIndex']} in {image_path.name}.",
                "kind": {"type": "generic", "category": "smallObject"},
                "position": proxy["position"],
                "size": proxy["size"],
                "color": colors[index % len(colors)],
                "isInteractive": True,
                "visualAsset": {
                    "format": "gaussianSplatPLY",
                    "source": "sam3D",
                    "status": "realized",
                    "remoteURL": None,
                    "localURL": None,
                    "notes": item["plyPath"],
                },
            }
        )

    return {
        "id": "sam3d_layout_signal_test",
        "scenario": {
            "id": "sam3d_layout_signal_test",
            "setting": "SAM3D example scene",
            "learnerRole": "tester",
            "sceneGoal": "Inspect whether SAM3D pose and scale outputs transfer into a plausible RoleplAR object layout.",
            "localContext": f"Objects are reconstructed from masks in {image_path}. Positions and sizes are normalized from SAM3D translation and scale outputs.",
            "targetInteractions": [],
            "expectedObjectCategories": ["sam3d_masked_object"],
        },
        "objects": world_objects,
        "tasks": [],
    }


def save_gaussian_splat(output: dict[str, Any], output_path: Path) -> None:
    if "gs" in output:
        output["gs"].save_ply(str(output_path))
        return
    if "gaussian" in output:
        gaussian = output["gaussian"]
        if isinstance(gaussian, list):
            gaussian = gaussian[0]
        gaussian.save_ply(str(output_path))
        return
    raise KeyError(f"No Gaussian splat in SAM 3D output. Keys: {list(output.keys())}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sam3d-root", required=True, type=Path)
    parser.add_argument(
        "--sample-dir",
        required=True,
        type=Path,
        help="SAM 3D sample folder with image.png and numbered mask PNGs.",
    )
    parser.add_argument("--mask-indices", required=True, type=parse_indices)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--tag", default="hf")
    parser.add_argument("--seed", default=42, type=int)
    parser.add_argument("--compile", action="store_true")
    parser.add_argument(
        "--disable-cudnn",
        action="store_true",
        help="Use this on the L4 setup if cuDNN/cuBLAS library conflicts appear.",
    )
    args = parser.parse_args()

    if args.disable_cudnn:
        import torch  # type: ignore

        torch.backends.cudnn.enabled = False

    args.out_dir.mkdir(parents=True, exist_ok=True)
    image_path = args.sample_dir / "image.png"
    if not image_path.exists():
        raise FileNotFoundError(f"Missing sample image: {image_path}")

    config_path = args.sam3d_root / "checkpoints" / args.tag / "pipeline.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"Missing SAM 3D config: {config_path}")

    Inference, load_image, load_single_mask = import_sam3d(args.sam3d_root)

    load_start = time.time()
    inference = Inference(str(config_path), compile=args.compile)
    model_load_seconds = time.time() - load_start

    image = load_image(str(image_path))
    objects: list[dict[str, Any]] = []
    clean_mask_dir = args.out_dir / "clean_masks"
    clean_mask_dir.mkdir(parents=True, exist_ok=True)

    for mask_index in args.mask_indices:
        object_id = f"mask_{mask_index}"
        mask_path = args.sample_dir / f"{mask_index}.png"
        if not mask_path.exists():
            raise FileNotFoundError(f"Missing mask {mask_index}: {mask_path}")

        bbox = mask_bbox(mask_path)
        clean_mask_path = clean_mask_dir / f"{mask_index}.png"
        write_clean_mask(mask_path, clean_mask_path)
        mask = load_single_mask(str(clean_mask_dir), index=mask_index)

        inference_start = time.time()
        output = inference(image, mask, seed=args.seed)
        inference_seconds = time.time() - inference_start

        ply_path = args.out_dir / f"{object_id}.ply"
        save_gaussian_splat(output, ply_path)

        objects.append(
            {
                "objectId": object_id,
                "maskIndex": mask_index,
                "maskPath": str(mask_path),
                "cleanMaskPath": str(clean_mask_path),
                "maskBBox": bbox,
                "imagePlaneRoleplARCandidate": image_plane_roleplar_candidate(bbox),
                "sam3D": {
                    "translation": vector3(output.get("translation")),
                    "scale": vector3(output.get("scale")),
                    "rotation": to_jsonable(output.get("rotation")),
                    "translationScale": to_jsonable(output.get("translation_scale")),
                    "pointmapBounds": array_bounds(output.get("pointmap")),
                    "coordsBounds": array_bounds(output.get("coords")),
                    "coordsOriginalBounds": array_bounds(output.get("coords_original")),
                },
                "inferenceSeconds": inference_seconds,
                "outputKeys": sorted(output.keys()),
                "plyPath": str(ply_path),
                "plySizeBytes": ply_path.stat().st_size,
            }
        )

    normalization = apply_sam3d_roleplar_candidates(objects)

    report = {
        "sampleDir": str(args.sample_dir),
        "imagePath": str(image_path),
        "maskIndices": args.mask_indices,
        "modelLoadSeconds": model_load_seconds,
        "objectCount": len(objects),
        "normalization": normalization,
        "objects": objects,
    }

    report_path = args.out_dir / "layout_signal_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    csv_path = args.out_dir / "layout_signal_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "objectId",
                "maskIndex",
                "bboxCenterX",
                "bboxCenterY",
                "bboxWidth",
                "bboxHeight",
                "samTranslation",
                "samScale",
                "samProxyPosition",
                "samProxySize",
                "proxyPosition",
                "proxySize",
                "inferenceSeconds",
                "plySizeBytes",
            ],
        )
        writer.writeheader()
        for item in objects:
            bbox = item["maskBBox"]
            image_proxy = item["imagePlaneRoleplARCandidate"] or {}
            sam_proxy = item["sam3DRoleplARCandidate"] or {}
            writer.writerow(
                {
                    "objectId": item["objectId"],
                    "maskIndex": item["maskIndex"],
                    "bboxCenterX": bbox.get("centerX"),
                    "bboxCenterY": bbox.get("centerY"),
                    "bboxWidth": bbox.get("width"),
                    "bboxHeight": bbox.get("height"),
                    "samTranslation": item["sam3D"]["translation"],
                    "samScale": item["sam3D"]["scale"],
                    "samProxyPosition": sam_proxy.get("position"),
                    "samProxySize": sam_proxy.get("size"),
                    "proxyPosition": image_proxy.get("position"),
                    "proxySize": image_proxy.get("size"),
                    "inferenceSeconds": f"{item['inferenceSeconds']:.2f}",
                    "plySizeBytes": item["plySizeBytes"],
                }
            )

    debug_image_path = args.out_dir / "layout_signal_debug.png"
    draw_layout_debug(image_path, objects, debug_image_path)

    roleplar_plan_path = args.out_dir / "roleplar_layout_plan.json"
    roleplar_plan_path.write_text(
        json.dumps(roleplar_plan(objects, image_path), indent=2),
        encoding="utf-8",
    )

    print(json.dumps(report, indent=2))
    print(f"Wrote {report_path}")
    print(f"Wrote {csv_path}")
    print(f"Wrote {debug_image_path}")
    print(f"Wrote {roleplar_plan_path}")


if __name__ == "__main__":
    main()
