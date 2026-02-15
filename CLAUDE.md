# CLAUDE.md

## Project Overview

LegoPieceFinder is a native iOS app (Swift 6 / SwiftUI) that uses ARKit and the Vision framework to find specific LEGO pieces in a pile. The user photographs a piece from the instruction manual, then points the camera at a pile — the app highlights matching pieces with AR overlays.

## Build

```bash
# Generate Xcode project (required before building)
xcodegen generate

# Build (requires Xcode, not just Command Line Tools)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project LegoPieceFinder.xcodeproj \
  -scheme LegoPieceFinder \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build

# Or open in Xcode
open LegoPieceFinder.xcodeproj
```

- Deployment target: iOS 17.0
- Swift version: 6.0 (strict concurrency)
- No external dependencies — pure Apple frameworks
- The `.xcodeproj` is gitignored and generated from `project.yml` via XcodeGen
- AR scanning requires a physical device; capture flow works in the simulator

## Project Structure

```
LegoPieceFinder/
  App/                  Entry point (LegoPieceFinderApp.swift) and AppState
  Views/                SwiftUI views — CaptureView, ScanView, ARViewContainer,
                        ReferencePreviewCard, MatchLegendOverlay
  Vision/               Detection pipeline and analysis:
                          DetectionPipeline  — actor, orchestrates per-frame matching
                          ReferenceProcessor — extracts descriptor from manual photo
                          ContourDetector    — Vision contour detection
                          ShapeDescriptor    — Hu moments + aspect ratio from contours
                          ReferenceDescriptor — data struct for reference piece
                          PieceCandidate     — match result with bbox and score
                          FeaturePrintExtractor — VNFeaturePrint extraction
                          ColorAnalyzer      — CIAreaAverage + CIELAB conversion
  AR/                   HighlightEntity (RealityKit overlays) and
                        HighlightOverlayManager (anchor/raycast management)
  Utilities/            HuMoments (7 invariants), Color+Distance (CIELAB math),
                        CGImage+Cropping, VNContour+BoundingBox, FrameThrottler
  Resources/            Assets.xcassets with app icons
```

## Architecture

- **State:** `AppState` is an `@MainActor ObservableObject` with two modes (`.capture` / `.scanning`). It holds the `ReferenceDescriptor` and is injected via `.environmentObject`.
- **Concurrency:** `DetectionPipeline` is an `actor` for thread-safe frame processing. Frame capture uses `Task.detached` + `MainActor.run` for UI updates. Swift 6 strict concurrency throughout.
- **Detection pipeline flow:**
  1. ARSession frame captured at 7 FPS (throttled by `FrameThrottler`)
  2. Downsample to max 512px, detect contours via Vision
  3. Per-contour: Hu moment similarity → aspect ratio filter → feature print comparison
  4. Weighted score: `0.60 * huMoments + 0.25 * aspectRatio + 0.15 * featurePrint`
  5. Color analysis in CIELAB space determines match type (shape-only vs shape+color)
  6. `HighlightOverlayManager` renders results as semi-transparent RealityKit planes

## Key Thresholds (DetectionPipeline.swift)

| Threshold | Default | Purpose |
|-----------|---------|---------|
| `huMomentThreshold` | 0.3 | Min Hu moment similarity to pass first filter |
| `aspectRatioThreshold` | 0.5 | Min aspect ratio similarity |
| `shapeScoreThreshold` | 0.35 | Min weighted score to qualify as match |
| `colorDistanceThreshold` | 25.0 | Max CIELAB distance for color match |

## Conventions

- All enums with only static methods use `enum` (not `struct`) to prevent instantiation (e.g., `HuMoments`, `ShapeDescriptor`, `ContourDetector`, `ReferenceProcessor`)
- MARK comments divide files into sections (`// MARK: - Thresholds`, etc.)
- UI state mutations happen on `@MainActor`; heavy processing uses actors or `Task.detached`
- Coordinate systems: Vision uses bottom-left origin with 0-1 normalized coordinates; conversion helpers are in the Utilities extensions
