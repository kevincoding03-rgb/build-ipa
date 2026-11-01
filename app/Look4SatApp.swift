//  Look4Sat iOS port — SwiftUI app entry & main UI
//  Ported from Kotlin: app/src/main/java/com/rtbishop/look4sat/MainActivity.kt,
//  MainScreen.kt and the Compose feature modules.
//  License: GPL-3.0
//
//  This is the iOS app shell. It wires up the Look4SatCore algorithm layer
//  and provides the six tabs from the Android bottom nav:
//    Satellites / Passes / Radar / Map / Settings / Status.
//
//  - Settings persist to UserDefaults (replaces SharedPreferences).
//  - Station position comes from CoreLocation (replaces the Android
//    location settings + auto-detect).
//  - TLE data is loaded by TLESource (URLSession → local cache).
//
//  Deployment target: iOS 16.
import SwiftUI
import CoreLocation
import Look4SatCore

// MARK: - App entry

@main
struct Look4SatApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(appModel.settings.stateOfLightTheme ? .light : .dark)
        }
    }
}

// MARK: - App-wide state

final class AppModel: NSObject, ObservableObject {
    @Published var settings: OtherSettings
    @Published var passes: PassesSettings
    @Published var station: GeoPos
    @Published var satellites: [SatItem] = []
    @Published var passesMap: [Int: [OrbitalPass]] = [:]   // catnum → passes
    @Published var isRefreshing: Bool = false

    private let defaults: UserDefaults
    private let tleSource: TLESource
    private let locationMgr = CLLocationManager()
    private var tleReloadTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, tleSource: TLESource = TLESource()) {
        self.defaults = defaults
        self.tleSource = tleSource
        self.settings = Self.load(OtherSettings.self, defaults)
            ?? OtherSettings(stateOfAutoUpdate: true, stateOfSensors: true,
                             stateOfSweep: false, stateOfUtc: false,
                             stateOfLightTheme: false,
                             shouldSeeWarning: true, shouldSeeWhatsNew: true)
        self.passes = Self.load(PassesSettings.self, defaults)
            ?? PassesSettings(hoursAhead: 24, minElevation: 10.0)
        self.station = Self.load(GeoPos.self, defaults)
            ?? GeoPos(latitude: 0.0, longitude: 0.0, altitude: 0.0)

        locationMgr.delegate = self
        locationMgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: persistence

    private static func load<T: Decodable & Encodable>(_ type: T.Type, _ d: UserDefaults) -> T? {
        guard let data = d.data(forKey: "l4s-\(String(describing: T.self))") else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func persist() {
        if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "l4s-OtherSettings") }
        if let d = try? JSONEncoder().encode(passes) { defaults.set(d, forKey: "l4s-PassesSettings") }
        if let d = try? JSONEncoder().encode(station) { defaults.set(d, forKey: "l4s-GeoPos") }
    }

    // MARK: TLE / satellite loading

    @MainActor
    func loadTLEs() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let tleText: String
        if settings.stateOfAutoUpdate {
            do { tleText = try await tleSource.refresh() }
            catch { tleText = await tleSource.loadCached() }
        } else {
            tleText = await tleSource.loadCached()
        }
        applyTLEText(tleText)
    }

    private func applyTLEText(_ tleText: String) {
        let tles = TLE.parse(tleText)
        var items: [SatItem] = []
        var grouped: [Int: [OrbitalPass]] = [:]
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for tle in tles {
            guard let d = tle.data else { continue }
            items.append(SatItem(catnum: d.catnum, name: d.name))
            let obj = d.makeOrbitalObject()
            let predictor = PassPredictor(object: obj, observer: station)
            let list = predictor.findAllPasses(
                minElevationDeg: passes.minElevation,
                startMs: nowMs,
                lookaheadDays: Double(passes.hoursAhead) / 24.0
            )
            // Map the shared PredictedPass model to the OrbitalPass struct
            // used by the UI (OrbitalPass wraps an OrbitalObject + progress).
            grouped[d.catnum] = list.map { p in
                OrbitalPass(aosTime: p.aosTime,
                            aosAzimuth: p.aosAzimuth,
                            losTime: p.losTime,
                            losAzimuth: p.losAzimuth,
                            altitude: 0,
                            maxElevation: p.maxElevation,
                            orbitalObject: obj)
            }
        }
        satellites = items.sorted { $0.name < $1.name }
        passesMap = grouped
    }

    // MARK: station

    func startLocationUpdates() {
        locationMgr.requestWhenInUseAuthorization()
        locationMgr.startUpdatingLocation()
    }
}

extension AppModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        station = GeoPos(latitude: loc.coordinate.latitude,
                         longitude: loc.coordinate.longitude,
                         altitude: loc.altitude)
        persist()
        // Re-run pass prediction with the new station.
        tleReloadTask?.cancel()
        tleReloadTask = Task { await loadTLEs() }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    private enum Tab: Int, CaseIterable {
        case satellites, passes, radar, map, settings, status
    }

    @State private var tab: Tab = .satellites

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                SatellitesView()
                    .tabItem { Label(title(for: .satellites), systemImage: icon(for: .satellites)) }
            }
            .tag(Tab.satellites)
            NavigationStack {
                PassesView()
                    .tabItem { Label(title(for: .passes), systemImage: icon(for: .passes)) }
            }
            .tag(Tab.passes)
            NavigationStack {
                RadarFeatureView()
                    .tabItem { Label(title(for: .radar), systemImage: icon(for: .radar)) }
            }
            .tag(Tab.radar)
            NavigationStack {
                MapFeatureView()
                    .tabItem { Label(title(for: .map), systemImage: icon(for: .map)) }
            }
            .tag(Tab.map)
            NavigationStack {
                SettingsView()
                    .tabItem { Label(title(for: .settings), systemImage: icon(for: .settings)) }
            }
            .tag(Tab.settings)
            NavigationStack {
                StatusFeatureView()
                    .tabItem { Label(title(for: .status), systemImage: icon(for: .status)) }
            }
            .tag(Tab.status)
        }
        .task {
            model.startLocationUpdates()
            await model.loadTLEs()
        }
    }

    private func title(for t: Tab) -> String {
        switch t {
        case .satellites: return "Satellites"
        case .passes:     return "Passes"
        case .radar:      return "Radar"
        case .map:        return "Map"
        case .settings:   return "Settings"
        case .status:     return "Status"
        }
    }

    private func icon(for t: Tab) -> String {
        switch t {
        case .satellites: return "satellite"
        case .passes:     return "clock"
        case .radar:      return "dot.radiowaves.left.and.right"
        case .map:        return "map"
        case .settings:   return "gearshape"
        case .status:     return "gauge"
        }
    }
}

// MARK: - Satellites

struct SatellitesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filtered: [SatItem] {
        guard !query.isEmpty else { return model.satellites }
        return model.satellites.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || String($0.catnum).contains(query)
        }
    }

    var body: some View {
        List {
            if model.satellites.isEmpty && model.isRefreshing {
                ProgressView("Loading TLEs…")
            }
            ForEach(filtered) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(String(item.catnum)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .searchable(text: $query, prompt: "Search satellites")
        .navigationTitle("Satellites (\(model.satellites.count))")
    }
}

// MARK: - Passes

struct PassesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.passesMap.isEmpty {
                Text("No passes in the next \(model.passes.hoursAhead)h. Lower the elevation threshold or extend the window.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.passesMap.keys.sorted()), id: \.self) { catnum in
                let sat = model.satellites.first { $0.catnum == catnum }
                Section(sat?.name ?? String(catnum)) {
                    ForEach(model.passesMap[catnum] ?? [], id: \.aosTime) { p in
                        PassRow(pass: p, utc: model.settings.stateOfUtc)
                    }
                }
            }
        }
        .navigationTitle("Passes")
    }
}

struct PassRow: View {
    let pass: OrbitalPass
    let utc: Bool

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack {
            Text(Self.fmt.string(from: Date(timeIntervalSince1970: Double(pass.aosTime) / 1000)))
                .monospacedDigit()
            Text("→").foregroundStyle(.secondary)
            Text(Self.fmt.string(from: Date(timeIntervalSince1970: Double(pass.losTime) / 1000)))
                .monospacedDigit()
            Spacer()
            Text(String(format: "%.0f° max", pass.maxElevation))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Auto-update TLEs", isOn: $model.settings.stateOfAutoUpdate)
                Toggle("UTC time", isOn: $model.settings.stateOfUtc)
                Toggle("Light theme", isOn: $model.settings.stateOfLightTheme)
                Toggle("Night mode", isOn: $model.settings.stateOfNightMode)
            }
            Section("Passes") {
                Stepper("Hours ahead: \(model.passes.hoursAhead)",
                        value: $model.passes.hoursAhead, in: 1...168, step: 1)
                Slider(value: $model.passes.minElevation, in: 0...90) {
                    Text("Min elevation")
                }
            }
        }
        .onDisappear { model.persist() }
        .navigationTitle("Settings")
    }
}

