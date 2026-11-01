//  Look4Sat iOS port — command-line demo / verification driver
//  Runs the pure-algorithm layer (TLE parsing + SGP4 + pass prediction)
//  without any iOS SDK dependency, so it can be built with `swift run`
//  on macOS / Linux for regression checking.
//  License: GPL-3.0
import Look4SatCore
import Foundation

// A representative LEO TLE set (ISS) used as a regression fixture.
// Fetched live from CelesTrak (2026 epoch, valid checksums).
let issTLE = """
ISS (ZARYA)
1 25544U 98067A   26304.75703383  .00006360  00000+0  12291-3 0  9993
2 25544  51.6332 344.2755 0007028 332.5119  27.5497 15.49131714592920
"""

// A GEO satellite (deep-space path, period > 225 min) to exercise SDP4.
// Synthetic GEO-1 element set (cat 26067) with valid TLE checksums.
let geoTLE = """
GEO-1
1 26067U 17008C   26304.00000000  .00000000  00000-0  00000-0 0  9992
2 26067   0.0500  45.0000 0001000   0.0000  90.0000  1.00270000    07
"""

func printHeader(_ title: String) {
    print("==== \(title) ====")
}

let now = Int64(Date().timeIntervalSince1970 * 1000)
print("Look4Sat iOS port — algorithm layer verification")
print("Run time: \(now) ms (epoch)")
print("")

// --- TLE parsing ---
printHeader("TLE parsing (ISS)")
let tles = TLE.parse(issTLE)
print("Parsed \(tles.count) TLE(s)")
for t in tles {
    guard let d = t.data else {
        print("  \(t.name): failed to parse orbital data")
        continue
    }
    print("  \(d.name) catnum=\(d.catnum) incl=\(d.incl) deg meanmo=\(d.meanmo) rev/day period=\(String(format: "%.2f", d.orbitalPeriod)) min deepSpace=\(d.isDeepSpace)")
}

// --- Pass prediction ---
printHeader("Pass prediction (ISS over London)")
if let tle = tles.first, let data = tle.data {
    let obj = data.makeOrbitalObject()
    let obs = GeoPos(latitude: 51.5, longitude: -0.1, altitude: 50.0)
    let predictor = PassPredictor(object: obj, observer: obs)
    let passes = predictor.findAllPasses(minElevationDeg: 10.0,
                                          startMs: now,
                                          lookaheadDays: 1.0)
    print("Found \(passes.count) passes in the next 24h (threshold 10°)")
    for p in passes.prefix(6) {
        print(String(format: "  AOS=%lld aosAz=%.1f° LOS=%lld losAz=%.1f° maxEl=%.1f°",
                     p.aosTime, p.aosAzimuth, p.losTime, p.losAzimuth, p.maxElevation))
    }
} else {
    print("  No ISS TLE available")
}

// --- GEO / deep-space path ---
printHeader("Deep-space (GEO) object")
let geoTles = TLE.parse(geoTLE)
for t in geoTles {
    guard let d = t.data else { print("  \(t.name): failed to parse"); continue }
    let obj = d.makeOrbitalObject()
    let obs = GeoPos(latitude: 0.0, longitude: 0.0, altitude: 0.0)
    let pos = obj.getPosition(obs, now)
    print(String(format: "  \(d.name) period=%.1f min deepSpace=%@",
                 d.orbitalPeriod, d.isDeepSpace ? "true" : "false"))
    print(String(format: "    az=%.2f el=%.2f dist=%.1f km/rate=%.2f km/s alt=%.1f km",
                 pos.azimuth * 57.29577951308232, pos.elevation * 57.29577951308232,
                 pos.distance, pos.distanceRate, pos.altitude))
}

// --- Celestial checks ---
printHeader("Celestial (Sun position, London)")
let london = GeoPos(latitude: 51.5, longitude: -0.1, altitude: 50.0)
let sun = CelestialComputer.getSunPosition(london, now)
print(String(format: "  sun az=%.2f el=%.2f RA=%.2f Dec=%.2f",
             sun.azimuth, sun.elevation, sun.rightAscension, sun.declination))
let riseSet = CelestialComputer.findSunRiseSet(london, now)
print("  next sunrise: \(riseSet.riseTimeMillis)")
print("  next sunset:  \(riseSet.setTimeMillis)")

let moon = CelestialComputer.getMoonPosition(london, now)
print(String(format: "  moon az=%.2f el=%.2f", moon.azimuth, moon.elevation))

print("")
print("Done.")
