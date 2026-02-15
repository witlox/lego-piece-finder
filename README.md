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

## Installing on iPhone / iPad

AR scanning requires a physical device. Follow these steps to install the app:

1. **Connect your device** to your Mac with a USB cable
2. **Open the project** in Xcode (`open LegoPieceFinder.xcodeproj`)
3. **Set your development team:**
   - Select the `LegoPieceFinder` project in the navigator
   - Go to the **Signing & Capabilities** tab
   - Check **Automatically manage signing**
   - Select your team from the **Team** dropdown (use your personal Apple ID if you don't have a paid developer account)
4. **Select your device** from the device dropdown in the Xcode toolbar (top bar, next to the scheme name)
5. **Trust the developer profile** on your device (first install only):
   - On your iPhone/iPad go to **Settings > General > VPN & Device Management**
   - Tap your developer profile and tap **Trust**
6. **Build and run** by pressing **Cmd+R** or clicking the play button

**Notes:**
- A free Apple ID works for development, but apps expire after 7 days and must be reinstalled. A paid Apple Developer account ($99/year) removes this limit.
- When prompted, allow camera access — the app needs it for both capturing manual photos and AR scanning.
- The device must support ARKit (iPhone 6s or later, most iPads from 2017+).

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
