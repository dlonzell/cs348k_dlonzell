#!/usr/bin/env python3
"""No-dependency mock SAM 3D realization service.

This service implements the same HTTP contract the visionOS app expects from the
future GPU-backed SAM 3D service. It does not run SAM 3D. It writes small
placeholder .ply files and returns one "realized" object per planned object so
the app-side bridge, cache, reconciliation, and RealityKit proxy path can be
tested immediately.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parent
ASSET_DIR = ROOT / "generated_assets"


def slug(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_]+", "_", value.strip().lower())
    return value.strip("_") or "object"


def ply_for_object(object_id: str, size: list[float]) -> str:
    width = max(float(size[0]), 0.02)
    height = max(float(size[1]), 0.02)
    depth = max(float(size[2]), 0.02)
    x = width / 2
    y = height / 2
    z = depth / 2

    vertices = [
        (-x, -y, -z),
        (x, -y, -z),
        (x, y, -z),
        (-x, y, -z),
        (-x, -y, z),
        (x, -y, z),
        (x, y, z),
        (-x, y, z),
    ]
    faces = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]

    lines = [
        "ply",
        "format ascii 1.0",
        f"comment mock placeholder for {object_id}",
        f"element vertex {len(vertices)}",
        "property float x",
        "property float y",
        "property float z",
        f"element face {len(faces)}",
        "property list uchar int vertex_indices",
        "end_header",
    ]
    lines.extend(f"{vx:.4f} {vy:.4f} {vz:.4f}" for vx, vy, vz in vertices)
    lines.extend("4 " + " ".join(str(index) for index in face) for face in faces)
    return "\n".join(lines) + "\n"


def proxy_shape_type(world_object: dict) -> str:
    kind = world_object.get("kind", {})
    if isinstance(kind, dict):
        kind_type = kind.get("type", "")
        category = kind.get("category", "")
    else:
        kind_type = str(kind)
        category = ""

    if kind_type == "cup" or category == "container":
        return "cylinder"
    if kind_type == "npcMarker" or category == "marker":
        return "uprightBox"
    return "box"


def realize(payload: dict, host_url: str, real_asset_path: Optional[Path] = None) -> dict:
    plan = payload.get("plan", {})
    objects = plan.get("objects", [])
    job_id = str(uuid.uuid4())
    realized = []

    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    for world_object in objects:
        object_id = slug(str(world_object.get("id", "object")))
        size = world_object.get("size") or [0.1, 0.1, 0.1]
        if len(size) != 3:
            size = [0.1, 0.1, 0.1]

        file_name = f"{job_id}_{object_id}.ply"
        file_path = ASSET_DIR / file_name
        using_real_asset = real_asset_path is not None and real_asset_path.exists()
        if using_real_asset:
            shutil.copyfile(real_asset_path, file_path)
        else:
            file_path.write_text(ply_for_object(object_id, size), encoding="utf-8")

        realized.append(
            {
                "objectId": object_id,
                "status": "realized",
                "visualFormat": "gaussianSplatPLY",
                "assetURL": f"{host_url}/assets/{file_name}",
                "position": world_object.get("position"),
                "size": size,
                "proxyShape": {
                    "type": proxy_shape_type(world_object),
                    "size": size,
                },
                "notes": (
                    f"Real SAM 3D artifact bridged from {real_asset_path.name}; rendered with primitive interaction proxy."
                    if using_real_asset
                    else "Mock realization: placeholder PLY, not SAM 3D output."
                ),
            }
        )

    return {
        "jobId": job_id,
        "generatedImageURL": None,
        "objects": realized,
        "notes": (
            "Bridge service response with a real SAM 3D artifact served as gaussianSplatPLY."
            if real_asset_path is not None and real_asset_path.exists()
            else "Mock service response. Replace this with image generation, segmentation, and SAM 3D reconstruction on the GPU service."
        ),
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path == "/" or self.path == "/health":
            self.write_json({"status": "ok", "mode": "mock"})
            return

        if self.path == "/layout-plan":
            self.serve_layout_plan()
            return

        if self.path.startswith("/assets/"):
            self.serve_asset(self.path.removeprefix("/assets/"))
            return

        self.write_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:
        if self.path != "/realize-scene":
            self.write_json({"error": "not found"}, status=404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            payload = json.loads(body.decode("utf-8"))
            host_url = f"http://{self.headers.get('Host')}"
            self.write_json(realize(payload, host_url, self.server.real_asset_path))
        except Exception as exc:  # Keep this mock debuggable from the app UI.
            self.write_json({"error": str(exc)}, status=500)

    def serve_asset(self, name: str) -> None:
        file_name = Path(unquote(name)).name
        file_path = ASSET_DIR / file_name
        if not file_path.exists():
            self.write_json({"error": "asset not found"}, status=404)
            return

        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_layout_plan(self) -> None:
        plan_path = self.server.layout_plan_path
        if plan_path is None:
            self.write_json({"error": "no layout plan configured"}, status=404)
            return
        if not plan_path.exists():
            self.write_json({"error": f"layout plan not found: {plan_path}"}, status=404)
            return

        data = plan_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def write_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8010, type=int)
    parser.add_argument(
        "--real-asset",
        type=Path,
        default=None,
        help="Optional path to a real SAM 3D Gaussian splat .ply to serve for each realized object.",
    )
    parser.add_argument(
        "--layout-plan",
        type=Path,
        default=None,
        help="Optional path to a RoleplAR InteractionWorldPlan JSON served at /layout-plan.",
    )
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.real_asset_path = args.real_asset
    server.layout_plan_path = args.layout_plan
    print(f"Mock SAM 3D service running at http://{args.host}:{args.port}")
    if args.real_asset:
        mode = "real artifact" if args.real_asset.exists() else "missing real artifact"
        print(f"SAM 3D bridge mode: {mode} ({args.real_asset})")
    if args.layout_plan:
        mode = "layout plan" if args.layout_plan.exists() else "missing layout plan"
        print(f"SAM 3D layout-plan mode: {mode} ({args.layout_plan})")
    server.serve_forever()


if __name__ == "__main__":
    main()
