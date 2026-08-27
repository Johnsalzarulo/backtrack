# BackTrack iPad — TestFlight deployment

BackTrack iPad v1 is a read-only performer app (backing tracks + lyrics). Deploy via the Apple Developer Program ($99/year); no App Store listing required.

## Prerequisites

1. Renew [Apple Developer Program](https://developer.apple.com) membership (required before device deploy).
2. Install Xcode and accept the license: `sudo xcodebuild -license`
3. Register your iPad Mini in the developer portal (Devices).

## Open the project

1. Open `BackTrack.xcodeproj` in Xcode (wraps the Swift package and iPad app target).
2. Select the **BackTrackPad** scheme and your iPad device or simulator.
3. Set **Signing & Capabilities**:
   - Team: your Apple Developer team
   - Bundle Identifier: e.g. `com.yourname.backtrack.pad` (create App ID in portal if needed)

## Build and run (USB)

1. Connect iPad via USB.
2. Product → Run (⌘R).
3. On first launch, use **Import library** and pick your Mac `BackTrack` folder (via Files/AirDrop). Only `Songs/`, `Setlists/`, and `Samples/` are copied.

## TestFlight (gig-ready updates)

1. Product → Archive (Release, Any iOS Device).
2. Distribute App → App Store Connect → Upload.
3. In App Store Connect, enable TestFlight for the build.
4. Add yourself as internal tester; install **TestFlight** on iPad and accept the invite.
5. When Mac content changes, tap **Update library** in the app (full replace) or re-import the folder.

## Run unit tests

From the repo root with Xcode selected as the active developer directory:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Golden-path tests cover ChordParser, loaders, lineup build, and the perform-only filter.

## Notes

- **Landscape only** on iPad (performer HUD).
- **Touch only** in v1 — no Bluetooth keyboard shortcuts.
- Empty setlists (all countdowns/interstitials on Mac) show **No songs in this setlist**.
- Mac app is unchanged; run with `swift run BackTrack` or the **BackTrackMac** scheme.
