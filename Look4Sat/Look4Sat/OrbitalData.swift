//  Look4Sat iOS port — orbital data model
//  Ported from Kotlin: core/domain/.../predict/OrbitalData.kt
//  License: GPL-3.0
import Foundation

/// Two-Line-Element-derived orbital parameters.
public struct OrbitalData {
    public let name: String
    public let epoch: Double       // YYDDD.fraction epoch
    public let meanmo: Double      // mean motion (rad/day)
    public let eccn: Double        // eccentricity
    public let incl: Double        // inclination (degrees)
    public let raan: Double        // right ascension of ascending node (degrees)
    public let argper: Double      // argument of perigee (degrees)
    public let meanan: Double      // mean anomaly (degrees)
    public let catnum: Int
    public let bstar: Double
    public let ndot: Double        // derivative of mean motion / 2

    public var xincl: Double { incl * DEG2RAD }
    public var xnodeo: Double { raan * DEG2RAD }
    public var omegao: Double { argper * DEG2RAD }
    public var xmo: Double { meanan * DEG2RAD }
    public var xno: Double { meanmo * TWO_PI / MIN_PER_DAY }
    /// Orbital period in minutes (meanmo is revolutions/day: period = 1440 / meanmo).
    public var orbitalPeriod: Double { MIN_PER_DAY / meanmo }
    /// PREDICT/SGP4 convention: the deep-space (SDP4) propagator is used for
    /// periods of 225 minutes or longer.
    public var isDeepSpace: Bool { orbitalPeriod >= 225.0 }

    /// Absolute age of this element set, used to pick the freshest data among
    /// several sources.
    public var epochDaynum: Double { Self.epochToDaynum(epoch) }

    /// Days since 31 Dec 1979, the reference point every daynum in the app is based on.
    public static func timeToDaynum(_ timeMillis: Int64) -> Double {
        millisToDaynum(timeMillis)
    }

    /// PREDICT v2.2.x: converts the TLE epoch field (YYDDD.ffff format, e.g. 19060.517
    /// = 2019 day 060.517) to a daynum (days since 31 Dec 1979 00:00:00 UTC, with
    /// 31 Dec 1979 = daynum 0.0). Raw epochs are not comparable across decades, so
    /// freshness checks must always go through this conversion.
    public static func epochToDaynum(_ epoch: Double) -> Double {
        var year = floor(epoch * 1e-3)
        let day = (epoch * 1e-3 - year) * 1000.0
        year = year < 57 ? year + 2000 : year + 1900
        let jan1Jd = julianDateOfYear(year)
        return jan1Jd + day - 2444238.5
    }

    private static func julianDateOfYear(_ theYear: Double) -> Double {
        // Meeus (Astronomical Formulae, pp. 23-25); same formula as
        // OrbitalObject.julianDateOfYear (returns JD of 0.0 Jan {year}).
        let aYear = theYear - 1
        let a = Int64(floor(aYear / 100.0))
        let b: Int64 = 2 - a + a / 4
        var i = Int64(365.25 * aYear)
        i += 429
        return Double(i) + 1720994.5 + Double(b)
    }
    public func makeOrbitalObject() -> OrbitalObject {
        isDeepSpace ? DeepSpaceObject(data: self) : NearEarthObject(data: self)
    }

    /// Check if satellite has likely decayed by the given time.
    public func hasDecayed(_ currentTimeMillis: Int64) -> Bool {
        if ndot == 0.0 { return false }
        return CelestialComputer.hasDecayed(meanMotion: meanmo, drag: ndot,
                                            epochDaynum: epochDaynum,
                                            currentDaynum: Self.timeToDaynum(currentTimeMillis))
    }
}
