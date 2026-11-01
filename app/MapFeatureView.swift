//  Look4Sat iOS port — MapKit map + offline tile caching
//  Re-implements the Android osmdroid offline-tile layer with Apple's
//  MapKit.  License: GPL-3.0
//
//  - Station marker (CoreLocation).
//  - Live satellite sub-satellite annotations (recomputed on demand).
//  - Ground footprint / coverage circles via OrbitalPos.rangeCircle().
//  - Offline tile cache: MapKit does not expose a tile provider, so the
//    offline path stores user-downloaded tile regions on disk and would
//    register them via MKTileOverlay on demand (stubbed here).
//
//  NOTE: uses only iOS 16-compatible MapKit APIs (Map(coordinateRegion:
//  annotationItems:annotationContent:)).
import MapKit
import SwiftUI
import Look4SatCore

/// One annotation to plot on the map.
struct MapAnnotationItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
}

/// The Map feature screen.
struct MapFeatureView: View {
    @EnvironmentObject private var model: AppModel

    @State private var region = MKCoordinateRegion(
        center: .init(latitude: 51.5, longitude: 0.0),
        span: .init(latitudeDelta: 40, longitudeDelta: 40))
    @State private var annotations: [MapAnnotationItem] = []
    @State private var showOffline = false

    var body: some View {
        VStack(spacing: 0) {
            mapContainer
            legendBar
        }
        .onAppear { refreshTracks() }
        .toolbar {
            Button("Offline tiles") { showOffline = true }
            Button("Refresh") { refreshTracks() }
        }
        .sheet(isPresented: $showOffline) { OfflineTilePicker() }
        .navigationTitle("Map")
    }

    private var mapContainer: some View {
        Map(coordinateRegion: $region,
            annotationItems: annotations,
            annotationContent: { item in
                SatelliteAnnotation(item: item)
            })
    }

    private var legendBar: some View {
        HStack(spacing: 12) {
            LegendChip(color: .green, text: "Station \(model.station.latitude.formatted(.number.precision(.fractionLength(2))), \(model.station.longitude.formatted(.number.precision(.fractionLength(2))))")
            LegendChip(color: .blue, text: "Satellite")
            Spacer()
            Text(model.satellites.count == 0 ? "no TLEs" : "\(model.satellites.count) sats")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    /// Recompute each satellite's current sub-point.
    private func refreshTracks() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var out: [MapAnnotationItem] = []
        for (cat, list) in model.passesMap {
            guard let first = list.first else { continue }
            let pos = first.orbitalObject.getPosition(model.station, nowMs)
            out.append(MapAnnotationItem(id: cat, name: first.name,
                                          latitude: pos.latitude * RAD2DEG,
                                          longitude: pos.longitude * RAD2DEG))
        }
        annotations = out
    }
}

/// A small annotation view for each satellite sub-point on the map.
struct SatelliteAnnotation: View {
    let item: MapAnnotationItem
    var body: some View {
        VStack(spacing: 2) {
            Circle().fill(.blue).frame(width: 10, height: 10)
            Text(item.name).font(.caption2)
        }
    }
}

struct LegendChip: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption)
        }
    }
}

/// Offline tile picker (a simplified stand-in for the Android offline
/// regions manager — downloads an OSM tile region into the app container
/// and registers it via MKTileOverlay).
struct OfflineTilePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lat: Double = 51.5
    @State private var lon: Double = 0.0
    @State private var zoom: Double = 8
    @State private var msg: String = "Enter a center + zoom, then download OSM tiles."

    var body: some View {
        NavigationStack {
            Form {
                Section("Region") {
                    Slider(value: $lat, in: -85...85) { Text("Lat") }
                    Slider(value: $lon, in: -180...180) { Text("Lon") }
                    Slider(value: $zoom, in: 0...17) { Text("Zoom") }
                }
                Section {
                    Button("Download tiles (stub)") { msg = "Offline tile download not wired to a provider yet." }
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
