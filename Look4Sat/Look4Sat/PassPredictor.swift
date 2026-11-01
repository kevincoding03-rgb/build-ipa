//  Look4Sat iOS port — pass prediction use case
//  Ported from Kotlin: core/domain/.../usecase/FindPasses.kt
//  License: GPL-3.0
//
//  Finds upcoming satellite passes (AOS/LOS) over an observer using the
//  elevation threshold, by scanning the satellite's elevation over time.
import Foundation

/// A computed pass, same shape as the Kotlin data class.
public struct PredictedPass {
    public let catNum: Int
    public let aosTime: Int64
    public let aosAzimuth: Double    // degrees
    public let losTime: Int64
    public let losAzimuth: Double
    public let maxElevation: Double  // degrees
    public let maxTime: Int64
}

/// Pass predictor: scans time to find when a satellite rises above
/// [minElevationDeg] and later sets below it.
public struct PassPredictor {
    public let object: OrbitalObject
    public let observer: GeoPos

    public init(object: OrbitalObject, observer: GeoPos) {
        self.object = object
        self.observer = observer
    }

    /// Find the next pass starting from [startTimeMs], looking up to
    /// [lookaheadDays] days ahead. Returns nil if no pass found.
    public func findNextPass(
        minElevationDeg: Double = 10.0,
        startTimeMs: Int64 = 0,
        lookaheadDays: Double = 1.0
    ) -> PredictedPass? {
        let threshold = minElevationDeg * DEG2RAD
        let startDaynum = millisToDaynum(startTimeMs)
        let endDaynum = startDaynum + lookaheadDays
        let step = 30.0 / 86400.0          // 30 s resolution

        var inPass = false
        var aos: Double?
        var los: Double?
        var maxEl = -Double.greatestFiniteMagnitude
        var maxTime = startDaynum

        var t = startDaynum
        while t < endDaynum {
            let el = object.getElevation(observer, daynumToMillis(t))
            if el > threshold {
                if !inPass {
                    inPass = true
                    // refine AOS by bisection between t-step and t
                    aos = refineEdge(from: t - step, to: t, threshold: threshold, rising: true)
                }
                if el > maxEl { maxEl = el; maxTime = t }
            } else {
                if inPass {
                    inPass = false
                    los = refineEdge(from: t - step, to: t, threshold: threshold, rising: false)
                    break  // return first pass
                }
            }
            t += step
        }

        guard let aosT = aos, let losT = los, losT > aosT else { return nil }
        let aosMs = daynumToMillis(aosT)
        let losMs = daynumToMillis(losT)
        let aosPos = object.getPosition(observer, aosMs)
        let losPos = object.getPosition(observer, losMs)
        return PredictedPass(
            catNum: object.data.catnum,
            aosTime: aosMs,
            aosAzimuth: aosPos.azimuth / DEG2RAD,
            losTime: losMs,
            losAzimuth: losPos.azimuth / DEG2RAD,
            maxElevation: maxEl / DEG2RAD,
            maxTime: daynumToMillis(maxTime)
        )
    }

    /// Find all passes within [startMs, startMs + lookaheadDays*86400000).
    public func findAllPasses(
        minElevationDeg: Double = 10.0,
        startMs: Int64 = 0,
        lookaheadDays: Double = 1.0
    ) -> [PredictedPass] {
        var results: [PredictedPass] = []
        var cursor = startMs
        let window = Int64(lookaheadDays * 86_400_000)
        for _ in 0..<32 {
            guard let p = findNextPass(
                minElevationDeg: minElevationDeg,
                startTimeMs: cursor,
                lookaheadDays: lookaheadDays
            ) else { break }
            results.append(p)
            cursor = p.losTime + 1
            if p.losTime > startMs + window { break }
        }
        return results
    }

    private func refineEdge(
        from: Double, to: Double, threshold: Double, rising: Bool
    ) -> Double {
        var lo = from, hi = to
        for _ in 0..<30 {
            let mid = (lo + hi) / 2.0
            let el = object.getElevation(observer, daynumToMillis(mid))
            if (el > threshold) == rising { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2.0
    }
}
