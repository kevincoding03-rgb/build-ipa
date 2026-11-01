//  Look4Sat iOS port — orbital math utilities
//  Ported from Kotlin: core/domain/.../predict/OrbitalMath.kt
//  License: GPL-3.0 (same as original)
//  Copyright (C) 2019-2026 Arty Bishop and contributors.
import Foundation

// Shared orbital math utilities used by both CelestialComputer and
// OrbitalObject (SGP4/SDP4). Package-internal, not part of the public API.

/// Greenwich Mean Sidereal Time from Julian Date, in radians [0, 2π).
/// Identical algorithm used in PREDICT v2.2.5 for both solar and satellite
/// calculations.
public func thetaGJD(jd: Double) -> Double {
    let ut = fraction(jd + 0.5)
    let aJD = jd - ut
    let tu = (aJD - 2451545.0) / 36525.0
    var gmst = 24110.54841 + tu * (8640184.812866 + tu * (0.093104 - tu * 6.2e-6))
    gmst = modulus(gmst + SEC_PER_DAY * EARTH_ROT_PER_SID_DAY * ut, SEC_PER_DAY)
    return TWO_PI * gmst / SEC_PER_DAY
}

/// Backward-compatible alias of [thetaGJD] used by earlier callers.
public func thetaGJ1_1(jd: Double) -> Double { thetaGJD(jd: jd) }

/// Fractional part of [arg].
public func fraction(_ arg: Double) -> Double { arg - floor(arg) }

/// modulo: returns [arg1] mod [arg2], result always in [0, arg2).
public func modulo(_ arg1: Double, _ arg2: Double = SEC_PER_DAY) -> Double {
    var r = arg1
    let i = floor(r / arg2)
    r -= i * arg2
    if r < 0.0 { r += arg2 }
    return r
}

/// Alias of [modulo] used by the SGP4/SDP4 propagators (matching the
/// PREDICT v2.2.5 naming).
public func modulus(_ arg1: Double, _ arg2: Double = SEC_PER_DAY) -> Double {
    modulo(arg1, arg2)
}

/// Reduce [value] to [0, 2π).
public func mod2PI(_ value: Double) -> Double {
    var r = value
    let i = floor(r / TWO_PI)
    r -= i * TWO_PI
    if r < 0.0 { r += TWO_PI }
    return r
}

/// Delta-ET: difference between Universal Time and Ephemeris Time (seconds).
/// Based on least-squares fit from 1950 to 1991 (PREDICT v2.2.5).
public func deltaET(year: Double) -> Double {
    26.465 + 0.747622 * (year - 1950) + 1.886913 * sin(TWO_PI * (year - 1975) / 33)
}

/// Convert Unix epoch milliseconds to daynum (days since 31 Dec 1979 00:00:00 UTC).
public func millisToDaynum(_ timeMillis: Int64) -> Double {
    (Double(timeMillis) - 315446400000.0) / 86400000.0
}

/// Convert daynum back to Unix epoch milliseconds.
public func daynumToMillis(_ daynum: Double) -> Int64 {
    Int64((daynum + 3651.0) * 86400000.0)
}

/// Compute the Sun's ECI position vector at [julUtc] (Julian UTC).
/// Returns [x, y, z, magnitude] in km.
/// Based on Calculate_Solar_Position() / FindSun() from PREDICT v2.2.5.
public func solarPositionECI(julUtc: Double) -> [Double] {
    let mjd = julUtc - 2415020.0
    let year = 1900 + mjd / 365.25
    let t = (mjd + deltaET(year: year) / SEC_PER_DAY) / 36525.0
    let mDeg = mod360(358.47583 + mod360(35999.04975 * t) - (0.000150 + 0.0000033 * t) * t * t)
    let m = mDeg * DEG2RAD
    let lDeg = mod360(279.69668 + mod360(36000.76892 * t) + 0.0003025 * t * t)
    let l = lDeg * DEG2RAD
    let e = 0.01675104 - (0.0000418 + 0.000000126 * t) * t
    let cDeg = (1.919460 - (0.004789 + 0.000014 * t) * t) * sin(m)
        + (0.020094 - 0.000100 * t) * sin(2 * m) + 0.000293 * sin(3 * m)
    let c = cDeg * DEG2RAD
    let oDeg = mod360(259.18 - 1934.142 * t)
    let o = oDeg * DEG2RAD
    let lsa = mod2PI(l + c - (0.00569 - 0.00479 * sin(o)) * DEG2RAD)
    let nu = mod2PI(m + c)
    var r = 1.0000002 * (1.0 - e * e) / (1.0 + e * cos(nu))
    let epsDeg = 23.452294 - (0.0130125 + (0.00000164 - 0.000000503 * t) * t) * t + 0.00256 * cos(o)
    let eps = epsDeg * DEG2RAD
    r *= ASTRONOMICAL_UNIT
    return [r * cos(lsa), r * sin(lsa) * cos(eps), r * sin(lsa) * sin(eps), r]
}

/// Convert ECI position [eciPos] = [x, y, z] (km) to geodetic [lat_rad, lon_rad, alt_km].
/// Based on Calculate_LatLonAlt() from PREDICT v2.2.5.
public func eciToGeodetic(julUtc: Double, eciPos: [Double]) -> [Double] {
    let thetaPos = atan2(eciPos[1], eciPos[0])
    let lon = mod2PI(thetaPos - thetaGJD(jd: julUtc))
    let r = sqrt(eciPos[0] * eciPos[0] + eciPos[1] * eciPos[1])
    let e2 = FLAT_FACT * (2.0 - FLAT_FACT)
    var lat = atan2(eciPos[2], r)
    var phi: Double
    var c: Double
    var i = 0
    while true {
        phi = lat
        c = 1.0 / sqrt(1.0 - e2 * sin(phi) * sin(phi))
        lat = atan2(eciPos[2] + EARTH_RADIUS * c * e2 * sin(phi), r)
        if i >= 10 || abs(lat - phi) <= EPSILON { break }
        i += 1
    }
    let alt = r / cos(lat) - EARTH_RADIUS * c
    var latFinal = lat
    if latFinal > PI_2 { latFinal -= TWO_PI }
    return [latFinal, lon, alt]
}

// Private helpers
public func mod360(_ x: Double) -> Double {
    var r = x
    let i = floor(r / 360.0)
    r -= i * 360.0
    if r < 0.0 { r += 360.0 }
    return r
}

// MARK: - Constants

public let ASTRONOMICAL_UNIT: Double = 1.49597870691e8
public let DEG2RAD: Double = 0.017453292519943295
public let RAD2DEG: Double = 57.29577951308232
public let EARTH_RADIUS: Double = 6378.137
public let EARTH_ROT_PER_SID_DAY: Double = 1.00273790934
public let EPSILON: Double = 1.0e-12
public let FLAT_FACT: Double = 3.35281066474748e-3
public let J3_HARMONIC: Double = -2.53881e-6
public let MIN_PER_DAY: Double = 1.44e3
public let SEC_PER_DAY: Double = 8.6400e4
public let SOLAR_RADIUS: Double = 6.96000e5
public let SPEED_OF_LIGHT: Double = 2.99792458e8
public let PI: Double = 3.141592653589793
public let PI_2: Double = PI / 2.0
public let TWO_PI: Double = PI * 2.0
public let TWO_THIRDS: Double = 2.0 / 3.0
public let CK2: Double = 5.413079e-4
public let CK4: Double = 6.209887e-7
public let XKE: Double = 7.43669161e-2
public let X2OV3: Double = 2.0 / 3.0
public let MSEC_PER_DAY: Double = 8.64e10

// Internal helpers used by the SGP4/SDP4 propagators and CelestialComputer.
public func invert(_ value: Double) -> Double { 1.0 / value }
public func sqr(_ value: Double) -> Double { value * value }
public func sqrtFn(_ value: Double) -> Double { value.squareRoot() }
