# ProCamera Studio — Phase 1, 2 & 3

## Prerequisites (install these before building)

| Requirement | Why |
|---|---|
| **Xcode 15+** (full IDE, Mac App Store or developer.apple.com) | Required for the iOS 17 SDK, SwiftUI previews, simulators, and on-device signing. Command Line Tools alone cannot build/run this project. |
| **Apple ID signed into Xcode** | A free Apple ID is enough to build and run on your own iPhone. The paid Apple Developer Program ($99/yr) is only needed in Phase 9 for TestFlight/App Store submission. |
| **Physical iPhone 14 Pro + Lightning/USB-C cable** | Simulator cannot drive a real camera — AVFoundation capture APIs are non-functional there. Every phase from here on requires a physical device. |
| **Developer Mode enabled on the iPhone** | Settings → Privacy & Security → Developer Mode → toggle on → reboot. Required on iOS 16+ before Xcode can install/debug an app. |

macOS 26.5 (what this Mac is running) is current enough for the latest Xcode — no OS upgrade needed.

The project was generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (installed via
Homebrew) so a real `.xcodeproj` could be produced before Xcode was available. If you ever
edit `project.yml`, regenerate with:

```bash
cd ~/Desktop/ProCameraStudio
xcodegen generate
```

## Build and run on your iPhone

1. Open `ProCameraStudio.xcodeproj` in Xcode.
2. Select the `ProCameraStudio` target → **Signing & Capabilities** → check "Automatically
   manage signing" → choose your Apple ID as the Team.
3. Plug in your iPhone 14 Pro. On the phone, tap **Trust This Computer** when prompted.
4. Select your iPhone as the run destination (top bar, next to the scheme).
5. Press **Run (⌘R)**.
6. On first launch, iOS will refuse to open the app ("Untrusted Developer"). Go to
   Settings → General → VPN & Device Management → tap your developer certificate → **Trust**.
   Relaunch from the Home Screen or from Xcode.
7. Grant camera access when prompted. Grant "Add Photos Only" access when you tap capture.

## Build/test checklist

- [ ] Project opens in Xcode without errors
- [ ] App builds and installs on a physical iPhone 14 Pro
- [ ] Camera permission prompt appears on first launch; denying it shows the "Open Settings" screen
- [ ] Live rear-camera preview renders full-screen
- [ ] Switch-camera button flips to front camera and back
- [ ] Capture button saves a photo and it appears in Photos
- [ ] Backgrounding the app and returning keeps the preview running
- [ ] `⌘U` in Xcode runs the `ProCameraStudioTests` target and all nine tests pass
- [ ] Tapping the slider icon (top-right) shows/hides the manual controls panel
- [ ] Dragging the ISO/Shutter/EV/Focus/White Balance sliders shows an "Auto" button and an
      orange highlight while a manual value is active
- [ ] Tapping "Auto" on any row (or "Reset All") returns that control to automatic and the
      highlight disappears
- [ ] Tapping anywhere on the live preview shows a brief orange reticle and refocuses/meters there
- [ ] The lens segmented control (0.5x/1x/3x) appears only on the back camera and switches lenses
- [ ] Exposure/Focus lock buttons toggle a filled lock icon
- [ ] A "Photo / RAW / ProRAW" segmented control appears below the device-name label on the back
      camera; on the front camera it's hidden (no RAW support there)
- [ ] Switching to RAW or ProRAW and capturing shows a banner with the actual format, resolution,
      and file size (e.g. "Apple ProRAW · 8064×6048 · 84.2 MB") that fades out after ~4 seconds
- [ ] A ProRAW capture produces a noticeably larger/slower save than a Photo capture, and the
      saved asset is visible and editable as RAW in the Photos app (look for the "RAW" badge)
- [ ] Switching lens/camera away from one with RAW selected resets the format picker back to
      "Photo" automatically if the new lens doesn't support RAW

## Known limitations (Phase 1, 2 & 3)

- Portrait orientation only — landscape is not yet handled.
- No night/long-exposure modes (Phase 4), no video (Phase 5).
- No flash/torch or pinch-to-zoom control yet.
- No live exposure histogram. The original Phase 2 brief allowed skipping this "if feasible
  without destabilizing the camera pipeline" — a real-time histogram needs a continuous
  `AVCaptureVideoDataOutput` sample-buffer pipeline running alongside the photo pipeline, which
  is real added risk to preview stability for a feature with no capture-correctness impact. Left
  for a later phase rather than bolted on here.
- White balance Kelvin slider range (2000K–10000K) is a fixed, conventional UI range, not a
  device-reported one — AVFoundation exposes a max white-balance *gain*, not a documented Kelvin
  range. Actual applied gains are always clamped to the device's real `maxWhiteBalanceGain`.
- Manual settings reset to auto automatically when you switch lens or front/rear camera, since a
  different physical camera can have a different valid ISO/shutter/focus range.
- No app icon artwork yet (placeholder slot only) — required before Phase 9 submission, not
  before on-device testing.

## RAW & Apple ProRAW notes (Phase 3)

What "RAW" means here, and real limits on the iPhone 14 Pro — not aspirational claims:

- **Three capture formats, picked explicitly per shot**: Photo (HEIC, Apple's normal
  computational pipeline — Smart HDR, Deep Fusion, Night mode all apply), RAW (unprocessed
  Bayer sensor data — none of that computational processing applies, which is the whole point
  of "RAW"), and Apple ProRAW (RAW sensor data *with* Apple's computational adjustments baked
  in as editable metadata — the best of both, Apple's own innovation, only on Pro models).
- **The format picker only ever shows what the active lens actually supports**, read at
  runtime from `AVCapturePhotoOutput.availableRawPhotoPixelFormatTypes` and
  `.isAppleProRAWSupported` — never hardcoded. If RAW/ProRAW isn't available for a given
  lens/position, that option simply isn't in the list.
- **Front camera doesn't support RAW or ProRAW at all** on the 14 Pro — the picker is hidden
  there and the format silently falls back to Photo.
- **File sizes are large**: ProRAW is roughly 75–110 MB per shot (48MP), standard RAW/DNG
  somewhat less, versus ~2–5 MB for a HEIC photo. A short RAW test session can use gigabytes.
- **Capture and save both take noticeably longer** than a processed photo — more data to
  write, and Photos needs longer to generate the DNG's embedded preview.
- **The app never claims a RAW capture succeeded if it didn't.** `AVCapturePhoto.isRawPhoto`
  (not our own assumption) is checked against what was requested before reporting success;
  if the device silently handed back a processed image instead, that's surfaced as a real
  error, not a mislabeled photo.
- **Manual exposure/focus/white-balance settings from Phase 2 carry over automatically** —
  they're device-level state applied continuously, independent of which photo format is
  selected, so a RAW or ProRAW shot taken with manual ISO/shutter active uses those values.
- Saved RAW/DNG and ProRAW files go through the same add-only Photos write path as processed
  photos (`MediaStorageService` doesn't need to know the difference) and show up in the
  Photos app with Apple's native "RAW" badge and editing support.

## Implications of running a development build on your actual phone

This is not a simulator — code you run here touches your real device, your real Photos
library, and (for signing) your real Apple ID.

1. **First-launch trust step.** iOS blocks apps signed with a personal development
   certificate until you explicitly trust it in Settings → General → VPN & Device
   Management. Until you do, the app icon appears but tapping it does nothing useful.
2. **Free Apple ID → 7-day expiry.** A free-tier signing certificate expires after 7 days;
   the app will simply stop launching until you reconnect the phone to Xcode and rebuild.
   This is expected, not a bug, and recurs every week until you either keep rebuilding or
   enroll in the paid Developer Program.
3. **Developer Mode is a real security setting.** Enabling it loosens code-signing
   enforcement on the device. Turning it back off later is possible but requires a reboot
   and re-confirmation.
4. **Real writes to your Photos library.** Every successful capture lands a genuine asset in
   your actual camera roll (and syncs to iCloud Photos if you have that on) — not a sandbox.
   Test shots will show up in your library; periodically delete the obvious test photos.
5. **Add-only Photos permission, camera-only otherwise.** This build requests camera access
   and "Add Photos Only" (it cannot browse or read your existing library). No microphone, no
   network access of any kind is requested in Phase 1.
6. **Storage grows fast in later phases.** Phase 1 photos are normal JPEG/HEIC size, but once
   Phase 3 (ProRAW, ~75–110 MB/photo) and Phase 5 (ProRes video, multiple GB/minute) land,
   watch free storage on the phone before long test sessions.
7. **Battery and thermal load.** A live camera session is power-hungry; extended sessions can
   trigger iOS thermal throttling, which may reduce preview frame rate or temporarily disable
   some camera features. That's the OS protecting the device, not an app bug.
8. **Debugger attachment.** Running via Xcode (⌘R) keeps a debugger attached so you see
   console logs and crash details live. Launching the already-installed app from the Home
   Screen works too, but you lose that live diagnostic feed if something misbehaves.
9. **Interruptions.** Phone calls, Control Center's camera widget, or another app grabbing
   the camera will interrupt the session. Phase 1 handles basic background/foreground
   lifecycle; deeper interruption recovery is hardened in Phase 8.
10. **Device/App ID limits on a free account.** Free Apple ID provisioning caps how many App
    IDs you can register in a rolling 7-day window — irrelevant for just this one app, but
    worth knowing if you're also side-loading other personal projects on the same phone.
