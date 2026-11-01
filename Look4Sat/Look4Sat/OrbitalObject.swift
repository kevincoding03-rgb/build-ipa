//  Look4Sat iOS port — orbital object base class
//  Ported from Kotlin: core/domain/.../predict/OrbitalObject.kt
//  License: GPL-3.0
import Foundation

/// Base class for orbital objects. Two concrete implementations:
/// NearEarthObject (SGP4, period < 225 min) and DeepSpaceObject (SDP4).
///
/// The base class holds the shared ECI state, the reusable vector
/// scratch space, the cached observer geometry, and the public entry
/// points (getPosition / getElevation / getFullPosition / willBeSeen).
/// The per-propagator SGP4/SDP4 coefficient fields live on the
/// concrete subclasses, matching the Kotlin layout.
open class  OrbitalObject {
    public let data: OrbitalData

    // ECI state vectors (km, km/s)
    public var position = [Double](repeating: 0.0, count: 4)
    public var velocity = [Double](repeating: 0.0, count: 4)

    public var orbitalPos = OrbitalPos()
    public private(set) var eclipseDepth: Double = 0.0
    private var perigee: Double = 0.0
    public var gsPosTheta: Double = 0.0
    public var julUTC: Double = 0.0
    public var qoms24: Double = 0.0
    public var s4: Double = 0.0

    // Cached observer position data to avoid recalculation when the observer
    // has not moved.
    public var cachedGsLat = Double.nan
    public var cachedGsLon = Double.nan
    public var cachedGsAlt = Double.nan
    public var cachedSinLat = 0.0
    public var cachedCosLat = 0.0
    public var cachedObsC = 0.0
    public var cachedObsSq = 0.0
    public var cachedObsAchFactor = 0.0
    public var cachedObsZFactor = 0.0

    // Pre-allocated reusable vectors to avoid allocation pressure in hot loops
    public var obsPos = [Double](repeating: 0.0, count: 4)
    public var obsVel = [Double](repeating: 0.0, count: 4)
    public var rangeVector = [Double](repeating: 0.0, count: 4)
    public var rgvelVector = [Double](repeating: 0.0, count: 4)
    public var squintVector = [Double](repeating: 0.0, count: 4)

    public let julEpoch: Double

    public init(data: OrbitalData) {
        self.data = data
        julEpoch = Self.julianDateOfEpoch(data.epoch)
    }

    // MARK: - Public entry points

    /// Will this satellite ever be seen from [pos]?
    public func willBeSeen(_ pos: GeoPos) -> Bool {
        if data.meanmo < 1e-8 { return false }
        let sma = 331.25 * exp(log(MIN_PER_DAY / data.meanmo) * (2.0 / 3.0))
        let apogee = sma * (1.0 + data.eccn) - EARTH_RADIUS
        var lin = data.incl
        if lin >= 90.0 { lin = 180.0 - lin }
        return acos(EARTH_RADIUS / (apogee + EARTH_RADIUS)) + lin * DEG2RAD > abs(pos.latitude * DEG2RAD)
    }

    public func getPosition(_ pos: GeoPos, _ time: Int64) -> OrbitalPos {
        orbitalPos = OrbitalPos()
        julUTC = calcCurrentDaynum(time) + 2444238.5
        let tsince = (julUTC - julEpoch) * MIN_PER_DAY
        calcSDP4orSGP4(tsince)
        convertSatState()
        magnitudeVelocity()
        calcObs(julUTC, gsPos: pos)
        calcLatLonAlt(julUTC)
        orbitalPos.time = time
        orbitalPos.eclipsed = isEclipsed()
        orbitalPos.eclipseDepth = eclipseDepth
        return orbitalPos
    }

    /// Lightweight elevation-only check for pass finding.
    public func getElevation(_ pos: GeoPos, _ time: Int64) -> Double {
        julUTC = calcCurrentDaynum(time) + 2444238.5
        let tsince = (julUTC - julEpoch) * MIN_PER_DAY
        calcSDP4orSGP4(tsince)
        convertSatState()
        magnitudeVelocity()
        calcObs(julUTC, gsPos: pos)
        return orbitalPos.elevation
    }

    /// Full position calculation that also populates azimuth, altitude, etc.
    public func getFullPosition(_ pos: GeoPos, _ time: Int64) -> OrbitalPos {
        orbitalPos = OrbitalPos()
        julUTC = calcCurrentDaynum(time) + 2444238.5
        let tsince = (julUTC - julEpoch) * MIN_PER_DAY
        calcSDP4orSGP4(tsince)
        convertSatState()
        magnitudeVelocity()
        calcObs(julUTC, gsPos: pos)
        calcLatLonAlt(julUTC)
        orbitalPos.time = time
        return orbitalPos
    }

    private func calcCurrentDaynum(_ now: Int64) -> Double {
        let then: Int64 = 315446400000 // 31 Dec 1979 00:00:00 UTC (daynum 0)
        let millis: Double = Double(now - then)
        let seconds = millis / 1000.0
        let minutes = seconds / 60.0
        let hours = minutes / 60.0
        return hours / 24.0
    }

    public static func julianDateOfEpoch(_ epoch: Double) -> Double {
        // PREDICT v2.2.x uses modf(epoch * 1e-3, &year): in C the integer part
        // truncates toward zero (e.g. 26304.757 → year 26304). Using Swift's
        // floor() matches for all valid years (>1957) where the value is positive.
        var year = floor(epoch * 1e-3)
        let day = (epoch * 1e-3 - year) * 1000.0
        year = year < 57 ? year + 2000 : year + 1900
        return julianDateOfYear(year) + day
    }

    public static func julianDateOfYear(_ theYear: Double) -> Double {
        // Meeus, Astronomical Formulae (same reference PREDICT v2.2.x cites,
        // pp. 23–25): returns the Julian Date of day 0.0 of {year} (i.e. 00:00 UTC
        // on 1 January). For 2000 this yields the well-known J2000 reference
        // JD 2451544.5 (= 2000-01-01 00:00 UTC), so all downstream SGP4/SDP4
        // inputs are astronomically correct.
        let aYear = theYear - 1
        let a = Int64(floor(aYear / 100.0))
        let b: Int64 = 2 - a + a / 4
        var i = Int64(365.25 * aYear)
        i += 429  // int(30.6001 * 14) = 428.4014; Meeus formula: floor → 429
        return Double(i) + 1720994.5 + Double(b)
    }
    private func calcSDP4orSGP4(_ tsince: Double) {
        if data.isDeepSpace {
            (self as! DeepSpaceObject).calculateSDP4(tsince)
        } else {
            (self as! NearEarthObject).calculateSGP4(tsince)
        }
    }

    /// Converts the sat position and velocity vectors to km and km/sec.
    public func convertSatState() {
        scaleVector(EARTH_RADIUS, &position)
        scaleVector(EARTH_RADIUS * MIN_PER_DAY / SEC_PER_DAY, &velocity)
    }

    /// Calculates the topocentric coordinates of the object given ECI pos and vel.
    public func calcObs(_ julianUTC: Double, gsPos: GeoPos) {
        calcUserPosVel(julianUTC, gsPos: gsPos)
        rangeVector = [position[0] - obsPos[0], position[1] - obsPos[1],
                       position[2] - obsPos[2], 0.0]
        squintVector = [rangeVector[0], rangeVector[1], rangeVector[2], 0.0]
        rgvelVector = [velocity[0] - obsVel[0], velocity[1] - obsVel[1],
                       velocity[2] - obsVel[2], 0.0]
        magnitude(&rangeVector)
        let sinLat = cachedSinLat
        let cosLat = cachedCosLat
        let sinTheta = sin(gsPosTheta)
        let cosTheta = cos(gsPosTheta)
        let topS = sinLat * cosTheta * rangeVector[0]
                    + sinLat * sinTheta * rangeVector[1]
                    - cosLat * rangeVector[2]
        let topE = -sinTheta * rangeVector[0] + cosTheta * rangeVector[1]
        let topZ = cosLat * cosTheta * rangeVector[0]
                  + cosLat * sinTheta * rangeVector[1]
                  + sinLat * rangeVector[2]
        var azim = atan(-topE / topS)
        if topS > 0.0 { azim += PI }
        if azim < 0.0 { azim += TWO_PI }
        orbitalPos.azimuth = azim
        orbitalPos.elevation = asin(topZ / rangeVector[3])
        orbitalPos.distance = rangeVector[3]
        orbitalPos.distanceRate = dot(rangeVector, rgvelVector) / rangeVector[3]
        var elevation = orbitalPos.elevation / TWO_PI * 360.0
        if elevation > 90 { elevation = 180 - elevation }
        orbitalPos.aboveHorizon = elevation - 0.0 > EPSILON
    }

    /// Returns the ECI position and velocity of the observer.
    public func calcUserPosVel(_ time: Double, gsPos: GeoPos) {
        let mFactor = 7.292115e-5
        gsPosTheta = mod2PI(thetaGJD(jd: time) + DEG2RAD * gsPos.longitude)

        if gsPos.latitude != cachedGsLat || gsPos.longitude != cachedGsLon
            || gsPos.altitude != cachedGsAlt {
            cachedGsLat = gsPos.latitude
            cachedGsLon = gsPos.longitude
            cachedGsAlt = gsPos.altitude
            cachedSinLat = sin(DEG2RAD * gsPos.latitude)
            cachedCosLat = cos(DEG2RAD * gsPos.latitude)
            cachedObsC = invert(sqrt(1.0 + FLAT_FACT * (FLAT_FACT - 2) * sqr(cachedSinLat)))
            cachedObsSq = sqr(1.0 - FLAT_FACT) * cachedObsC
            cachedObsAchFactor = (EARTH_RADIUS * cachedObsC + gsPos.altitude / 1000.0) * cachedCosLat
            cachedObsZFactor = (EARTH_RADIUS * cachedObsSq + gsPos.altitude / 1000.0) * cachedSinLat
        }

        obsPos = [cachedObsAchFactor * cos(gsPosTheta),
                  cachedObsAchFactor * sin(gsPosTheta),
                  cachedObsZFactor, 0.0]
        obsVel = [-mFactor * obsPos[1], mFactor * obsPos[0], 0.0, 0.0]
        magnitude(&obsPos)
        magnitude(&obsVel)
    }

    /// Calculates the geodetic position of an object given its ECI position and time.
    public func calcLatLonAlt(_ time: Double) {
        orbitalPos.theta = atan2(position[1], position[0])
        orbitalPos.longitude = mod2PI(orbitalPos.theta - thetaGJD(jd: time))
        let r = sqrt(sqr(position[0]) + sqr(position[1]))
        let e2 = FLAT_FACT * (2.0 - FLAT_FACT)
        var lat = atan2(position[2], r)
        var phi: Double
        var c = 0.0
        var i = 0
        var converged = false
        while !converged && i < 10 {
            phi = lat
            c = invert(sqrt(1.0 - e2 * sqr(sin(phi))))
            lat = atan2(position[2] + EARTH_RADIUS * c * e2 * sin(phi), r)
            converged = abs(lat - phi) < EPSILON
            i += 1
        }
        orbitalPos.latitude = lat
        orbitalPos.altitude = r / cos(orbitalPos.latitude) - EARTH_RADIUS * c
        if orbitalPos.latitude > PI_2 {
            orbitalPos.latitude -= TWO_PI
        }
    }

    /// Called by the SGP4/SDP4 implementations to fill [position] and [velocity]
    /// from the short-periodic-corrected orbital elements.
    public func calculatePosAndVel(_ rk: Double, _ uk: Double, _ xnodek: Double,
                            _ xinck: Double, _ rdotk: Double, _ rfdotk: Double) {
        // Orientation vectors
        let sinuk = sin(uk)
        let cosuk = cos(uk)
        let sinik = sin(xinck)
        let cosik = cos(xinck)
        let sinnok = sin(xnodek)
        let cosnok = cos(xnodek)
        let xmx = -sinnok * cosik
        let xmy = cosnok * cosik
        let ux = xmx * sinuk + cosnok * cosuk
        let uy = xmy * sinuk + sinnok * cosuk
        let uz = sinik * sinuk
        let vx = xmx * cosuk - cosnok * sinuk
        let vy = xmy * cosuk - sinnok * sinuk
        let vz = sinik * cosuk
        // Position and velocity
        position = [ux, uy, uz, 0.0]
        scaleVector(rk, &position)
        velocity[0] = rdotk * ux + rfdotk * vx
        velocity[1] = rdotk * uy + rfdotk * vy
        velocity[2] = rdotk * uz + rfdotk * vz
    }

    // MARK: - Vector / math helpers

    public func sqr(_ arg: Double) -> Double { arg * arg }

    public func invert(_ value: Double) -> Double { 1.0 / value }

    public func converge(_ tmp: inout [Double], _ axn: Double, _ ayn: Double, _ capu: Double) {
        var converged = false
        var i = 0
        while !converged && i < 10 {
            tmp[7] = sin(tmp[2])
            tmp[8] = cos(tmp[2])
            tmp[3] = axn * tmp[7]
            tmp[4] = ayn * tmp[8]
            tmp[5] = axn * tmp[8]
            tmp[6] = ayn * tmp[7]
            let epw = (capu - tmp[4] + tmp[3] - tmp[2]) / (1.0 - tmp[5] - tmp[6]) + tmp[2]
            if abs(epw - tmp[2]) <= EPSILON {
                converged = true
            } else {
                tmp[2] = epw
            }
            i += 1
        }
    }

    public func calculatePhase(_ xlt: Double, _ xnode: Double, _ omgadf: Double) {
        var phaseValue = xlt - xnode - omgadf + TWO_PI
        if phaseValue < 0.0 { phaseValue += TWO_PI }
        orbitalPos.phase = mod2PI(phaseValue)
    }

    public func setPerigee(_ perigee: Double) {
        self.perigee = perigee
        checkPerigee()
    }

    private func checkPerigee() {
        s4 = 1.012229
        qoms24 = 1.880279e-9
        if perigee < 156.0 {
            s4 = perigee <= 98.0 ? 20.0 : perigee - 78.0
            qoms24 = pow((120 - s4) / EARTH_RADIUS, 4.0)
            s4 = s4 / EARTH_RADIUS + 1.0
        }
    }

    /// Checks if the satellite is in sunlight.
    public func isEclipsed() -> Bool {
        let sunVector = calcSunVector()
        let sdEarth = asin(EARTH_RADIUS / position[3])
        let rho = subtract(sunVector, position)
        let sdSun = asin(SOLAR_RADIUS / rho[3])
        let earth = scalarNegMultiply(position)
        let delta = angle(sunVector, earth)
        eclipseDepth = sdEarth - sdSun - delta
        return sdEarth < sdSun ? false : eclipseDepth >= 0
    }

    public func calcSunVector() -> [Double] {
        let mjd = julUTC - 2415020.0
        let year = 1900 + mjd / 365.25
        let solTime = (mjd + deltaEt(year)) / SEC_PER_DAY / 36525.0
        let mTemp = modulus(35999.04975 * solTime, 360.0)
        let m = radians(modulus(358.47583 + mTemp - (0.000150 + 0.0000033 * solTime) * sqr(solTime), 360.0))
        let lTemp = modulus(36000.76892 * solTime, 360.0)
        let l = radians(modulus(279.69668 + lTemp + 0.0003025 * sqr(solTime), 360.0))
        let e = 0.01675104 - (0.0000418 + 0.000000126 * solTime) * solTime
        let c = radians((1.919460 - (0.004789 + 0.000014 * solTime) * solTime) * sin(m)
            + (0.020094 - 0.000100 * solTime) * sin(2 * m) + 0.000293 * sin(3 * m))
        let o = radians(modulus(259.18 - 1934.142 * solTime, 360.0))
        let lsa = modulus(l + c - radians(0.00569 - 0.00479 * sin(o)), TWO_PI)
        let nu = modulus(m + c, TWO_PI)
        var r = 1.0000002 * (1.0 - sqr(e)) / (1.0 + e * cos(nu))
        let eps = radians(23.452294
            - (0.0130125 + (0.00000164 - 0.000000503 * solTime) * solTime) * solTime
            + 0.00256 * cos(o))
        r *= ASTRONOMICAL_UNIT
        return [r, r * cos(lsa), r * sin(lsa) * cos(eps), r * sin(lsa) * sin(eps)]
    }

    public func subtract(_ v1: [Double], _ v2: [Double]) -> [Double] {
        var v3 = [v1[0] - v2[0], v1[1] - v2[1], v1[2] - v2[2], 0.0]
        magnitude(&v3)
        return v3
    }

    public func scalarNegMultiply(_ vector: [Double]) -> [Double] {
        let neg = -1.0
        return [abs(vector[3] * neg), vector[0] * neg, vector[1] * neg, vector[2] * neg]
    }

    public func angle(_ v1: [Double], _ v2: [Double]) -> Double {
        var a = v1
        var b = v2
        magnitude(&a)
        magnitude(&b)
        return acos(dot(a, b) / (a[3] * b[3]))
    }

    public func dot(_ v1: [Double], _ v2: [Double]) -> Double {
        v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2]
    }

    public func magnitude(_ v: inout [Double]) {
        v[3] = sqrt(sqr(v[0]) + sqr(v[1]) + sqr(v[2]))
    }

    public func magnitudeVelocity() {
        position[3] = sqrt(sqr(position[0]) + sqr(position[1]) + sqr(position[2]))
        velocity[3] = sqrt(sqr(velocity[0]) + sqr(velocity[1]) + sqr(velocity[2]))
    }

    public func scaleVector(_ k: Double, _ v: inout [Double]) {
        for i in 0..<3 { v[i] *= k }
        magnitude(&v)
    }

    public func deltaEt(_ year: Double) -> Double {
        deltaET(year: year)
    }

    public func radians(_ degrees: Double) -> Double {
        degrees * DEG2RAD
    }

    // Delegates to the package-level modulus (OrbitalMath); the SGP4/SDP4
    // propagators pass an explicit 360.0 or TWO_PI so the default is immaterial.
    public func modulus(_ arg1: Double, _ arg2: Double = 360.0) -> Double {
        var r = arg1
        let i = floor(r / arg2)
        r -= i * arg2
        if r < 0.0 { r += arg2 }
        return r
    }
}
