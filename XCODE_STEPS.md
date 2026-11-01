//  Look4Sat iOS port — Xcode project generator (run on macOS)
//  License: GPL-3.0
//
//  Xcode .xcodeproj files are machine-generated; the canonical way to
//  bootstrap is to create a fresh app project in Xcode and attach this
//  SPM package. This script automates that with xcodegen (optional) or
//  plain xcodebuild.
//
//  Manual steps (no third-party tools required):
//
//  1. Xcode → File → New → Project → iOS → App
//       • Product Name: Look4Sat
//       • Interface: SwiftUI
//       • Language: Swift
//       • Minimum Deployment: iOS 16.0
//
//  2. In the new project navigator: Look4Sat target → General
//       → Frameworks, Libraries → +
//       → Local Package… → select the ios_Look4Sat folder
//         (the one containing Package.swift).
//       → Add the "Look4SatCore" library.
//
//  3. Add app/Look4SatApp.swift to the Look4Sat app target (drag it in
//       from Finder, choosing "Create groups").
//
//  4. Delete the template ContentView.swift / Look4SatApp.swift that
//       Xcode generated (our app/Look4SatApp.swift is the entry point).
//
//  5. Look4Sat target → Info tab: import the keys from
//       Look4Sat/Look4Sat/Info.plist
//       (NSLocationWhenInUseUsageDescription,
//        NSBluetoothAlwaysUsageDescription,
//        NSCalendarsUsageDescription,
//        UIBackgroundModes = [fetch, location]).
//
//  6. Look4Sat target → Signing & Capabilities
//       → Team = your Apple ID / dev team
//       → Bundle ID = com.<you>.look4sat
//       → Automatically manage signing.
//
//  7. ⌘B to build. If there are compile errors, they will reference
//       Look4SatCore files; fix in the SPM source (the same files
//       live in this repo under Look4Sat/Look4Sat/).
//
//  8. To run tests: ⌘U with a macOS scheme selected, or run
//       `swift test` in a terminal from the ios_Look4Sat folder.
//
//  9. To produce an .ipa:
//       Product → Archive (with a physical device selected)
//       → Organizer → Distribute App → Ad Hoc / Development
//       → install on a registered device.
//
//  The SwiftUI app shell (app/Look4SatApp.swift) is intentionally thin
//  until the B-class UI migration (map/offline tiles, TLE network
//  refresh, SQLite data layer, calendar, notifications, Bluetooth
//  radio control) is complete.
