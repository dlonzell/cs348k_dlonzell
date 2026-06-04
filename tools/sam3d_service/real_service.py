#!/usr/bin/env python3
"""GPU-backed SAM3D scene realization service for RoleplAR.

This is the real generation path. Given a RoleplAR interaction plan, it:

1. Generates an isolated object image for each selected object.
2. Builds a foreground mask for that generated image.
3. Runs SAM 3D Objects once per object.
4. Exports a native USD/USDA mesh when SAM3D returns mesh geometry.
5. Also saves the Gaussian-splat PLY and preview image for debugging.

The visionOS app keeps RoleplAR's collider and interaction semantics as the
source of truth, but it can render the returned USD/USDA asset as the visible
generated object.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
from urllib import request
from urllib.parse import unquote

os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")


def slug(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_]+", "_", value.strip().lower())
    return value.strip("_") or "object"


def sanitize_size(value: Any) -> list[float]:
    if isinstance(value, list) and len(value) == 3:
        try:
            return [max(float(part), 0.03) for part in value]
        except (TypeError, ValueError):
            pass
    return [0.16, 0.16, 0.16]


def object_kind(world_object: dict[str, Any]) -> tuple[str, str]:
    kind = world_object.get("kind", {})
    if isinstance(kind, dict):
        return str(kind.get("type", "")), str(kind.get("category", ""))
    return str(kind), ""


def object_text(world_object: dict[str, Any]) -> str:
    return " ".join(
        str(world_object.get(key, ""))
        for key in ("id", "displayName", "description")
    ).lower()


def is_container_like(world_object: dict[str, Any]) -> bool:
    kind_type, category = object_kind(world_object)
    text = object_text(world_object)
    return (
        category == "container"
        or kind_type in {"basket", "bag", "box", "tray", "bowl", "bin"}
        or any(token in text for token in ("basket", "bag", "box", "tray", "bowl", "bin"))
    )


def is_context_like(world_object: dict[str, Any]) -> bool:
    kind_type, _ = object_kind(world_object)
    text = object_text(world_object)
    return kind_type in {"menu", "displayCase", "npcMarker"} or any(
        token in text
        for token in (
            "menu",
            "display",
            "sign",
            "vendor",
            "cashier",
            "barista",
            "clerk",
            "server",
            "attendant",
            "seller",
            "staff",
            "marker",
            "reader",
            "terminal",
        )
    )


def is_surface_like(world_object: dict[str, Any]) -> bool:
    kind_type, category = object_kind(world_object)
    text = object_text(world_object)
    return (
        kind_type in {"counter", "table"}
        or category == "flatSurface"
        or any(token in text for token in ("counter", "table", "stand", "stall", "surface", "desk"))
    )


def should_realize_object(world_object: dict[str, Any], realize_surfaces: bool = False) -> bool:
    object_id = str(world_object.get("id", ""))
    if object_id == "interaction_surface":
        return False

    if not realize_surfaces and is_surface_like(world_object):
        return False

    return True


def task_object_priorities(plan: dict[str, Any]) -> dict[str, int]:
    """Rank objects by the task order that makes them worth visualizing first."""
    priorities: dict[str, int] = {}
    tasks = plan.get("tasks") or []
    if not isinstance(tasks, list):
        return priorities

    for index, task in enumerate(tasks):
        if not isinstance(task, dict):
            continue

        base = index * 10
        interaction = task.get("expectedInteraction") or {}
        if isinstance(interaction, dict):
            source_id = interaction.get("objectId")
            target_id = interaction.get("targetId")
            interaction_type = str(interaction.get("type", ""))

            if source_id:
                priorities[str(source_id)] = min(priorities.get(str(source_id), base), base)

            if target_id:
                # Targets matter, but after the thing the learner handles.
                offset = 2 if interaction_type == "place" else 3
                target_key = str(target_id)
                priorities[target_key] = min(priorities.get(target_key, base + offset), base + offset)

        required_ids = task.get("requiredObjectIds") or []
        if isinstance(required_ids, list):
            for required_id in required_ids:
                key = str(required_id)
                priorities[key] = min(priorities.get(key, base + 1), base + 1)

    return priorities


def realization_priority(
    world_object: dict[str, Any],
    task_priorities: Optional[dict[str, int]] = None,
) -> tuple[int, int, float, str]:
    size = sanitize_size(world_object.get("size"))
    volume = size[0] * size[1] * size[2]
    text = object_text(world_object)
    object_id = str(world_object.get("id", ""))
    task_rank = (task_priorities or {}).get(object_id, 999)

    if is_surface_like(world_object):
        return (990, 8, volume, object_id)

    if any(token in text for token in ("apple", "cup", "snack", "chips", "wallet", "card", "ticket")):
        group = 0
    elif object_kind(world_object)[1] == "smallObject":
        group = 1
    elif is_container_like(world_object):
        group = 3
    elif is_context_like(world_object):
        group = 4
    else:
        group = 2

    return (task_rank, group, volume, object_id)


def request_host_url(headers: Any) -> str:
    proto = headers.get("X-Forwarded-Proto") or headers.get("Cf-Visitor")
    if proto and "https" in str(proto).lower():
        scheme = "https"
    else:
        scheme = "http"

    return f"{scheme}://{headers.get('Host')}"


def prompt_for_object(scenario: dict[str, Any], world_object: dict[str, Any]) -> str:
    display_name = str(world_object.get("displayName") or world_object.get("id") or "object")
    description = str(world_object.get("description") or "")
    setting = str(scenario.get("setting") or "an educational roleplay scene")
    goal = str(scenario.get("sceneGoal") or "")
    asset_card = world_object.get("assetCard") or {}
    asset_hint = canonical_asset_hint(world_object)

    return (
        "Create one clean product-style reference image of a single object for 3D reconstruction.\n"
        f"Object: {display_name}.\n"
        f"Description: {description}.\n"
        f"Scenario setting: {setting}.\n"
        f"Scenario goal: {goal}.\n"
        f"Layout role: {asset_card.get('layoutRole', 'unknown')}.\n"
        f"Asset kind: {asset_card.get('assetKind', 'unknown')}.\n"
        f"Orientation hint: {asset_card.get('orientationHint', 'unknown')}.\n"
        f"Asset guidance: {asset_hint}\n"
        "Requirements: isolated single object, centered, fully visible, realistic material, "
        "distinctive object-appropriate color, visible surface texture/detail, "
        "object fills most of the frame, front view with slight top view, plain white background, "
        "no floor plane, no strong cast shadow, no hands, no people unless the object is explicitly "
        "a person marker, no environment, no text labels, no watermark."
    )


def canonical_asset_hint(world_object: dict[str, Any]) -> str:
    text = object_text(world_object)
    kind_type, category = object_kind(world_object)
    asset_card = world_object.get("assetCard") or {}
    asset_kind = str(asset_card.get("assetKind") or "").lower()

    if asset_kind == "paymentdevice":
        return "small tabletop payment card reader, compact rectangular device with screen and tap area"
    if asset_kind == "displayfixture":
        return (
            "small tabletop pastry display case or product display tray, low and horizontal, "
            "clear cover or shallow base, front-facing, not a sign, not a billboard"
        )
    if asset_kind == "menu":
        return "upright menu sign or display board, simple rectangular stand, no readable text"
    if asset_kind == "personmarker":
        return (
            "upright stylized counter-attendant marker or simple mannequin bust, front-facing, "
            "standing vertically on a small base, no signpost, no text, no floor-facing billboard"
        )
    if asset_kind == "cup":
        return "single cup, upright with open top visible, stable cylindrical shape, no saucer unless explicitly requested"
    if asset_kind == "tray":
        return "empty shallow tray or plate, horizontal tabletop object, clean rim visible"
    if asset_kind == "container":
        return "small open-top container, basket, bowl, or bag matching the object name, stable product photo, no contents"
    if any(token in text for token in ("chips", "snack")):
        return (
            "sealed upright snack bag or chips package, rectangular flexible pouch, "
            "front-facing, not torn open, no loose chips, no crumpled flat wrapper"
        )
    if any(token in text for token in ("basket", "shopping_basket")):
        return (
            "small plastic shopping basket with open top, visible lattice holes and rim, "
            "stable product photo, no contents"
        )
    if any(token in text for token in ("wallet",)):
        return "closed wallet, compact rectangular shape, leather-like material, no cards or hands"
    if any(token in text for token in ("payment", "reader", "terminal", "card")) or kind_type == "cardReader":
        return "small tabletop payment card reader, compact rectangular device with screen and tap area"
    if any(token in text for token in ("cup", "coffee")) or kind_type == "cup":
        return "single cup, open top visible, stable cylindrical shape, no saucer unless explicitly requested"
    if kind_type == "displayCase" or any(
        token in text for token in ("display case", "display_case", "pastry display", "pastry_display")
    ):
        return (
            "small tabletop pastry display case or product display tray, low and horizontal, "
            "clear cover or shallow base, front-facing, not a sign, not a billboard"
        )
    if any(token in text for token in ("menu", "sign")) or kind_type == "menu" or category == "uprightObject":
        return "upright menu sign or display board, simple rectangular stand, no readable text"
    if any(token in text for token in ("tray", "plate")):
        return "empty shallow tray or plate, tabletop object, clean rim visible"
    if any(token in text for token in ("apple", "fruit")):
        return "single whole fruit, clean silhouette, stem visible if appropriate, no leaves or extra fruit"
    if any(
        token in text
        for token in ("vendor", "cashier", "barista", "clerk", "server", "attendant", "seller", "staff")
    ) or kind_type == "npcMarker":
        return (
            "upright stylized counter-attendant marker or simple mannequin bust, front-facing, "
            "standing vertically on a small base, no signpost, no text, no floor-facing billboard"
        )
    if is_container_like(world_object):
        return "single empty container object, open top visible, no contents"
    if is_context_like(world_object):
        return "upright roleplay marker prop, front-facing, vertical on a small base, no text"
    return "single complete object with clear silhouette and enough thickness for 3D reconstruction"


def openai_generate_image(prompt: str, output_path: Path, model: str, size: str) -> None:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is required for real object image generation.")

    body = {
        "model": model,
        "prompt": prompt,
        "size": size,
    }
    data = json.dumps(body).encode("utf-8")
    req = request.Request(
        "https://api.openai.com/v1/images/generations",
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with request.urlopen(req, timeout=180) as response:
        payload = json.loads(response.read().decode("utf-8"))

    image_item = payload.get("data", [{}])[0]
    if "b64_json" in image_item:
        output_path.write_bytes(base64.b64decode(image_item["b64_json"]))
        return

    if "url" in image_item:
        with request.urlopen(image_item["url"], timeout=180) as image_response:
            output_path.write_bytes(image_response.read())
        return

    raise RuntimeError(f"Image response did not contain b64_json or url: {payload}")


AXIS_VECTORS: dict[str, tuple[float, float, float]] = {
    "+X": (1.0, 0.0, 0.0),
    "-X": (-1.0, 0.0, 0.0),
    "+Y": (0.0, 1.0, 0.0),
    "-Y": (0.0, -1.0, 0.0),
    "+Z": (0.0, 0.0, 1.0),
    "-Z": (0.0, 0.0, -1.0),
}


AXIS_OPPOSITES: dict[str, str] = {
    "+X": "-X",
    "-X": "+X",
    "+Y": "-Y",
    "-Y": "+Y",
    "+Z": "-Z",
    "-Z": "+Z",
}


POSE_CANDIDATES: list[tuple[str, str]] = [
    ("A", "+X"),
    ("B", "-X"),
    ("C", "+Y"),
    ("D", "-Y"),
    ("E", "+Z"),
    ("F", "-Z"),
]


def clamp_float(value: Any, default: float, lower: float, upper: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(number):
        return default
    return max(lower, min(upper, number))


def vector_dot(lhs: tuple[float, float, float], rhs: tuple[float, float, float]) -> float:
    return lhs[0] * rhs[0] + lhs[1] * rhs[1] + lhs[2] * rhs[2]


def vector_cross(lhs: tuple[float, float, float], rhs: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        lhs[1] * rhs[2] - lhs[2] * rhs[1],
        lhs[2] * rhs[0] - lhs[0] * rhs[2],
        lhs[0] * rhs[1] - lhs[1] * rhs[0],
    )


def vector_length(value: tuple[float, float, float]) -> float:
    return math.sqrt(vector_dot(value, value))


def vector_normalize(value: tuple[float, float, float]) -> tuple[float, float, float]:
    length = vector_length(value)
    if length < 1e-6:
        return (0.0, 0.0, 0.0)
    return (value[0] / length, value[1] / length, value[2] / length)


def candidate_basis(up_axis: str) -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]:
    up = vector_normalize(AXIS_VECTORS[up_axis])
    reference = (0.0, 0.0, 1.0)
    if abs(vector_dot(up, reference)) > 0.92:
        reference = (1.0, 0.0, 0.0)
    right = vector_normalize(vector_cross(reference, up))
    forward = vector_normalize(vector_cross(up, right))
    return right, up, forward


def render_pose_candidate_grid(
    mesh_arrays: tuple[list[list[float]], list[list[int]], Optional[list[list[float]]]],
    output_path: Path,
    object_id: str,
    material_color: list[float],
) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
        import numpy as np
    except Exception as exc:
        raise RuntimeError("Pillow and numpy are required for pose candidate rendering.") from exc

    vertices, _faces, vertex_colors = mesh_arrays
    points = np.array(vertices, dtype=np.float32)
    if points.shape[0] == 0:
        raise RuntimeError("Cannot render pose candidates from an empty mesh.")

    if points.shape[0] > 16000:
        stride = max(1, points.shape[0] // 16000)
        points = points[::stride]
        if vertex_colors is not None:
            vertex_colors = vertex_colors[::stride]

    center = (points.min(axis=0) + points.max(axis=0)) / 2.0
    points = points - center
    span = float(np.max(np.ptp(points, axis=0)))
    if span > 1e-6:
        points = points / span

    if vertex_colors is not None and len(vertex_colors) >= points.shape[0]:
        colors = np.array(vertex_colors[: points.shape[0]], dtype=np.float32)
    else:
        colors = np.tile(np.array(material_color, dtype=np.float32), (points.shape[0], 1))
    colors = np.clip(colors, 0.0, 1.0)

    cell_w = 320
    cell_h = 260
    label_h = 34
    margin = 18
    cols = 3
    rows = 2
    image = Image.new("RGB", (cols * cell_w, rows * cell_h), (245, 246, 248))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 16)
        small_font = ImageFont.truetype("DejaVuSans.ttf", 13)
    except Exception:
        font = ImageFont.load_default()
        small_font = ImageFont.load_default()

    title = f"{object_id}: choose natural up axis"
    draw.text((margin, 6), title, fill=(35, 35, 38), font=font)

    for index, (candidate_id, up_axis) in enumerate(POSE_CANDIDATES):
        col = index % cols
        row = index // cols
        ox = col * cell_w
        oy = row * cell_h + label_h
        right, up, forward = candidate_basis(up_axis)

        projected_x = points @ np.array(right, dtype=np.float32)
        projected_y = points @ np.array(up, dtype=np.float32)
        depth = points @ np.array(forward, dtype=np.float32)
        order = np.argsort(depth)

        x_min, x_max = float(projected_x.min()), float(projected_x.max())
        y_min, y_max = float(projected_y.min()), float(projected_y.max())
        x_span = max(x_max - x_min, 1e-6)
        y_span = max(y_max - y_min, 1e-6)
        scale = min((cell_w - margin * 2) / x_span, (cell_h - label_h - margin * 2) / y_span)

        draw.rounded_rectangle(
            [ox + 8, oy + 8, ox + cell_w - 8, oy + cell_h - label_h - 8],
            radius=8,
            fill=(255, 255, 255),
            outline=(206, 210, 216),
            width=1,
        )
        label = f"{candidate_id}: local {up_axis} is UP"
        draw.text((ox + margin, oy + 12), label, fill=(20, 20, 22), font=font)

        for point_index in order:
            x = int(ox + cell_w / 2 + projected_x[point_index] * scale)
            y = int(oy + (cell_h - label_h) / 2 - projected_y[point_index] * scale + 12)
            depth_lift = clamp_float((float(depth[point_index]) + 0.5) * 0.25, 0.0, -0.2, 0.25)
            color = tuple(
                int(max(0, min(255, (channel + depth_lift) * 255)))
                for channel in colors[point_index].tolist()
            )
            draw.point((x, y), fill=color)

        draw.text(
            (ox + margin, oy + cell_h - label_h - 26),
            "upright/resting candidate",
            fill=(84, 88, 96),
            font=small_font,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)


def normalize_axis(value: Any) -> Optional[str]:
    if value is None:
        return None
    axis = str(value).strip().upper()
    axis = axis.replace(" ", "")
    if axis in AXIS_VECTORS:
        return axis
    return None


def sanitize_canonical_pose(
    raw_pose: dict[str, Any],
    *,
    candidate_grid_url: str,
) -> dict[str, Any]:
    selected_candidate = str(raw_pose.get("selectedCandidate") or "").strip().upper()
    candidate_axis = next(
        (axis for candidate_id, axis in POSE_CANDIDATES if candidate_id == selected_candidate),
        None,
    )
    up_axis = normalize_axis(raw_pose.get("upAxis")) or candidate_axis
    bottom_axis = normalize_axis(raw_pose.get("bottomAxis"))
    if bottom_axis is None and up_axis is not None:
        bottom_axis = AXIS_OPPOSITES[up_axis]
    front_axis = normalize_axis(raw_pose.get("frontAxis"))

    if selected_candidate not in {candidate_id for candidate_id, _axis in POSE_CANDIDATES}:
        selected_candidate = next(
            (candidate_id for candidate_id, axis in POSE_CANDIDATES if axis == up_axis),
            "",
        )

    return {
        "selectedCandidate": selected_candidate or None,
        "upAxis": up_axis,
        "bottomAxis": bottom_axis,
        "frontAxis": front_axis,
        "restingPose": str(raw_pose.get("restingPose") or raw_pose.get("naturalRestingPose") or "unknown")[:80],
        "confidence": clamp_float(raw_pose.get("confidence"), 0.0, 0.0, 1.0),
        "reason": str(raw_pose.get("reason") or "")[:280],
        "candidateGridURL": candidate_grid_url,
    }


def openai_classify_asset_pose(
    *,
    model: str,
    object_id: str,
    display_name: str,
    description: str,
    asset_card: dict[str, Any],
    candidate_grid_path: Path,
    candidate_grid_url: str,
) -> dict[str, Any]:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is required for VLM asset canonicalization.")

    encoded_image = base64.b64encode(candidate_grid_path.read_bytes()).decode("ascii")
    prompt = (
        "You are labeling a reconstructed 3D object for an AR layout engine.\n"
        "The image is a contact sheet of the same mesh rendered six ways. Each candidate label says which "
        "LOCAL mesh axis would be treated as the object's UP axis.\n"
        "Choose the candidate where the object would naturally rest on a table/counter/floor, not on its side. "
        "For bags, baskets, cups, trays, people, signs, and card readers, prefer the orientation a human would expect "
        "during interaction.\n"
        "Also infer a frontAxis only if the mesh clearly has a front, such as handles, screen, face, label, or opening. "
        "Use null if unsure.\n\n"
        f"Object id: {object_id}\n"
        f"Display name: {display_name}\n"
        f"Description: {description}\n"
        f"Asset card: {json.dumps(asset_card, sort_keys=True)}\n\n"
        "Return JSON only with this schema:\n"
        "{"
        "\"selectedCandidate\":\"A|B|C|D|E|F\","
        "\"upAxis\":\"+X|-X|+Y|-Y|+Z|-Z\","
        "\"bottomAxis\":\"+X|-X|+Y|-Y|+Z|-Z\","
        "\"frontAxis\":\"+X|-X|+Y|-Y|+Z|-Z|null\","
        "\"restingPose\":\"short label\","
        "\"confidence\":0.0,"
        "\"reason\":\"short explanation\""
        "}"
    )
    body = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{encoded_image}",
                        },
                    },
                ],
            }
        ],
        "response_format": {"type": "json_object"},
    }
    req = request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with request.urlopen(req, timeout=180) as response:
        payload = json.loads(response.read().decode("utf-8"))

    content = payload.get("choices", [{}])[0].get("message", {}).get("content")
    if not isinstance(content, str):
        raise RuntimeError(f"VLM response did not contain message content: {payload}")

    raw_pose = json.loads(content)
    if not isinstance(raw_pose, dict):
        raise RuntimeError(f"VLM response was not a JSON object: {content}")
    return sanitize_canonical_pose(raw_pose, candidate_grid_url=candidate_grid_url)


def canonicalize_asset_pose(
    *,
    args: argparse.Namespace,
    mesh_arrays: tuple[list[list[float]], list[list[int]], Optional[list[list[float]]]],
    object_dir: Path,
    host_url: str,
    object_id: str,
    display_name: str,
    description: str,
    asset_card: dict[str, Any],
    material_color: list[float],
) -> Optional[dict[str, Any]]:
    if not args.canonicalize_assets_with_vlm:
        return None

    candidate_grid_path = object_dir / f"{object_id}_pose_candidates.png"
    render_pose_candidate_grid(mesh_arrays, candidate_grid_path, object_id, material_color)
    candidate_grid_url = f"{host_url}/assets/{candidate_grid_path.relative_to(args.out_dir)}"

    try:
        pose = openai_classify_asset_pose(
            model=args.openai_vlm_model,
            object_id=object_id,
            display_name=display_name,
            description=description,
            asset_card=asset_card,
            candidate_grid_path=candidate_grid_path,
            candidate_grid_url=candidate_grid_url,
        )
        print(
            f"VLM canonical pose for {object_id}: "
            f"up={pose.get('upAxis')} front={pose.get('frontAxis')} confidence={pose.get('confidence')}",
            flush=True,
        )
        return pose
    except Exception as exc:
        print(f"VLM canonical pose failed for {object_id}: {exc}", flush=True)
        return {
            "selectedCandidate": None,
            "upAxis": None,
            "bottomAxis": None,
            "frontAxis": None,
            "restingPose": "unknown",
            "confidence": 0.0,
            "reason": f"VLM canonicalization failed: {exc}"[:280],
            "candidateGridURL": candidate_grid_url,
        }


def prepare_sam3d_input(
    image_path: Path,
    mask_path: Path,
    sam3d_image_path: Path,
    sam3d_mask_path: Path,
    max_dim: int,
) -> dict[str, Any]:
    try:
        from PIL import Image
        import numpy as np
    except Exception as exc:
        raise RuntimeError("Pillow and numpy are required in the SAM3D environment.") from exc

    image = Image.open(image_path).convert("RGB")
    mask_image = Image.open(mask_path).convert("L")
    mask = np.array(mask_image) > 0

    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        image.save(sam3d_image_path)
        mask_image.save(sam3d_mask_path)
        return {
            "sam3dInputWidth": image.width,
            "sam3dInputHeight": image.height,
            "sam3dInputScale": 1.0,
        }

    padding = max(12, int(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) * 0.12))
    left = max(0, int(xs.min()) - padding)
    upper = max(0, int(ys.min()) - padding)
    right = min(image.width, int(xs.max()) + padding + 1)
    lower = min(image.height, int(ys.max()) + padding + 1)

    image = image.crop((left, upper, right, lower))
    mask_image = mask_image.crop((left, upper, right, lower))

    scale = 1.0
    longest = max(image.width, image.height)
    if max_dim > 0 and longest > max_dim:
        scale = max_dim / longest
        new_size = (max(1, int(image.width * scale)), max(1, int(image.height * scale)))
        image = image.resize(new_size, Image.Resampling.LANCZOS)
        mask_image = mask_image.resize(new_size, Image.Resampling.NEAREST)

    image.save(sam3d_image_path)
    mask_image.save(sam3d_mask_path)
    return {
        "sam3dInputWidth": image.width,
        "sam3dInputHeight": image.height,
        "sam3dInputScale": scale,
        "sam3dCropBox": [left, upper, right, lower],
    }


def clear_cuda_cache() -> None:
    try:
        import torch

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception:
        pass


def largest_connected_component(mask: Any) -> Any:
    try:
        import numpy as np
        from scipy import ndimage  # type: ignore

        labels, count = ndimage.label(mask)
        if count == 0:
            return mask

        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        return labels == int(sizes.argmax())
    except Exception:
        pass

    try:
        import numpy as np
        from collections import deque
    except Exception:
        return mask

    height, width = mask.shape
    visited = np.zeros(mask.shape, dtype=bool)
    best_pixels: list[tuple[int, int]] = []

    starts = np.argwhere(mask)
    for start_y, start_x in starts:
        y = int(start_y)
        x = int(start_x)
        if visited[y, x] or not mask[y, x]:
            continue

        component: list[tuple[int, int]] = []
        queue: deque[tuple[int, int]] = deque([(y, x)])
        visited[y, x] = True

        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if (
                    0 <= ny < height
                    and 0 <= nx < width
                    and not visited[ny, nx]
                    and mask[ny, nx]
                ):
                    visited[ny, nx] = True
                    queue.append((ny, nx))

        if len(component) > len(best_pixels):
            best_pixels = component

    cleaned = np.zeros(mask.shape, dtype=bool)
    if best_pixels:
        ys, xs = zip(*best_pixels)
        cleaned[np.array(ys), np.array(xs)] = True
    return cleaned


def smooth_mask(mask: Any) -> Any:
    try:
        from scipy import ndimage  # type: ignore

        mask = ndimage.binary_fill_holes(mask)
        mask = ndimage.binary_opening(mask, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]])
        mask = ndimage.binary_closing(mask, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]])
    except Exception:
        pass
    return mask


def save_foreground_mask(image_path: Path, mask_path: Path) -> dict[str, Any]:
    try:
        from PIL import Image
        import numpy as np
    except Exception as exc:
        raise RuntimeError("Pillow and numpy are required in the SAM3D environment.") from exc

    image = Image.open(image_path).convert("RGBA")
    arr = np.array(image)
    rgb = arr[..., :3].astype(np.float32) / 255.0
    alpha = arr[..., 3]

    alpha_mask = alpha > 16
    corner = max(8, min(image.width, image.height) // 32)
    corner_pixels = np.concatenate(
        [
            rgb[:corner, :corner].reshape(-1, 3),
            rgb[:corner, -corner:].reshape(-1, 3),
            rgb[-corner:, :corner].reshape(-1, 3),
            rgb[-corner:, -corner:].reshape(-1, 3),
        ],
        axis=0,
    )
    background = np.median(corner_pixels, axis=0)
    color_distance = np.linalg.norm(rgb - background, axis=-1)
    max_channel_delta = np.max(np.abs(rgb - background), axis=-1)
    channel_max = np.max(rgb, axis=-1)
    channel_min = np.min(rgb, axis=-1)
    saturation = (channel_max - channel_min) / np.maximum(channel_max, 1e-6)
    luminance = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722

    raw_mask = alpha_mask & ((color_distance > 0.045) | (max_channel_delta > 0.035))

    # Product-reference generations often include a soft gray floor shadow.
    # Shadow pixels are connected to the object in a naive non-white mask, so
    # remove low-saturation/bright pixels before component cleanup.
    shadow_like = raw_mask & (saturation < 0.16) & (luminance > 0.50)
    color_confident = raw_mask & ~shadow_like
    if color_confident.sum() >= 64:
        mask = color_confident
    else:
        mask = raw_mask

    mask = largest_connected_component(mask)
    mask = smooth_mask(mask)

    # Generated image backgrounds are usually white. If cleanup is too strict,
    # fall back to the largest raw foreground component.
    if mask.sum() < 64:
        mask = smooth_mask(largest_connected_component(raw_mask))

    raw_mask_path = mask_path.with_name(f"{mask_path.stem}_raw{mask_path.suffix}")
    Image.fromarray((raw_mask.astype(np.uint8) * 255)).save(raw_mask_path)

    Image.fromarray((mask.astype(np.uint8) * 255)).save(mask_path)

    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return {
            "isEmpty": True,
            "areaPixels": 0,
            "areaFraction": 0,
        }

    return {
        "isEmpty": False,
        "areaPixels": int(len(xs)),
        "areaFraction": float(len(xs) / mask.size),
        "rawAreaPixels": int(raw_mask.sum()),
        "rawAreaFraction": float(raw_mask.sum() / raw_mask.size),
        "shadowRemovedPixels": int(max(raw_mask.sum() - mask.sum(), 0)),
        "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
    }


def material_color_from_mask(image_path: Path, mask_path: Path) -> list[float]:
    try:
        from PIL import Image
        import numpy as np
    except Exception:
        return [0.78, 0.78, 0.76]

    image = Image.open(image_path).convert("RGB")
    mask_image = Image.open(mask_path).convert("L")
    rgb = np.array(image).astype(np.float32) / 255.0
    mask = np.array(mask_image) > 0
    if mask.sum() == 0:
        return [0.78, 0.78, 0.76]

    pixels = rgb[mask]
    channel_max = np.max(pixels, axis=1)
    channel_min = np.min(pixels, axis=1)
    saturation = (channel_max - channel_min) / np.maximum(channel_max, 1e-6)
    luminance = (
        pixels[:, 0] * 0.2126
        + pixels[:, 1] * 0.7152
        + pixels[:, 2] * 0.0722
    )

    # Prefer saturated/colored object pixels so white backgrounds, highlights,
    # and small gray shadows do not wash out the material color.
    confident = pixels[(saturation > 0.10) | (luminance < 0.72)]
    if len(confident) >= 32:
        pixels = confident

    color = np.median(pixels, axis=0)
    return [float(max(0.0, min(1.0, channel))) for channel in color.tolist()]


def boosted_color(color: list[float]) -> list[float]:
    if len(color) != 3:
        return [0.78, 0.78, 0.76]

    rgb = [max(0.0, min(1.0, float(channel))) for channel in color]
    average = sum(rgb) / 3.0
    chroma = max(rgb) - min(rgb)
    if chroma < 0.04:
        return rgb

    boosted = [average + (channel - average) * 1.28 for channel in rgb]
    luminance = boosted[0] * 0.2126 + boosted[1] * 0.7152 + boosted[2] * 0.0722
    if luminance > 0.82:
        boosted = [channel * (0.82 / max(luminance, 1e-6)) for channel in boosted]
    if luminance < 0.18:
        boosted = [0.18 + channel * 0.82 for channel in boosted]
    return [float(max(0.0, min(1.0, channel))) for channel in boosted]


def material_profile_for_object(world_object: dict[str, Any], base_color: list[float]) -> dict[str, Any]:
    text = object_text(world_object)
    asset_card = world_object.get("assetCard") or {}
    asset_kind = str(asset_card.get("assetKind") or "").lower() if isinstance(asset_card, dict) else ""
    kind_type, category = object_kind(world_object)

    color = boosted_color(base_color)
    chroma = max(color) - min(color)
    luminance = color[0] * 0.2126 + color[1] * 0.7152 + color[2] * 0.0722
    needs_preset = chroma < 0.07 or luminance > 0.88

    preset: Optional[list[float]] = None
    roughness = 0.68
    metallic = 0.0

    if any(token in text for token in ("payment", "reader", "terminal", "card_reader")) or asset_kind == "paymentdevice":
        preset = [0.18, 0.18, 0.17]
        roughness = 0.42
    elif any(token in text for token in ("wallet",)):
        preset = [0.34, 0.22, 0.15]
        roughness = 0.78
    elif any(token in text for token in ("chips", "snack")):
        preset = [0.92, 0.76, 0.12]
        roughness = 0.62
    elif any(token in text for token in ("basket", "fruit_basket", "shopping_basket")) or kind_type == "basket":
        preset = [0.74, 0.62, 0.42]
        roughness = 0.82
    elif any(token in text for token in ("paper bag", "paper_bag", "shopping_bag", "bag")) or kind_type == "bag":
        preset = [0.82, 0.74, 0.60]
        roughness = 0.86
    elif any(token in text for token in ("apple",)):
        preset = [0.86, 0.20, 0.16]
        roughness = 0.56
    elif any(token in text for token in ("fruit",)):
        preset = [0.86, 0.46, 0.18]
        roughness = 0.58
    elif any(token in text for token in ("menu", "sign")) or asset_kind == "menu":
        preset = [0.05, 0.55, 0.55]
        roughness = 0.72
    elif any(token in text for token in ("cup", "coffee")) or kind_type == "cup":
        preset = [0.86, 0.84, 0.78]
        roughness = 0.52
    elif any(token in text for token in ("tray", "plate")) or asset_kind == "tray":
        preset = [0.78, 0.72, 0.62]
        roughness = 0.64
    elif (
        any(token in text for token in ("vendor", "cashier", "barista", "marker", "attendant"))
        or asset_kind == "personmarker"
        or kind_type == "npcMarker"
    ):
        preset = [0.66, 0.61, 0.46]
        roughness = 0.74
    elif category == "container" or asset_kind == "container":
        preset = [0.72, 0.64, 0.46]
        roughness = 0.82

    if preset is not None and needs_preset:
        color = preset
    elif preset is not None:
        color = [
            float(max(0.0, min(1.0, color[index] * 0.72 + preset[index] * 0.28)))
            for index in range(3)
        ]

    return {
        "color": color,
        "roughness": roughness,
        "metallic": metallic,
    }


def import_sam3d(sam3d_root: Path) -> tuple[Any, Any, Any]:
    notebook_dir = sam3d_root / "notebook"
    if not notebook_dir.exists():
        raise FileNotFoundError(f"Could not find SAM3D notebook dir: {notebook_dir}")

    sys.path.insert(0, str(notebook_dir))
    from inference import Inference, load_image, load_mask  # type: ignore

    return Inference, load_image, load_mask


def tensor_to_list(value: Any) -> list[Any]:
    if hasattr(value, "detach"):
        value = value.detach().cpu().numpy()
    if hasattr(value, "tolist"):
        return value.tolist()
    return list(value)


def mesh_candidates_from_output(output: dict[str, Any]) -> list[Any]:
    candidates: list[Any] = []
    for key in ("mesh", "glb"):
        source = output.get(key)
        if isinstance(source, list):
            for item in source:
                candidates.extend(expand_mesh_source(item))
        else:
            candidates.extend(expand_mesh_source(source))
    return [candidate for candidate in candidates if candidate is not None]


def expand_mesh_source(source: Any) -> list[Any]:
    if source is None:
        return []

    geometry = getattr(source, "geometry", None)
    if isinstance(geometry, dict):
        return list(geometry.values())

    dump = getattr(source, "dump", None)
    if callable(dump):
        try:
            dumped = dump()
            if isinstance(dumped, list):
                return dumped
        except Exception:
            pass

    return [source]


def extract_mesh_arrays(
    output: dict[str, Any],
) -> Optional[tuple[list[list[float]], list[list[int]], Optional[list[list[float]]]]]:
    for mesh in mesh_candidates_from_output(output):
        vertices = None
        faces = None

        if isinstance(mesh, dict):
            vertices = mesh.get("vertices") or mesh.get("verts") or mesh.get("v")
            faces = mesh.get("faces") or mesh.get("triangles") or mesh.get("f")
        else:
            vertices = getattr(mesh, "vertices", None)
            faces = getattr(mesh, "faces", None)
            if faces is None:
                faces = getattr(mesh, "triangles", None)

        if vertices is None or faces is None:
            continue

        vertices_list = tensor_to_list(vertices)
        faces_list = tensor_to_list(faces)

        clean_vertices = [[float(v[0]), float(v[1]), float(v[2])] for v in vertices_list]
        clean_faces = [[int(index) for index in face[:3]] for face in faces_list if len(face) >= 3]
        vertex_colors = extract_vertex_colors(mesh, len(clean_vertices))

        if len(clean_vertices) >= 3 and clean_faces:
            return clean_vertices, clean_faces, vertex_colors

    return None


def extract_vertex_colors(mesh: Any, vertex_count: int) -> Optional[list[list[float]]]:
    candidates: list[Any] = []
    if isinstance(mesh, dict):
        candidates.extend(
            [
                mesh.get("vertex_colors"),
                mesh.get("vertexColors"),
                mesh.get("colors"),
                mesh.get("color"),
                mesh.get("rgba"),
                mesh.get("rgb"),
            ]
        )
    else:
        candidates.extend(
            [
                getattr(mesh, "vertex_colors", None),
                getattr(mesh, "vertexColors", None),
                getattr(mesh, "colors", None),
                getattr(mesh, "color", None),
            ]
        )
        visual = getattr(mesh, "visual", None)
        if visual is not None:
            candidates.extend(
                [
                    getattr(visual, "vertex_colors", None),
                    getattr(visual, "colors", None),
                ]
            )

    for candidate in candidates:
        colors = normalize_vertex_colors(candidate, vertex_count)
        if colors is not None:
            return colors

    return texture_vertex_colors(mesh, vertex_count)


def texture_vertex_colors(mesh: Any, vertex_count: int) -> Optional[list[list[float]]]:
    visual = getattr(mesh, "visual", None)
    if visual is None:
        return None

    uv = getattr(visual, "uv", None)
    material = getattr(visual, "material", None)
    image = getattr(material, "image", None) if material is not None else None
    if uv is None or image is None:
        return None

    try:
        import numpy as np
        from PIL import Image
    except Exception:
        return None

    try:
        uv_values = np.array(tensor_to_list(uv), dtype=np.float32)
        if uv_values.ndim != 2 or uv_values.shape[0] < vertex_count or uv_values.shape[1] < 2:
            return None

        texture = image.convert("RGB") if isinstance(image, Image.Image) else Image.fromarray(np.array(image)).convert("RGB")
        pixels = np.array(texture).astype(np.float32) / 255.0
        height, width = pixels.shape[:2]
        u = np.clip(uv_values[:vertex_count, 0], 0.0, 1.0)
        v = np.clip(uv_values[:vertex_count, 1], 0.0, 1.0)
        xs = np.rint(u * (width - 1)).astype(int)
        ys = np.rint((1.0 - v) * (height - 1)).astype(int)
        sampled = pixels[ys, xs, :3]
        return [
            [float(max(0.0, min(1.0, channel))) for channel in color]
            for color in sampled.tolist()
        ]
    except Exception:
        return None


def normalize_vertex_colors(value: Any, vertex_count: int) -> Optional[list[list[float]]]:
    if value is None:
        return None

    try:
        colors_list = tensor_to_list(value)
    except Exception:
        return None

    if not isinstance(colors_list, list) or len(colors_list) < vertex_count:
        return None

    clean_colors: list[list[float]] = []
    for item in colors_list[:vertex_count]:
        if not isinstance(item, (list, tuple)) or len(item) < 3:
            return None
        try:
            rgb = [float(item[0]), float(item[1]), float(item[2])]
        except (TypeError, ValueError):
            return None
        clean_colors.append(rgb)

    max_value = max(max(color) for color in clean_colors) if clean_colors else 0
    if max_value > 1.0:
        clean_colors = [[channel / 255.0 for channel in color] for color in clean_colors]

    return [
        [float(max(0.0, min(1.0, channel))) for channel in color]
        for color in clean_colors
    ]


def normalize_vertices(vertices: list[list[float]], target_size: list[float]) -> list[list[float]]:
    mins = [min(vertex[axis] for vertex in vertices) for axis in range(3)]
    maxs = [max(vertex[axis] for vertex in vertices) for axis in range(3)]
    extents = [max(maxs[axis] - mins[axis], 1e-6) for axis in range(3)]
    center = [(mins[axis] + maxs[axis]) / 2 for axis in range(3)]
    scale = min(target_size[axis] / extents[axis] for axis in range(3)) * 0.95

    return [
        [
            (vertex[0] - center[0]) * scale,
            (vertex[1] - center[1]) * scale,
            (vertex[2] - center[2]) * scale,
        ]
        for vertex in vertices
    ]


def usd_array(values: list[Any]) -> str:
    return "[" + ", ".join(str(value) for value in values) + "]"


def usd_points(points: list[list[float]]) -> str:
    return "[" + ", ".join(f"({x:.6f}, {y:.6f}, {z:.6f})" for x, y, z in points) + "]"


def usd_colors(colors: list[list[float]]) -> str:
    return "[" + ", ".join(f"({r:.4f}, {g:.4f}, {b:.4f})" for r, g, b in colors) + "]"


def write_usda_mesh(
    output: dict[str, Any],
    output_path: Path,
    target_size: list[float],
    color: Optional[list[float]] = None,
    roughness: float = 0.68,
    metallic: float = 0.0,
) -> bool:
    mesh_arrays = extract_mesh_arrays(output)
    if mesh_arrays is None:
        return False

    vertices, faces, vertex_colors = mesh_arrays
    vertices = normalize_vertices(vertices, target_size)
    face_counts = [3 for _ in faces]
    face_indices = [index for face in faces for index in face]
    color = color or [0.78, 0.78, 0.76]
    display_color = ""
    if vertex_colors is not None:
        display_color = f"""
        color3f[] primvars:displayColor = {usd_colors(vertex_colors)} (
            interpolation = "vertex"
        )"""

    if vertex_colors is not None:
        shader_body = f"""
            def Shader "DisplayColorReader"
            {{
                uniform token info:id = "UsdPrimvarReader_float3"
                token inputs:varname = "displayColor"
                color3f inputs:fallback = ({color[0]:.4f}, {color[1]:.4f}, {color[2]:.4f})
                color3f outputs:result
            }}

            def Shader "PreviewSurface"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor.connect = </GeneratedObject/Looks/GeneratedMaterial/DisplayColorReader.outputs:result>
                float inputs:roughness = {roughness:.4f}
                float inputs:metallic = {metallic:.4f}
                token outputs:surface
            }}"""
    else:
        shader_body = f"""
            def Shader "PreviewSurface"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = ({color[0]:.4f}, {color[1]:.4f}, {color[2]:.4f})
                float inputs:roughness = {roughness:.4f}
                float inputs:metallic = {metallic:.4f}
                token outputs:surface
            }}"""

    text = f"""#usda 1.0
(
    defaultPrim = "GeneratedObject"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "GeneratedObject"
{{
    def Mesh "Mesh" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {{
        uniform token subdivisionScheme = "none"
        int[] faceVertexCounts = {usd_array(face_counts)}
        int[] faceVertexIndices = {usd_array(face_indices)}
        point3f[] points = {usd_points(vertices)}
{display_color}
        rel material:binding = </GeneratedObject/Looks/GeneratedMaterial>
    }}

    def Scope "Looks"
    {{
        def Material "GeneratedMaterial"
        {{
            token outputs:surface.connect = </GeneratedObject/Looks/GeneratedMaterial/PreviewSurface.outputs:surface>
{shader_body}
        }}
    }}
}}
"""
    output_path.write_text(text, encoding="utf-8")
    return True


def mesh_export_stats(output: dict[str, Any]) -> dict[str, Any]:
    mesh_candidates = mesh_candidates_from_output(output)
    mesh = mesh_candidates[0] if mesh_candidates else None

    stats: dict[str, Any] = {
        "hasMesh": mesh is not None,
        "outputKeys": sorted(str(key) for key in output.keys()),
        "meshCandidateCount": len(mesh_candidates),
    }
    if mesh is None:
        return stats

    stats["meshType"] = type(mesh).__name__
    if isinstance(mesh, dict):
        stats["meshKeys"] = sorted(str(key) for key in mesh.keys())
    else:
        stats["meshAttributes"] = sorted(
            name
            for name in dir(mesh)
            if not name.startswith("_")
        )[:80]
        visual = getattr(mesh, "visual", None)
        if visual is not None:
            stats["meshVisualType"] = type(visual).__name__
            stats["meshVisualAttributes"] = sorted(
                name
                for name in dir(visual)
                if not name.startswith("_")
            )[:80]

    mesh_arrays = extract_mesh_arrays(output)
    if mesh_arrays is None:
        stats.update(
            {
                "exportableMesh": False,
                "vertexCount": 0,
                "faceCount": 0,
                "hasVertexColors": False,
            }
        )
        return stats

    vertices, faces, vertex_colors = mesh_arrays
    stats.update(
        {
            "exportableMesh": True,
            "vertexCount": len(vertices),
            "faceCount": len(faces),
            "hasVertexColors": vertex_colors is not None,
        }
    )
    return stats


def save_gaussian_splat(output: dict[str, Any], output_path: Path) -> bool:
    if "gs" in output:
        output["gs"].save_ply(str(output_path))
        return True

    gaussian = output.get("gaussian")
    if isinstance(gaussian, list):
        gaussian = gaussian[0] if gaussian else None
    if gaussian is not None and hasattr(gaussian, "save_ply"):
        gaussian.save_ply(str(output_path))
        return True

    return False


def save_textured_glb(output: dict[str, Any], output_path: Path) -> bool:
    glb = output.get("glb")
    if isinstance(glb, list):
        glb = next((item for item in glb if item is not None), None)
    if glb is None:
        return False

    export = getattr(glb, "export", None)
    if not callable(export):
        return False

    try:
        export(str(output_path))
        return output_path.exists()
    except Exception:
        return False


def convert_usda_to_usdz(usda_path: Path, usdz_path: Path, usdzip_path: Optional[str]) -> bool:
    if not usdzip_path:
        usdzip_path = shutil.which("usdzip")
    if not usdzip_path:
        return False

    try:
        subprocess.run(
            [usdzip_path, str(usdz_path), str(usda_path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return usdz_path.exists()
    except subprocess.CalledProcessError:
        return False


def run_sam3d_inference(
    *,
    inference: Any,
    image: Any,
    mask: Any,
    seed: int,
    texture_baking: bool,
    mesh_postprocess: bool,
    fallback: bool,
) -> tuple[dict[str, Any], dict[str, Any]]:
    info: dict[str, Any] = {
        "textureBakingRequested": bool(texture_baking),
        "textureBakingUsed": False,
        "textureBakingFallback": False,
        "meshPostprocess": bool(mesh_postprocess),
    }

    if not texture_baking:
        return inference(image, mask, seed=seed), info

    pipeline = getattr(inference, "_pipeline", None)
    merge_mask_to_rgba = getattr(inference, "merge_mask_to_rgba", None)
    if pipeline is None or not callable(merge_mask_to_rgba):
        if not fallback:
            raise RuntimeError("SAM3D texture baking requested, but this Inference object does not expose the pipeline.")
        info["textureBakingFallback"] = True
        info["textureBakingError"] = "Inference object does not expose pipeline/merge_mask_to_rgba."
        return inference(image, mask, seed=seed), info

    try:
        image_rgba = merge_mask_to_rgba(image, mask)
        output = pipeline.run(
            image_rgba,
            None,
            seed=seed,
            stage1_only=False,
            with_mesh_postprocess=mesh_postprocess,
            with_texture_baking=True,
            with_layout_postprocess=False,
            use_vertex_color=False,
        )
        info["textureBakingUsed"] = True
        return output, info
    except Exception as exc:
        if not fallback:
            raise
        clear_cuda_cache()
        info["textureBakingFallback"] = True
        info["textureBakingError"] = str(exc)
        print(f"SAM3D texture baking failed; falling back to non-baked mesh: {exc}", flush=True)
        return inference(image, mask, seed=seed), info


class SAM3DRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.inference = None
        self.load_image = None
        self.load_mask = None

    def get_inference(self) -> tuple[Any, Any, Any]:
        if self.inference is not None and self.load_image is not None and self.load_mask is not None:
            return self.inference, self.load_image, self.load_mask

        if self.args.disable_cudnn:
            import torch

            torch.backends.cudnn.enabled = False

        config_path = self.args.sam3d_root / "checkpoints" / self.args.tag / "pipeline.yaml"
        if not config_path.exists():
            raise FileNotFoundError(f"Missing SAM3D checkpoint config: {config_path}")

        Inference, load_image, load_mask = import_sam3d(self.args.sam3d_root)
        start = time.time()
        print(f"Loading SAM3D model from {config_path} ...", flush=True)
        self.inference = Inference(str(config_path), compile=self.args.compile)
        self.load_image = load_image
        self.load_mask = load_mask
        print(f"SAM3D loaded in {time.time() - start:.1f}s", flush=True)
        return self.inference, self.load_image, self.load_mask

    def run_object(
        self,
        *,
        scenario: dict[str, Any],
        world_object: dict[str, Any],
        object_dir: Path,
        host_url: str,
    ) -> dict[str, Any]:
        object_id = slug(str(world_object.get("id", "object")))
        display_name = str(world_object.get("displayName") or object_id)
        description = str(world_object.get("description") or "")
        asset_card = world_object.get("assetCard") or {}
        size = sanitize_size(world_object.get("size"))
        position = world_object.get("position")
        object_dir.mkdir(parents=True, exist_ok=True)

        image_path = object_dir / f"{object_id}_reference.png"
        mask_path = object_dir / f"{object_id}_mask.png"
        sam3d_image_path = object_dir / f"{object_id}_sam3d_input.png"
        sam3d_mask_path = object_dir / f"{object_id}_sam3d_mask.png"
        mesh_debug_path = object_dir / f"{object_id}_mesh_debug.json"
        ply_path = object_dir / f"{object_id}.ply"
        glb_path = object_dir / f"{object_id}_texture_baked.glb"
        usda_path = object_dir / f"{object_id}.usda"
        usdz_path = object_dir / f"{object_id}.usdz"

        prompt = prompt_for_object(scenario, world_object)
        if not image_path.exists() or self.args.regenerate_images:
            openai_generate_image(prompt, image_path, self.args.openai_image_model, self.args.image_size)

        mask_stats = save_foreground_mask(image_path, mask_path)
        if mask_stats.get("isEmpty"):
            raise RuntimeError(f"Generated mask for {display_name} is empty.")
        mask_stats.update(
            prepare_sam3d_input(
                image_path,
                mask_path,
                sam3d_image_path,
                sam3d_mask_path,
                self.args.sam3d_input_max_dim,
            )
        )
        material_color = material_color_from_mask(image_path, mask_path)
        material_profile = material_profile_for_object(world_object, material_color)
        mask_stats["materialColor"] = material_color
        mask_stats["materialProfile"] = material_profile

        inference, load_image, load_mask = self.get_inference()
        image = load_image(str(sam3d_image_path))
        mask = load_mask(str(sam3d_mask_path))

        start = time.time()
        try:
            clear_cuda_cache()
            object_texture_baking = self.args.texture_baking and (
                self.args.texture_baking_surfaces or not is_surface_like(world_object)
            )
            output, inference_options = run_sam3d_inference(
                inference=inference,
                image=image,
                mask=mask,
                seed=self.args.seed,
                texture_baking=object_texture_baking,
                mesh_postprocess=self.args.mesh_postprocess,
                fallback=self.args.texture_baking_fallback,
            )
            inference_options["textureBakingSkippedForSurface"] = bool(
                self.args.texture_baking and not object_texture_baking and is_surface_like(world_object)
            )
        except RuntimeError as exc:
            if "out of memory" in str(exc).lower():
                clear_cuda_cache()
            raise
        duration = time.time() - start

        mesh_stats = mesh_export_stats(output)
        mesh_stats["inferenceOptions"] = inference_options
        mask_stats["sam3dOptions"] = inference_options
        mesh_debug_path.write_text(json.dumps(mesh_stats, indent=2), encoding="utf-8")
        mesh_arrays = extract_mesh_arrays(output)
        canonical_pose = None
        if mesh_arrays is not None:
            canonical_pose = canonicalize_asset_pose(
                args=self.args,
                mesh_arrays=mesh_arrays,
                object_dir=object_dir,
                host_url=host_url,
                object_id=object_id,
                display_name=display_name,
                description=description,
                asset_card=asset_card if isinstance(asset_card, dict) else {},
                material_color=material_color,
            )
        saved_glb = save_textured_glb(output, glb_path)
        saved_ply = save_gaussian_splat(output, ply_path)
        saved_usda = write_usda_mesh(
            output,
            usda_path,
            size,
            color=material_profile["color"],
            roughness=material_profile["roughness"],
            metallic=material_profile["metallic"],
        )
        saved_usdz = saved_usda and convert_usda_to_usdz(
            usda_path,
            usdz_path,
            self.args.usdzip_path,
        )

        if saved_usdz:
            asset_path = usdz_path
            visual_format = "usdz"
            notes = "Generated image -> SAM3D mesh -> USDZ conversion. RoleplAR collider/semantics preserved."
        elif saved_usda:
            asset_path = usda_path
            visual_format = "usd"
            notes = "Generated image -> SAM3D mesh -> USDA export. RoleplAR collider/semantics preserved."
        elif saved_ply:
            asset_path = ply_path
            visual_format = "gaussianSplatPLY"
            notes = "Generated image -> SAM3D Gaussian-splat PLY. Native mesh export unavailable."
        else:
            raise RuntimeError(f"SAM3D output for {display_name} had no exportable asset.")

        if inference_options.get("textureBakingUsed"):
            notes += " Texture baking was requested and used; texture-derived mesh colors are preserved when exportable."
        elif inference_options.get("textureBakingFallback"):
            notes += " Texture baking was requested but fell back to non-baked mesh."

        clear_cuda_cache()
        result = {
            "objectId": object_id,
            "status": "realized",
            "visualFormat": visual_format,
            "assetURL": f"{host_url}/assets/{asset_path.relative_to(self.args.out_dir)}",
            "previewImageURL": f"{host_url}/assets/{image_path.relative_to(self.args.out_dir)}",
            "position": position,
            "size": size,
            "proxyShape": {
                "type": "box",
                "size": size,
            },
            "durationSeconds": duration,
            "notes": notes,
            "maskStats": mask_stats,
            "meshStats": mesh_stats,
            "canonicalPose": canonical_pose,
            "meshDebugURL": f"{host_url}/assets/{mesh_debug_path.relative_to(self.args.out_dir)}",
        }
        if saved_glb:
            result["textureBakedGLBURL"] = f"{host_url}/assets/{glb_path.relative_to(self.args.out_dir)}"
        return result


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path == "/" or self.path == "/health":
            self.write_json(
                {
                    "status": "ok",
                    "mode": "real-sam3d",
                    "modelLoaded": self.server.runner.inference is not None,
                    "outDir": str(self.server.args.out_dir),
                    "textureBaking": self.server.args.texture_baking,
                    "meshPostprocess": self.server.args.mesh_postprocess,
                    "realizeSurfaces": self.server.args.realize_surfaces,
                }
            )
            return

        if self.path.startswith("/jobs/"):
            job_id = self.path.removeprefix("/jobs/").split("?", 1)[0]
            self.write_json(self.job_status(job_id))
            return

        if self.path.startswith("/assets/"):
            self.serve_asset(self.path.removeprefix("/assets/"))
            return

        self.write_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:
        if self.path == "/realize-scene-async":
            self.start_async_job()
            return

        if self.path != "/realize-scene":
            self.write_json({"error": "not found"}, status=404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            host_url = request_host_url(self.headers)
            self.write_json(self.realize_scene(payload, host_url))
        except BrokenPipeError:
            print("Client disconnected before synchronous realization response was delivered.", flush=True)
        except Exception as exc:
            self.write_json({"error": str(exc)}, status=500)

    def start_async_job(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            host_url = request_host_url(self.headers)
            job_id = str(uuid.uuid4())
            now = time.time()
            with self.server.jobs_lock:
                self.server.jobs[job_id] = {
                    "jobId": job_id,
                    "status": "queued",
                    "createdAt": now,
                    "updatedAt": now,
                    "result": None,
                    "error": None,
                }

            thread = threading.Thread(
                target=self.run_async_job,
                args=(job_id, payload, host_url),
                daemon=True,
            )
            thread.start()
            self.write_json(
                {
                    "jobId": job_id,
                    "status": "queued",
                    "pollURL": f"{host_url}/jobs/{job_id}",
                },
                status=202,
            )
        except Exception as exc:
            self.write_json({"error": str(exc)}, status=500)

    def run_async_job(self, job_id: str, payload: dict[str, Any], host_url: str) -> None:
        print(f"SAM3D job {job_id} queued.", flush=True)
        with self.server.jobs_lock:
            self.server.jobs[job_id]["status"] = "running"
            self.server.jobs[job_id]["updatedAt"] = time.time()

        try:
            result = self.realize_scene(payload, host_url, job_id=job_id)
            with self.server.jobs_lock:
                self.server.jobs[job_id]["status"] = "completed"
                self.server.jobs[job_id]["result"] = result
                self.server.jobs[job_id]["updatedAt"] = time.time()
            print(f"SAM3D job {job_id} completed.", flush=True)
        except Exception as exc:
            with self.server.jobs_lock:
                self.server.jobs[job_id]["status"] = "failed"
                self.server.jobs[job_id]["error"] = str(exc)
                self.server.jobs[job_id]["updatedAt"] = time.time()
            print(f"SAM3D job {job_id} failed: {exc}", flush=True)

    def job_status(self, job_id: str) -> dict[str, Any]:
        with self.server.jobs_lock:
            job = self.server.jobs.get(job_id)
            if job is None:
                return {"error": "job not found", "jobId": job_id}
            return dict(job)

    def realize_scene(
        self,
        payload: dict[str, Any],
        host_url: str,
        job_id: Optional[str] = None,
    ) -> dict[str, Any]:
        scenario = payload.get("scenario") or {}
        plan = payload.get("plan") or {}
        objects = plan.get("objects") or []

        job_id = job_id or str(uuid.uuid4())
        job_dir = self.server.args.out_dir / job_id
        job_dir.mkdir(parents=True, exist_ok=True)

        task_priorities = task_object_priorities(plan)
        candidate_priorities = {
            slug(str(obj.get("id", "object"))): realization_priority(obj, task_priorities)
            for obj in objects
            if should_realize_object(obj, self.server.args.realize_surfaces)
        }
        candidates = sorted(
            (obj for obj in objects if should_realize_object(obj, self.server.args.realize_surfaces)),
            key=lambda obj: candidate_priorities[slug(str(obj.get("id", "object")))],
        )
        max_objects = self.server.args.max_objects
        if max_objects > 0:
            candidates = candidates[:max_objects]
        selected_id_list = [slug(str(obj.get("id", "object"))) for obj in candidates]
        selected_ids = set(selected_id_list)
        selected_label = ", ".join(selected_id_list) if selected_id_list else "none"
        print(
            f"SAM3D job {job_id}: selected for realization: {selected_label} "
            f"(max_objects={max_objects}, realize_surfaces={self.server.args.realize_surfaces}).",
            flush=True,
        )

        realized_by_id: dict[str, dict[str, Any]] = {}
        for world_object in candidates:
            object_id = slug(str(world_object.get("id", "object")))
            try:
                print(f"SAM3D job {job_id}: realizing {object_id}.", flush=True)
                realized_by_id[object_id] = (
                    self.server.runner.run_object(
                        scenario=scenario,
                        world_object=world_object,
                        object_dir=job_dir / object_id,
                        host_url=host_url,
                    )
                )
            except Exception as exc:
                realized_by_id[object_id] = {
                    "objectId": object_id,
                    "status": "failed",
                    "visualFormat": "primitiveProxy",
                    "assetURL": None,
                    "previewImageURL": None,
                    "position": world_object.get("position"),
                    "size": sanitize_size(world_object.get("size")),
                    "proxyShape": {
                        "type": "box",
                        "size": sanitize_size(world_object.get("size")),
                    },
                    "notes": str(exc),
                }

        realized = []
        for world_object in objects:
            object_id = slug(str(world_object.get("id", "object")))
            if object_id in realized_by_id:
                realized.append(realized_by_id[object_id])
                continue

            priority = candidate_priorities.get(object_id)
            priority_note = f" selectionPriority={priority}." if priority is not None else ""
            realized.append(
                {
                    "objectId": object_id,
                    "status": "fallbackPrimitive",
                    "visualFormat": "primitiveProxy",
                    "assetURL": None,
                    "previewImageURL": None,
                    "position": world_object.get("position"),
                    "size": sanitize_size(world_object.get("size")),
                    "proxyShape": {
                        "type": "box",
                        "size": sanitize_size(world_object.get("size")),
                    },
                    "notes": (
                        "Not selected for SAM3D this request; RoleplAR keeps the primitive "
                        f"proxy interactive. selectedIds=[{selected_label}], maxObjects={max_objects}."
                        f"{priority_note}"
                    ),
                }
            )

        return {
            "jobId": job_id,
            "generatedImageURL": next(
                (item.get("previewImageURL") for item in realized if item.get("previewImageURL")),
                None,
            ),
            "objects": realized,
            "notes": "Real SAM3D service: scenario card plan normalized by RoleplAR, generated object images reconstructed by SAM3D, mesh exported to USD/USDA when available.",
        }

    def serve_asset(self, name: str) -> None:
        relative_path = Path(unquote(name))
        if relative_path.is_absolute() or ".." in relative_path.parts:
            self.write_json({"error": "invalid asset path"}, status=400)
            return

        file_path = self.server.args.out_dir / relative_path
        if not file_path.exists():
            self.write_json({"error": "asset not found"}, status=404)
            return

        content_types = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".ply": "application/octet-stream",
            ".usd": "model/vnd.usd",
            ".usda": "model/vnd.usd",
            ".usdc": "model/vnd.usd",
            ".usdz": "model/vnd.usdz+zip",
            ".glb": "model/gltf-binary",
        }
        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_types.get(file_path.suffix.lower(), "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def write_json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            print("Client disconnected before JSON response was delivered.", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8010, type=int)
    parser.add_argument("--sam3d-root", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--tag", default="hf")
    parser.add_argument("--seed", default=42, type=int)
    parser.add_argument("--compile", action="store_true")
    parser.add_argument("--disable-cudnn", action="store_true")
    parser.add_argument("--preload", action="store_true")
    parser.add_argument(
        "--max-objects",
        default=0,
        type=int,
        help="Maximum eligible objects to send to SAM3D. Use 0 or negative for all eligible objects.",
    )
    parser.add_argument(
        "--realize-surfaces",
        action="store_true",
        help="Also send counters/tables/flat surfaces to SAM3D. By default they remain stable RoleplAR layout anchors.",
    )
    parser.add_argument("--openai-image-model", default="gpt-image-1")
    parser.add_argument("--image-size", default="1024x1024")
    parser.add_argument("--sam3d-input-max-dim", default=512, type=int)
    parser.add_argument("--canonicalize-assets-with-vlm", action="store_true")
    parser.add_argument("--openai-vlm-model", default="gpt-4.1-mini")
    parser.add_argument(
        "--texture-baking",
        action="store_true",
        help="Ask SAM3D to run its texture-baking path, then preserve texture-derived colors when the output is exportable to USD.",
    )
    parser.add_argument(
        "--texture-baking-surfaces",
        action="store_true",
        help="Also texture-bake large support surfaces. Off by default because counters/tables can be slow and block polling.",
    )
    parser.add_argument(
        "--mesh-postprocess",
        action="store_true",
        help="Ask SAM3D to run mesh postprocessing. This can improve some meshes but costs more time/memory.",
    )
    parser.add_argument(
        "--no-texture-baking-fallback",
        dest="texture_baking_fallback",
        action="store_false",
        help="Fail the object instead of rerunning without texture baking when SAM3D texture baking errors.",
    )
    parser.set_defaults(texture_baking_fallback=True)
    parser.add_argument("--regenerate-images", action="store_true")
    parser.add_argument("--usdzip-path", default=None)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    runner = SAM3DRunner(args)
    if args.preload:
        runner.get_inference()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.args = args
    server.runner = runner
    server.jobs = {}
    server.jobs_lock = threading.Lock()
    print(f"Real SAM3D service running at http://{args.host}:{args.port}", flush=True)
    print(f"Assets served from {args.out_dir}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
