# EyePals

EyePals is an accessibility-first native iOS app for blind and low-vision users. It provides:

- `Read Text`: live OCR with Google ML Kit Text Recognition v2 and VoiceOver announcements.
- `Face Recognition`: fully on-device face enrollment and matching using Vision plus a bundled Core ML embedding model.
- `Settings`: speech throttling, sensitivity tuning, and onboarding guidance.

## Requirements

- Xcode 16 or newer
- iOS 17.0+
- CocoaPods
- The ONNX face embedding model `arcface_fresh.onnx`

## Setup

1. Run `pod install`.
2. Open `EyePals.xcworkspace`.
3. Download `arcface_fresh.onnx` into `tools/face_model/models/` before building locally.
4. Build and run on a physical iPhone because the app depends on the camera.

## Face Model Prep

The face-model tooling now uses the verified ONNX model already in the repo:

- model: `tools/face_model/models/arcface_fresh.onnx`
- runtime: ONNX Runtime on iOS
- validation/package scripts: `tools/face_model`

The model file is not committed to git because GitHub blocks files over 100 MB. Fetch it locally before building, or let GitHub Actions download it during CI.

Start with: `tools\\face_model\\README.md`

## Face Embedding Model Contract

The app loads `arcface_fresh.onnx` at runtime with ONNX Runtime. The model accepts a single `112x112x3` float tensor input named `input_1` and emits a `512`-D embedding output named `embedding`.

## Experimental Files

The following files may exist locally for past experiments, but they are not part of the shipping build or packaging flow:

- `tools/face_model/models/mobilefacenet_scripted.pt`
- `tools/face_model/models/model_mobilefacenet.pth`

## Suggested New-Face Flow

When EyePals sees a stable unknown face across several frames, it surfaces a suggestion card instead of auto-saving. The user can:

- name and save the person locally
- discard the suggestion
- capture more samples later to improve accuracy

This keeps recognition private, explicit, and fully on-device.
