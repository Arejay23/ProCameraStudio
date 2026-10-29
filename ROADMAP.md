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

## Phase 2 — Professional manual camera controls

Extend `CaptureConfiguration` with manual ISO, shutter duration, focus position, white
balance, and exposure-bias fields, each `Optional` so "unset" means "follow auto." Discover
valid ranges from `AVCaptureDevice.activeFormat` at runtime — do not hardcode ranges, since
they differ across the ultra-wide/main/telephoto lenses on the 14 Pro. Lens selection becomes
an explicit `AVCaptureDevice.DeviceType` choice in `CaptureConfiguration` rather than the
Phase 1 "pick the richest system" default. Add exposure/focus lock as additional
configuration fields, not side-channel state.

*(Phases 3–9 unchanged from the original roadmap — see the full phase prompts already
reviewed with the user. Each should: extend `CaptureConfiguration`/`CameraServicing` rather
than replace them, route Photos I/O through `MediaStoring`, add tests for new logic, and
assume physical-device-only testing.)*
