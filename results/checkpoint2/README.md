# Checkpoint 2 Results

This folder contains intermediate results for the May 22 checkpoint.

## Main Artifact

`sam3d_layout_signal/` contains a SAM3D layout-transfer spike:

- `layout_signal_debug.png` — source image with cleaned masks plus the derived top-down RoleplAR proxy layout.
- `roleplar_loaded_layout.png` — the derived plan loaded in the RoleplAR Vision Pro simulator.
- `layout_signal_summary.csv` — compact per-object table with mask bbox, SAM3D translation/scale, normalized proxy position/size, inference time, and `.ply` size.
- `layout_signal_report.json` — detailed per-object run log.
- `roleplar_layout_plan.json` — RoleplAR-compatible `InteractionWorldPlan`.
- `mask_*.ply` — generated SAM3D Gaussian splat artifacts.
- `clean_masks/` — cleaned binary masks passed to SAM3D.

## Interpretation

This result shows that object-level SAM3D outputs can be converted into RoleplAR's plan representation and loaded in the simulator. It does not yet show accurate scene reconstruction. The RoleplAR screenshot uses primitive proxies at SAM3D-derived positions while retaining `.ply` metadata for future visual rendering work.
