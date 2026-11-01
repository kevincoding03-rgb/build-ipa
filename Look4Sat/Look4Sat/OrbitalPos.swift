//  Look4Sat iOS port — orbital position & pass structures
//  Ported from Kotlin: core/domain/.../predict/OrbitalPos.kt, OrbitalPass.kt
//  License: GPL-3.0
import Foundation

/// Result of a full position calculation for an orbital object at a time.
/// All angles in radians; distances in km; time in Unix ms.
public struct OrbitalPos {
    public var azimuth: Double = 0.0        // 0=N, 90=E
    public var elevation: Double = 0.0
    public var latitude: Double = 0.0       // sub-point geodetic lat
    public var longitude: Double = 0.0      // sub-point geodetic lon
    public var altitude: Double = 0.0       // km above geoid
    public var distance: Double = 0.0       // km
    public var distanceRate: Double = 0.0   // km/s
    public var theta: Double = 0.0          // ECI right ascension
    public var time: Int64 = 0
    public var phase: Double = 0.0          // 0-256 orbital phase
    public var eclipseDepth: Double = 0.0   // Earth shadow depth
    public var eclipsed: Bool = false
    public var aboveHorizon: Bool = false

    // MARK: - Doppler

    /// Shifted downlink frequency given [freq] in Hz and the current range rate.
    public func downlinkFreq(_ freq: Int64) -> Int64 {
        let f = Double(freq)
        return Int64(f * (SPEED_OF_LIGHT - distanceRate * 1000.0) / SPEED_OF_LIGHT)
    }

    /// Shifted uplink frequency given [freq] in Hz and the current range rate.
    public func uplinkFreq(_ freq: Int64) -> Int64 {
        let f = Double(freq)
        return Int64(f * (SPEED_OF_LIGHT + distanceRate * 1000.0) / SPEED_OF_LIGHT)
    }

    // MARK: - Orbital velocity

    /// Circular-orbital velocity estimate at the current altitude, in km/s.
    public func orbitalVelocity() -> Double {
        let gmEarth = 3.986004418e14 // m^3/s^2
        let earthRadiusM = 6.37e6    // m
        let radius = earthRadiusM + altitude * 1000.0
        return sqrt(gmEarth / radius) / 1000.0
    }

    // MARK: - Ground footprint / range circle

    /// Approximate ground-coverage circle (721 points) for the sub-satellite
    /// point at the current altitude.
    public func rangeCircle() -> [GeoPos] {
        var points: [GeoPos] = []
        let beta = acos(EARTH_RADIUS / (EARTH_RADIUS + altitude))
        let sinLat = sin(latitude)
        let cosLat = cos(latitude)
        let cosBeta = cos(beta)
        let sinBeta = sin(beta)
        for azimuth in 0...720 {
            let rads = Double(azimuth) * DEG2RAD
            let lat = asin(sinLat * cosBeta + cosLat * sinBeta * cos(rads))
            let lon = longitude + atan2(sin(rads) * sinBeta * cosLat, cosBeta - sinLat * sin(lat))
            points.append(GeoPos(latitude: lat * RAD2DEG, longitude: lon * RAD2DEG))
        }
        return points
    }
}

/// A predicted satellite pass over an observer.
public struct OrbitalPass {
    public var aosTime: Int64 = 0
    public var aosAzimuth: Double = 90.0
    public var losTime: Int64 = 0
    public var losAzimuth: Double = 270.0
    public var altitude: Int = 1000
    public var maxElevation: Double = 75.0
    public let orbitalObject: OrbitalObject
    public var progress: Float = 0.0
    public var hasDecayed: Bool = false

    public var catNum: Int { orbitalObject.data.catnum }
    public var name: String {
        hasDecayed ? "\(orbitalObject.data.name) (decayed?)" : orbitalObject.data.name
    }
    public var isDeepSpace: Bool { orbitalObject.data.isDeepSpace }

    /// Fraction of the pass elapsed at [timeMillis]. Deep-space objects are
    /// always in view, so they report 1.0.
    public func progressAt(_ timeMillis: Int64) -> Float {
        if isDeepSpace { return 1.0 }
        let total = Double(losTime - aosTime)
        if total <= 0 { return 0.0 }
        return Float(min(max(Double(timeMillis - aosTime) / total, 0.0), 1.0))
    }
}
