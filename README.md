# ProCamera Studio — Phase 1

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
- [ ] `⌘U` in Xcode runs the `ProCameraStudioTests` target and all four tests pass

## Known limitations (Phase 1)

- Portrait orientation only — landscape is not yet handled.
- No manual exposure/ISO/white-balance controls (Phase 2).
- No RAW/ProRAW (Phase 3), no night/long-exposure modes (Phase 4), no video (Phase 5).
- Back camera always uses the richest available system (triple camera on 14 Pro) with no
  explicit ultra-wide/main/telephoto picker yet — that arrives in Phase 2.
- No flash/torch or pinch-to-zoom control yet.
- No app icon artwork yet (placeholder slot only) — required before Phase 9 submission, not
  before on-device testing.

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
