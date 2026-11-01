//  Look4Sat iOS port — radar scope (polar display)
//  Re-implements the Android Compose RadarView as a SwiftUI Canvas.
//  License: GPL-3.0
import SwiftUI
import Look4SatCore

/// A polar radar display: azimuth ring with elevation-scaled radius,
/// a sweep line, and one blip per visible satellite.
struct RadarScope: View {
    /// Blips to plot. Azimuth in degrees (0=N), elevation in degrees.
    let blips: [RadarBlip]
    /// Optional sweep angle in degrees, animated by the caller.
    var sweepAngle: Double = 0.0
    var minElevationDeg: Double = 0.0

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2 - 4

            // Rings
            for ring in stride(from: 0.0, through: 1.0, by: 0.25) {
                let r = maxR * ring
                var p = Path()
                p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(p, with: .color(.gray.opacity(0.35)), lineWidth: ring == 1.0 ? 1.5 : 0.5)
            }

            // Crosshairs + N/E/S/W labels
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - maxR, y: c.y)); p.addLine(to: CGPoint(x: c.x + maxR, y: c.y))
                p.move(to: CGPoint(x: c.x, y: c.y - maxR)); p.addLine(to: CGPoint(x: c.x, y: c.y + maxR))
            }, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)

            let labels: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
            for (text, deg) in labels {
                let rad = deg * .pi / 180
                let pos = CGPoint(x: c.x + Double(maxR) * 0.85 * sin(rad),
                                  y: c.y - Double(maxR) * 0.85 * cos(rad))
                ctx.draw(Text(text).font(.caption2).foregroundStyle(.secondary),
                         at: pos, anchor: .center)
            }

            // Sweep line
            let sw = sweepAngle * .pi / 180
            ctx.stroke(Path { p in
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + maxR * sin(sw), y: c.y - maxR * cos(sw)))
            }, with: .color(.green.opacity(0.7)), lineWidth: 1.5)

            // Blips
            for b in blips {
                let r = elevationFraction(b.elevationDeg) * maxR
                let rad = b.azimuthDeg * .pi / 180
                let pt = CGPoint(x: c.x + r * sin(rad), y: c.y - r * cos(rad))
                let d: CGFloat = 6
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - d/2, y: pt.y - d/2, width: d, height: d)),
                         with: .color(b.color))
            }
        }
        .accessibilityLabel("Radar scope with \(blips.count) satellite blips")
    }

    /// Map an elevation to a fraction of the radius (higher = further out).
    private func elevationFraction(_ elDeg: Double) -> Double {
        guard elDeg > minElevationDeg else { return 0 }
        let top = minElevationDeg + 75.0   // 90° clamped display scale
        return min((elDeg - minElevationDeg) / (top - minElevationDeg), 1.0)
    }
}

/// One satellite to plot on the scope.
struct RadarBlip: Identifiable, Hashable {
    let id: Int
    let name: String
    let azimuthDeg: Double
    let elevationDeg: Double
    let color: Color

    init(id: Int, name: String, azimuthDeg: Double, elevationDeg: Double, color: Color = .blue) {
        self.id = id
        self.name = name
        self.azimuthDeg = azimuthDeg
        self.elevationDeg = elevationDeg
        self.color = color
    }
}

/// The Radar feature screen: scope + countdown for the next pass.
struct RadarFeatureView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sweep: Double = 0.0
    @State private var selected: Int? = nil

    private var blips: [RadarBlip] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var out: [RadarBlip] = []
        for (cat, list) in model.passesMap {
            for p in list where p.aosTime <= nowMs && nowMs <= p.losTime {
                let pos = p.orbitalObject.getPosition(model.station, nowMs)
                out.append(RadarBlip(id: cat, name: p.name,
                                      azimuthDeg: pos.azimuth * RAD2DEG,
                                      elevationDeg: pos.elevation * RAD2DEG))
                break
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 12) {
            RadarScope(blips: blips, sweepAngle: sweep,
                       minElevationDeg: model.passes.minElevation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let next = nextPass {
                NextPassTimerRow(pass: next, timeNowMs: Int64(Date().timeIntervalSince1970 * 1000),
                                 utc: model.settings.stateOfUtc)
            } else {
                Text("No satellite currently in view").foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            // 4-second sweep period, 60 fps.
            let start = Date()
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    let t = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 4.0)
                    sweep = t / 4.0 * 360.0
                }
            }
        }
        .navigationTitle("Radar")
    }

    private var nextPass: OrbitalPass? {
        model.passesMap.values.flatMap { $0 }
            .filter { $0.aosTime > Int64(Date().timeIntervalSince1970 * 1000) }
            .min { $0.aosTime < $1.aosTime }
    }
}

/// AOS/LOS countdown row (mirrors the Android TimerRow).
struct NextPassTimerRow: View {
    let pass: OrbitalPass
    let timeNowMs: Int64
    let utc: Bool

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(pass.name).font(.headline)
                Spacer()
                Text(countdown).font(.system(.body, design: .monospaced))
            }
            ProgressView(value: pass.progressAt(timeNowMs))
            HStack {
                Text(Self.fmt.string(from: Date(timeIntervalSince1970: Double(pass.aosTime) / 1000)))
                Text("→")
                Text(Self.fmt.string(from: Date(timeIntervalSince1970: Double(pass.losTime) / 1000)))
                Spacer()
                Text(String(format: "max %.0f°", pass.maxElevation)).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var countdown: String {
        let secs = Int((pass.aosTime - timeNowMs) / 1000)
        if secs <= 0 { return "in view" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m \(secs % 60)s"
    }
}
