# VLM Scene Understanding Module

This module enables vision-language model (VLM) based understanding of user interactions with virtual objects in RoleplAR.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VLMPipeline                              │
│  (Main coordinator - ties everything together)                  │
└─────────────────────┬───────────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
┌───────────────┐           ┌───────────────┐
│ SceneCapture  │           │ SceneAnalyzer │
│ (5 FPS loop)  │           │ (Mock/FastVLM)│
└───────┬───────┘           └───────────────┘
        │
        ├──► OffscreenRenderer ──► MTLTexture ──► CVPixelBuffer
        │
        ├──► HandTrackingSystem ──► Joint Positions ──► Hand Meshes
        │
        └──► WorldTrackingProvider ──► Head Position ──► Camera
```

## Files

| File | Purpose |
|------|---------|
| `VLMPipeline.swift` | Main entry point, coordinates capture + analysis |
| `SceneCapture.swift` | Capture loop, manages frame delivery |
| `OffscreenRenderer.swift` | RealityRenderer setup, renders to texture |
| `TextureConverter.swift` | MTLTexture → CVPixelBuffer conversion |
| `HandTrackingSystem.swift` | ARKit hand tracking integration |
| `HandMeshGenerator.swift` | Converts skeleton to visible spheres/cylinders |
| `ActionClassification.swift` | Data models and SceneAnalyzer protocol |
| `MockAnalyzer.swift` | Heuristic-based mock for testing |
| `FastVLMAnalyzer.swift` | Real FastVLM CoreML integration |
| `USDZLoader.swift` | Loads 3D models from usdz_project service |

## Quick Start

### Using Mock Analyzer (No Model Required)

```swift
let pipeline = VLMPipeline()

// Set up callbacks
pipeline.onPickUp = { object in
    print("User picked up: \(object)")
    // Trigger NPC response
}

pipeline.onPlace = { object, target in
    print("User placed \(object)")
}

// Start with mock analyzer
try await pipeline.startWithMockAnalyzer()

// Add scene objects (uses usdz_project service)
try await pipeline.setupRestaurantDemo()
```

### Using FastVLM (Requires Model)

```swift
let pipeline = VLMPipeline()
let analyzer = FastVLMAnalyzer()

// Load model (must be added to bundle first)
try await analyzer.loadModelFromBundle(named: "FastVLM")

// Start pipeline
try await pipeline.start(analyzer: analyzer)
```

## Setting Up FastVLM

### Step 1: Download the Model

1. Go to [Apple's FastVLM on HuggingFace](https://huggingface.co/apple/FastVLM-0.5B)
2. Download the CoreML version (`.mlpackage` or `.mlmodelc`)
3. If only PyTorch/MLX is available, convert using Apple's ml-fastvlm repo:
   ```bash
   git clone https://github.com/apple/ml-fastvlm
   cd ml-fastvlm
   python model_export/export_coreml.py --model-path FastVLM-0.5B --output FastVLM.mlpackage
   ```

### Step 2: Add to Xcode Project

1. Drag `FastVLM.mlpackage` into your Xcode project
2. Ensure "Copy items if needed" is checked
3. Ensure target membership includes RoleplAR

### Step 3: Compile the Model (Optional but Recommended)

Xcode will compile `.mlpackage` to `.mlmodelc` at build time, but you can pre-compile:
```bash
xcrun coremlcompiler compile FastVLM.mlpackage FastVLM.mlmodelc
```

## Model Requirements

| Model | Size | Memory | Speed | Recommended For |
|-------|------|--------|-------|-----------------|
| FastVLM-0.5B | ~1GB | ~2GB | ~100ms | Development, testing |
| FastVLM-1.5B | ~3GB | ~4GB | ~300ms | Better accuracy |
| FastVLM-7B | ~14GB | ~16GB | ~1s | Best accuracy (not for device) |

**Recommendation:** Start with FastVLM-0.5B for on-device inference.

## Action Types

The analyzer detects these actions:

| Action | Description |
|--------|-------------|
| `idle` | Hands at rest, no interaction |
| `reaching` | Hand moving toward an object |
| `picking_up` | Hand closing around an object |
| `holding` | Holding an object steady |
| `placing` | Putting an object down |
| `pointing` | Index finger extended |
| `waving` | Hand moving side-to-side |
| `gesturing` | Other hand movements |

## Prompt Engineering

The FastVLM analyzer uses this prompt structure:

**System Prompt:**
```
You are observing a user's hands interacting with objects in a virtual Japanese restaurant.
The scene contains virtual objects rendered in 3D. The user's hands are shown as colored
spheres at joint positions (blue = left hand, green = right hand).
```

**User Prompt:**
```
Objects in the scene: {objects}

Analyze what action the user's hands are performing with these objects.

Respond ONLY with a JSON object in this exact format:
{"action": "...", "object": "...", "target": "...", "confidence": 0.0-1.0}
```

Customize these in `FastVLMAnalyzer`:
```swift
analyzer.systemPrompt = "Your custom system prompt"
analyzer.promptTemplate = "Your custom template with {objects} placeholder"
```

## Testing Without Vision Pro

The mock analyzer uses heuristic-based detection from hand joint positions:

- Hand near object position → `reaching` or `picking_up`
- Hand stationary near object → `holding`
- Hand moving down → `placing`
- Hand at face level moving → `waving`

This allows testing the full pipeline flow before deploying to device.

## Debugging

### Save Captured Frames

```swift
// Save current frame to Photos for inspection
try await pipeline.saveCurrentFrame()
```

### Check Statistics

```swift
let stats = pipeline.getStats()
print("FPS: \(stats.fps)")
print("Analyzed: \(stats.analyzedFrames)/\(stats.totalFrames)")
```

### Adjust Capture Rate

```swift
pipeline.captureFPS = 10.0  // Increase capture rate
pipeline.analyzeEveryNthFrame = 2  // Analyze every 2nd frame
```

## Dependencies

- **ARKit** - Hand tracking and world tracking
- **RealityKit** - Offscreen rendering with RealityRenderer
- **Metal** - Texture handling
- **CoreML** - FastVLM model inference
- **Vision** - Image processing for VLM input

## Limitations

1. **Hand tracking requires Vision Pro** - Simulator doesn't support it
2. **Immersive space required** - Hand tracking only works in full immersive mode
3. **Model size** - FastVLM-0.5B is ~1GB, may impact app size
4. **Inference latency** - ~100-300ms per frame depending on model
