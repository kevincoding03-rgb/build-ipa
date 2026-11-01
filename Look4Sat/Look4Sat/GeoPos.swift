//  Look4Sat iOS port — geographic observer position
//  Ported from Kotlin: core/domain/.../predict/GeoPos.kt
//  License: GPL-3.0
import Foundation

/// A geographic position (observer station or arbitrary point).
/// Coordinates in degrees; positive longitude = East (matches OrbitalObject convention).
public struct GeoPos: Hashable, Codable {
    public let latitude: Double     // degrees, -90...90
    public let longitude: Double    // degrees, -180...180, positive east
    public let altitude: Double     // meters
    public let qthLocator: String   // grid locator (nullable in original; "null" if unset)
    public let timestamp: Int64     // Unix ms

    public init(latitude: Double, longitude: Double, altitude: Double = 0.0,
                qthLocator: String = "null", timestamp: Int64 = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.qthLocator = qthLocator
        self.timestamp = timestamp
    }

    /// WGS-84 geodetic → ECI-ready [lat_rad, lon_rad, alt_km] for use with the
    /// PREDICT observer-geodetic helpers. Positive longitude = east.
    public var observerGeodetic: [Double] {
        [latitude * DEG2RAD, longitude * DEG2RAD, altitude / 1000.0]
    }
}
