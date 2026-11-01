# ProCamera Studio — Development Roadmap (gap-fixed)

Tech stack: Swift, SwiftUI, AVFoundation, Core Image, Metal, Core ML · Target: iPhone 14 Pro · iOS 17+

This is the original 9-phase roadmap with six architectural gaps closed before Phase 1 was
implemented. Scope and phase order are unchanged — only the foundational conventions below
were added so later phases extend the codebase instead of partially rewriting it.

## Foundational conventions (apply to every phase)

1. **`CaptureConfiguration` is the single source of truth for capture intent.** Phase 1 only
   populates `position`. Phase 2 adds manual ISO/shutter/WB/focus/exposure fields to this same
   struct; Phase 3 adds a format field (processed/RAW/ProRAW); Phase 4 adds bracketing
   parameters. `CameraServicing` methods take/return this struct so its shape, not the
   protocol's methods, is what each phase extends.
2. **`CameraServicing` is a protocol, `CameraService` is its only production conformer.**
   Every phase's camera logic goes behind this seam so it stays unit-testable with a mock
   (see `MockCameraService`) without touching real hardware.
3. **All Photos-library I/O goes through `MediaStoring`/`MediaStorageService`.** RAW/DNG
   export (Phase 3), video export (Phase 5), and the gallery (Phase 7) all read/write through
   this one boundary rather than each calling `PHPhotoLibrary` directly.
4. **An XCTest target exists from Phase 1 onward.** Each phase adds tests for the logic it
   introduces instead of deferring all testing to Phase 8.
5. **Simulator cannot be used for camera testing, ever.** AVFoundation capture APIs do not
   drive a real sensor in Simulator. Every phase's test instructions assume a physical
   iPhone 14 Pro.
6. **The project is under git from Phase 1.** Each phase is reviewed as a diff against the
   previous phase's commit, matching the instruction to hand the coding assistant "existing
   project files and build errors" rather than a fresh tree.

## Phase 1 — Project architecture and camera foundation (implemented)

Delivered: `CameraServicing`/`CameraService` (session lifecycle on a private serial queue,
triple/dual/wide camera auto-discovery per position), `MediaStoring`/`MediaStorageService`
(add-only Photos authorization), `CameraViewModel` (`@MainActor`, drives permission flow,
front/rear switch, capture), SwiftUI views (`ContentView`, `CameraView`,
`CameraPreviewView`, `CameraControlsView`, `PermissionDeniedView`), Info.plist privacy keys,
and an XCTest target with four tests against mocked dependencies.

Deliberately out of scope here (per original instructions): manual controls, RAW/ProRAW,
night modes, video recording, computational photography.

Known Phase 1 limitations (see `README.md` for the full list): portrait orientation only,
single best-available camera per position (explicit ultra-wide/main/telephoto picker arrives
in Phase 2), no flash/torch/zoom yet.

## Phase 2 — Professional manual camera controls (implemented)

Delivered: `CaptureConfiguration` extended with optional manual ISO, shutter duration (`CMTime`),
exposure bias, focus lens position, and white-balance Kelvin fields, plus tap-to-focus/meter
points and exposure/focus lock flags — all still one struct, so Phase 3's format selection
extends it the same way. `CameraCapabilities` (new model) reports the active device/format's real
ISO/shutter/exposure-bias ranges and available lenses, discovered at runtime via
`AVCaptureDevice.activeFormat`, never hardcoded. Lens selection is now an explicit
`AVCaptureDevice.DeviceType` choice (ultra-wide/wide/telephoto) replacing Phase 1's "pick the
richest system" default, since manual controls apply per physical lens, not a virtual
multi-cam device. `CameraServicing.updateConfiguration` became async (session-queue dispatch +
main-thread completion) instead of blocking-sync, so dragging a slider can't stall the UI —
`CameraService` always reports back the configuration it actually applied, clamped to the
device's real ranges or falling back to auto when a mode isn't supported, so published state
never claims a manual value that isn't really active on the hardware. Tap-to-focus/meter is
handled via a `UITapGestureRecognizer` in `CameraPreviewView` converting layer points to device
points through `captureDevicePointConverted(fromLayerPoint:)`, with a UIKit-drawn reticle for
feedback. Test target grew from 4 to 7 tests.

Deliberately deferred (see `README.md`): a live exposure histogram — the roadmap allowed
skipping it "if feasible without destabilizing the camera pipeline," and a real-time histogram
needs a continuous `AVCaptureVideoDataOutput` pipeline that adds real risk to preview stability
for a feature with no effect on capture correctness.

*(Phases 3–9 unchanged from the original roadmap — see the full phase prompts already
reviewed with the user. Each should: extend `CaptureConfiguration`/`CameraServicing` rather
than replace them, route Photos I/O through `MediaStoring`, add tests for new logic, and
assume physical-device-only testing.)*
