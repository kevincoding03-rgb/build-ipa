//  Look4Sat iOS port — satellite live status readout
//  Re-implements the Android status feature (sat position / doppler readout).
//  License: GPL-3.0
import SwiftUI
import Look4SatCore

struct StatusFeatureView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Station") {
                LabeledContent("Coordinates",
                               value: String(format: "%.4f°, %.4f°",
                                              model.station.latitude, model.station.longitude))
                LabeledContent("Altitude", value: String(format: "%.0f m", model.station.altitude))
            }

            Section("Data") {
                LabeledContent("Satellites", value: "\(model.satellites.count)")
                LabeledContent("Passes in window",
                               value: "\(model.passesMap.values.reduce(0) { $0 + $1.count })")
                LabeledContent("Refresh", value: model.isRefreshing ? "in progress…" : "idle")
                if model.settings.stateOfAutoUpdate {
                    Button("Refresh TLEs now") { Task { await model.loadTLEs() } }
                }
            }

            Section("Next pass") {
                if let p = nextPass {
                    LabeledContent("Satellite", value: p.name)
                    LabeledContent("AOS", value: passTime(p.aosTime, utc: model.settings.stateOfUtc))
                    LabeledContent("LOS", value: passTime(p.losTime, utc: model.settings.stateOfUtc))
                    LabeledContent("Max elev", value: String(format: "%.0f°", p.maxElevation))
                } else {
                    Text("None in the \(model.passes.hoursAhead)h window")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Status")
    }

    private var nextPass: OrbitalPass? {
        model.passesMap.values.flatMap { $0 }
            .filter { $0.aosTime > Int64(Date().timeIntervalSince1970 * 1000) }
            .min { $0.aosTime < $1.aosTime }
    }

    private func passTime(_ ms: Int64, utc: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = utc ? TimeZone(identifier: "UTC") : .current
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
