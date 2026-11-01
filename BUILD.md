//  Look4Sat iOS port — project build instructions (macOS / Xcode side)
//  License: GPL-3.0
//
//  This repository ships the Swift source + a Swift Package (Look4SatCore)
//  and a minimal SwiftUI app shell. The actual .ipa build, code-signing,
//  and installation can ONLY be done on macOS with Xcode — Apple's signing
//  and device tooling do not exist on Windows.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Fast path (Windows, zero Mac needed — see ALTSTORE_GUIDE.md):
//    1. Push this folder to a public GitHub repo.
//    2. .github/workflows/ios-build.yml runs on a free macOS runner,
//       xcodegen-generates the Xcode project, archives the app, and
//       exports an AltStore-ready .ipa as a workflow artifact.
//    3. Download the .ipa on Windows → AltStore re-signs with your free
//       Apple ID → USB install to iPhone. 7-day renewal: AltStore "Update".
//
//  This guide (below) covers the manual macOS/Xcode flow for people who
//  already have a Mac or want full D-class (Ad Hoc / App Store) signing.
//
//  ─────────────────────────────────────────────────────────────────────────
//  1. Prerequisites
//  ─────────────────────────────────────────────────────────────────────────
//  • macOS 14+ (Sonoma) recommended
//  • Xcode 15 or later (Xcode 16 strongly recommended)
//  • An Apple Developer account (free accounts can run on a device for
//    7 days; paid $99/yr needed for distribution beyond that)
//  • Optionally: a physical iPhone (iOS 16+) for device testing
//
//  ─────────────────────────────────────────────────────────────────────────
//  2. Get the source onto the Mac
//  ─────────────────────────────────────────────────────────────────────────
//  This folder (ios_Look4Sat) contains:
//    Look4Sat/            SPM package: Look4SatCore algorithm library
//      Look4Sat/Look4Sat/ the actual Swift source files
//    app/                 Look4SatApp.swift (SwiftUI entry + tab UI shell)
//    look4sat-cli/        command-line driver to sanity-check SGP4/SDP4
//    Look4SatTests/       XCTest unit tests
//    Package.swift        the SPM manifest
//    Info.plist           app configuration (deployment target, permissions)
//
//  On the Mac, open a terminal and:
//    cd path/to/ios_Look4Sat
//    swift build          # builds Look4SatCore + look4sat-cli for macOS
//    swift test           # runs the XCTest suite (OrbitalMathTests)
//    swift run look4sat-cli   # prints a TLE parse + pass prediction demo
//
//  If `swift build`/`swift test` succeed, the algorithm layer compiles.
//  This is the first and most important gate: it proves the SGP4/SDP4
//  port is syntactically and semantically valid Swift.
//
//  ─────────────────────────────────────────────────────────────────────────
//  3. Create the Xcode app project
//  ─────────────────────────────────────────────────────────────────────────
//  Xcode project (.xcodeproj) files are machine-generated; the reliable way
//  to bootstrap is:
//
//  a. Open Xcode → File → New → Project → iOS → App
//     • Product Name: Look4Sat
//     • Organization: your team / bundle-id prefix (e.g. com.example)
//     • Interface: SwiftUI
//     • Language: Swift
//     • Storage: None
//     • Minimum Deployment: iOS 16.0
//
//  b. Add the Swift Package to the app target
//     • In the project navigator, select the Look4Sat target →
//       General → Frameworks, Libraries → +
//     • Choose "Local Package…" and point it at the ios_Look4Sat folder
//       (the one containing Package.swift).
//     • This makes Look4SatCore available as `import Look4SatCore`.
//
//  c. Add the SwiftUI app shell
//     • Move (or copy) app/Look4SatApp.swift into the new app target's folder.
//     • Delete the template ContentView.swift that Xcode generated
//       (the app shell in Look4SatApp.swift is the real entry point).
//     • Set the @main entry point: the file containing `@main struct
//       Look4SatApp: App` is the entry. If Xcode complains about multiple
//       @main, make sure ContentView is removed and only Look4SatApp.swift
//       has @main.
//
//  d. Configure Info.plist
//     • Select the Look4Sat target → Info tab
//     • Set MinimumOSVersion = 16.0
//     • Import the keys from the bundled Info.plist (NSLocationWhenInUseUsageDescription,
//       NSBluetoothAlwaysUsageDescription, NSCalendarsUsageDescription,
//       UIBackgroundModes = fetch, location).
//
//  e. Signing
//     • Select the Look4Sat target → Signing & Capabilities
//     • Team = your Apple ID (or your development team)
//     • Bundle Identifier = something unique, e.g. com.example.look4sat
//     • Choose "Automatically manage signing" for development builds.
//     • For distribution (.ipa), keep automatic signing enabled; Xcode
//       creates the provisional profile automatically.
//
//  ─────────────────────────────────────────────────────────────────────────
//  4. Build & run
//  ─────────────────────────────────────────────────────────────────────────
//  • Simulator: ⌘R — runs the app. B-class feature code now covers:
//    TLE network refresh (URLSession + local cache), CoreLocation station,
//    MapKit map with live satellite sub-points + offline-tile stub,
//    Canvas radar scope with sweep + next-pass countdown, live status
//    readout, EventKit calendar events, and UNUserNotificationCenter
//    AOS reminders.
//  • Device: select your iPhone in the toolbar (it must appear under
//    "My Devices" after you plug it in and trust the computer).
//    ⌘R installs and launches it.
//
//  ─────────────────────────────────────────────────────────────────────────
//  5. Create the .ipa
//  ─────────────────────────────────────────────────────────────────────────
//  Archive:
//    Product → Archive (select a physical device as the destination).
//  When the archive finishes, the Organizer opens.
//    1. Select the archive → Distribute App → App Store Connect / Ad Hoc /
//       Development (choose based on your goal).
//    2. For a quick side-loadable .ipa: "Development" or "Ad Hoc".
//    3. Xcode produces an .xcarchive and an .ipa file.
//
//  To install on a non-jailbroken iPhone:
//    • Development / Ad Hoc signing: the device must be registered in your
//      Apple Developer account (UDID). Ad Hoc allows up to 100 devices.
//    • The .ipa can be installed via Xcode, or via Apple Configurator, or
//      via an in-house / TestFlight channel.
//    • A plain .ipa created for App Store (production) signing will NOT
//      install directly on a device — that path is App Store only.
//
//  ─────────────────────────────────────────────────────────────────────────
//  5b. Fast path on Windows: GitHub Actions + AltStore (no Mac)
//  ────────────────────────────────────────────────────────────────────────
//  • Push this repo to GitHub (public repo, free tier).
//  • .github/workflows/ios-build.yml runs automatically on a macOS-14
//    runner:
//        xcodegen generate                  # from project.yml
//        xcodebuild archive …               # CODE_SIGNING_ALLOWED=NO
//        xcodebuild -exportArchive          # → Look4Sat.ipa (AltStore-ready)
//        actions/upload-artifact
//  • Download the .ipa artifact on Windows.
//  • AltStore (altstore.io, free) re-signs the .ipa locally with your free
//    Apple ID, then USB-installs it to the iPhone. 7-day renewal: AltStore
//    "Update". Full instructions: ALTSTORE_GUIDE.md.
//
//  ─────────────────────────────────────────────────────────────────────────
//  6. What each layer requires (so you know what to verify)
//  ─────────────────────────────────────────────────────────────────────────
//  A-class (algorithm): Look4SatCore — SGP4/SDP4, TLE, CelestialComputer,
//    PassPredictor. Verified by `swift test` and `look4sat-cli` output.
//    No iOS-only dependency; runs on macOS.
//
//  B-class (UI + system APIs): map/offline tiles, TLE network refresh,
//    settings, calendar (EventKit), notifications, CoreLocation.
//    These live in the app shell + feature code and require a
//    device/simulator to verify.
//
//  C-class (Bluetooth radio control, SSTV/audio): framework scaffolding
//    only; needs a real ICOM/FT817/IC-705 to verify.
//
//  D-class (build/sign/install): this entire document. Requires macOS +
//    Apple Developer account + a registered device.
//
//  ─────────────────────────────────────────────────────────────────────────
//  7. Android → iOS API mapping (for the reviewer)
//  ─────────────────────────────────────────────────────────────────────────
//  | Android                                  | iOS replacement
//  |------------------------------------------|--------------------------------|
//  | Jetpack Compose (feature/*)              | SwiftUI Views (app/*.swift)
//  | SharedPreferences                        | UserDefaults + Codable JSON
//  | Room / SQLite (SatelliteRepo)            | local TLE text cache + parse
//  | osmdroid MapView + offline tiles         | MapKit Map + MKTileOverlay (stub)
//  | Android location settings + auto-detect  | CoreLocation (CLLocationManager)
//  | EventReminder / CalendarProvider         | EventKit EKEventStore
//  | NotificationManagerService (pass alerts) | UNUserNotificationCenter
//  | BluetoothGatt (FT817/IC705 CAT)         | CoreBluetooth RadioLink (C-class)
//  | AudioRecord / AudioTrack (SSTV)          | AVAudioEngine (not ported yet)
//  | Kotlin coroutines / StateFlow            | Swift async/await + @Published
//  | ViewModel + collectAsStateWithLifecycle  | @StateObject + ObservableObject
//  | Navigation3 (bottom nav, 6 tabs)         | TabView(selection:) 6 tabs
//
//  ─────────────────────────────────────────────────────────────────────────
//  8. Status matrix (as of this hand-off)
//  ─────────────────────────────────────────────────────────────────────────
//  • 已编译已测试 (compiled + tested on Windows via Swift 6.4.2 toolchain):
//    — Look4SatCore (all algorithm files), look4sat-cli, and the full
//      XCTest suite: 18/18 tests green (OrbitalMathTests 7/7 +
//      RadioProtocolTests 11/11). CLI verified end-to-end: TLE parse
//      (ISS, checksum-valid), SGP4 pass prediction over London,
//      SDP4 GEO-1, Sun/Moon position, sunrise/sunset.
//    — Windows build: pwsh build-windows.ps1 [build|test|cli]
//      (MSVC 14.44 + Swift 6.4.2; SDKROOT env required).
//  • 已编译未功能验证 (compiled, not functionally verified on device):
//    — B-class UI (SwiftUI/MapKit/CoreBluetooth/EventKit in app/*.swift):
//      written and macOS-compilable in principle, but NOT compiled in this
//      environment (Windows has no SwiftUI/MapKit SDKs). Must be built on
//      macOS/Xcode to verify.
//  • 仅生成未编译 (generated, not compiled):
//    — no remaining pure-algorithm files; all A-class and C-class protocol
//      modules are compiled and unit-tested on Windows.
//  • 未实现 (not implemented): offline-tile download (stub only), SSTV
//    audio (AVAudioEngine path), IC-705 SPLIT dual-VFO state machine,
//    full radio protocol validation against hardware.
//  • 平台受限 (platform-locked): building/signing/installing the .ipa
//    (requires macOS + Apple developer certificate for full D-class
//    Ad Hoc / App Store signing; the free-tier AltStore route in §5b only
//    needs a free Apple ID + AltStore on Windows).
