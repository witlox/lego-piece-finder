# LegoPieceFinder

An iOS app that helps you find specific LEGO pieces in a pile. Photograph a piece from the instruction manual, then use your camera with AR overlays to spot matching pieces.

## How It Works

1. **Capture** — Take a photo of the LEGO piece illustration from the instruction manual
2. **Scan** — Point your camera at a pile of LEGO pieces
3. **Match** — The app highlights matching pieces with AR overlays:
   - **Orange** = same shape
   - **Green** = same shape + same color

## Shape Matching

The core challenge is matching a 2D manual illustration to real 3D pieces. The app uses a hybrid approach:

- **Hu moment invariants** (primary) — rotation-, scale-, and translation-invariant shape descriptors that work across the illustration-to-photo domain gap
- **Aspect ratio** comparison — quick geometric filter
- **VNFeaturePrint** (secondary) — helps differentiate pieces with similar outlines but different stud patterns
- **CIELAB color distance** — perceptually uniform color comparison for distinguishing shape-only vs shape+color matches

Weighted score: `0.6 × huMoments + 0.25 × aspectRatio + 0.15 × featurePrint`

## Tech Stack

- Swift / SwiftUI
- Vision framework (contour detection, feature prints)
- ARKit / RealityKit (AR overlays)
- CIAreaAverage (color extraction)

## Requirements

- iOS 17.0+
- Device with ARKit support (LiDAR optional)
- Xcode 16+

## Building

```bash
# Generate Xcode project
brew install xcodegen
xcodegen generate

# Open and build
open LegoPieceFinder.xcodeproj
```

Build for a physical device to use the AR scanning features. The capture flow works in the simulator.

## Project Structure

```
LegoPieceFinder/
  App/                  # Entry point and app state
  Views/                # SwiftUI views (capture, scan, AR container)
  Vision/               # Detection pipeline, contour/shape/color analysis
  AR/                   # Highlight overlay entities and management
  Utilities/            # Hu moments, color math, frame throttling, extensions
```

## Tuning

Detection thresholds in `DetectionPipeline.swift` can be adjusted for your environment:

| Threshold | Default | Effect |
|-----------|---------|--------|
| `huMomentThreshold` | 0.3 | Minimum Hu moment similarity (higher = stricter shape match) |
| `aspectRatioThreshold` | 0.5 | Minimum aspect ratio similarity |
| `shapeScoreThreshold` | 0.35 | Minimum weighted score to qualify as match |
| `colorDistanceThreshold` | 25.0 | Max CIELAB distance for color match |
