//  Look4Sat iOS port — standalone celestial computations
//  Ported from Kotlin: core/domain/.../predict/CelestialComputer.kt
//  License: GPL-3.0
//
//  Sun position, Moon position, satellite visibility classification,
//  orbital metadata, RA/Dec conversion, and rise/set finding for
//  Sun and Moon.
//
//  All angles in degrees unless noted. Time is Unix epoch milliseconds.
//  Shared math utilities (thetaGJ1, modulo, mod2PI, deltaET,
//  millisToDaynum, solarPositionECI, eciToGeodetic) live in
//  OrbitalMath.swift in the same package.
import Foundation

public enum  CelestialComputer {

    // MARK: - Result types

    /// Sun position as seen from a ground observer.
    public struct SunPosition {
        public let azimuth: Double        // degrees, 0=N, 90=E
        public let elevation: Double      // degrees, >0 above horizon
        public let distance: Double       // normalized: 1.0 + ((range - AU) / AU)
        public let rangeRate: Double      // km/s
        public let latitude: Double       // sub-solar point latitude, degrees
        public let longitude: Double      // sub-solar point longitude, degrees
        public let rightAscension: Double // degrees
        public let declination: Double    // degrees
    }

    /// Moon position as seen from a ground observer.
    public struct MoonPosition {
        public let azimuth: Double        // degrees, 0=N, 90=E
        public let elevation: Double      // degrees, topocentric (parallax corrected)
        public let rightAscension: Double // degrees
        public let declination: Double    // degrees
        public let gha: Double            // Greenwich Hour Angle, degrees
        public let angularDiameter: Double // apparent diameter relative to Earth's diameter
        public let radialVelocity: Double // m/s, Doppler radial velocity for EME
    }

    /// 3-state satellite visibility classification.
    public enum SatVisibility: Int {
        case visible   = 0  // satellite is sunlit, observer in darkness (sun below -12°)
        case daylight  = 1  // satellite is sunlit, observer in daylight
        case eclipsed  = 2  // satellite is in Earth's shadow
    }

    /// Orbital metadata not typically included in pass data.
    public struct OrbitalMetadata {
        public let footprintDiameter: Double // km, ground coverage circle diameter
        public let orbitNumber: Int64        // current orbit/revolution number
        public let betaAngle: Double         // degrees, angle between orbital plane and Sun
        public let orbitalPhase: Double       // 0-256 phase within current orbit
    }

    /// Rise and set times for a celestial body.
    public struct RiseSetTimes {
        public let riseTimeMillis: Int64  // 0 if not found
        public let setTimeMillis: Int64   // 0 if not found
    }

    // MARK: - Sun position

    /// Compute the Sun's full position as seen from [observer] at [timeMillis].
    /// Includes az/el, RA/Dec, sub-solar lat/lon, range, and range rate.
    /// Based on FindSun() from PREDICT v2.2.5.
    public static func getSunPosition(_ observer: GeoPos, _ timeMillis: Int64) -> SunPosition {
        let daynum = millisToDaynum(timeMillis)
        let julUtc = daynum + 2444238.5
        let sunVec = solarPositionECI(julUtc: julUtc)
        let zeroVel = [0.0, 0.0, 0.0]
        let obsGeo = observerGeodetic(observer)

        // Az, El, Range, RangeRate
        let obsSet = computeObsAngles(julUtc: julUtc,
                                       targetPos: sunVec,
                                       targetVel: zeroVel,
                                       obsGeo: obsGeo)

        // Lat/Lon of sub-solar point
        let latLon = eciToGeodetic(julUtc: julUtc, eciPos: sunVec)

        // RA/Dec
        let raDec = calculateRADec(julUtc: julUtc,
                                   targetPos: sunVec,
                                   targetVel: zeroVel,
                                   obsGeo: obsGeo)

        return SunPosition(
            azimuth: obsSet[0] * RAD2DEG,
            elevation: obsSet[1] * RAD2DEG,
            distance: 1.0 + ((obsSet[2] - ASTRONOMICAL_UNIT) / ASTRONOMICAL_UNIT),
            rangeRate: 1000.0 * obsSet[3],
            latitude: latLon[0] * RAD2DEG,
            longitude: (latLon[1] * RAD2DEG > 180.0 ? latLon[1] * RAD2DEG - 360.0 : latLon[1] * RAD2DEG),
            rightAscension: raDec[0] * RAD2DEG,
            declination: raDec[1] * RAD2DEG
        )
    }

    // MARK: - Moon position

    /// Compute the Moon's position as seen from [observer] at [timeMillis].
    /// Full Meeus lunar ephemeris from PREDICT v2.2.5 with expanded terms
    /// and radial velocity approximation for EME Doppler.
    public static func getMoonPosition(_ observer: GeoPos, _ timeMillis: Int64) -> MoonPosition {
        let daynum = millisToDaynum(timeMillis)
    let jd = daynum + 2444238.5
        var t = (jd - 2415020.0) / 36525.0
        let t2 = t * t
        let t3 = t2 * t

        var l1 = 270.434164 + 481267.8831 * t - 0.001133 * t2 + 0.0000019 * t3
        var mSun = 358.475833 + 35999.0498 * t - 0.00015 * t2 - 0.0000033 * t3
        var m1 = 296.104608 + 477198.8491 * t + 0.009192 * t2 + 0.0000144 * t3
        var d = 350.737486 + 445267.1142 * t - 0.001436 * t2 + 0.0000019 * t3
        var ff = 11.250889 + 483202.0251 * t - 0.003211 * t2 - 0.0000003 * t3
        let om = (259.183275 - 1934.142 * t + 0.002078 * t2 + 0.0000022 * t3) * DEG2RAD

        let correction512 = sin((51.2 + 20.2 * t) * DEG2RAD)
        let ss = 0.003964 * sin((346.56 + 132.87 * t - 0.0091731 * t2) * DEG2RAD)
        l1 += 0.000233 * correction512 + ss + 0.001964 * sin(om)
        mSun -= 0.001778 * correction512
        m1 += 0.000817 * correction512 + ss + 0.002541 * sin(om)
        d += 0.002011 * correction512 + ss + 0.001964 * sin(om)
        ff += ss - 0.024691 * sin(om) - 0.004328 * sin(om + (275.05 - 2.3 * t) * DEG2RAD)
    let e = 1.0 - 0.002495 * t - 0.00000752 * t2
        l1 = primeAngle(l1); mSun = primeAngle(mSun); m1 = primeAngle(m1)
        d = primeAngle(d); ff = primeAngle(ff)

        let mSR = mSun * DEG2RAD
        let m1R = m1 * DEG2RAD
        let dR = d * DEG2RAD
        let ffR = ff * DEG2RAD

        // Elliptic longitude — expand v225 terms
        var l = l1 + 6.28875 * sin(m1R) + 1.274018 * sin(2 * dR - m1R) + 0.658309 * sin(2 * dR)
        l += 0.213616 * sin(2 * m1R) - e * 0.185596 * sin(mSR) - 0.114336 * sin(2 * ffR)
        l += 0.058793 * sin(2 * dR - 2 * m1R) + e * 0.057212 * sin(2 * dR - mSR - m1R) + 0.05332 * sin(2 * dR + m1R)
        l += e * 0.045874 * sin(2 * dR - mSR) + e * 0.041024 * sin(m1R - mSR) - 0.034718 * sin(dR)
        l -= e * 0.030465 * sin(mSR + m1R) + 0.015326 * sin(2 * dR - 2 * ffR) - 0.012528 * sin(2 * ffR + m1R)
        l -= 0.01098 * sin(2 * ffR - m1R) + 0.010674 * sin(4 * dR - m1R) + 0.010034 * sin(3 * m1R)
        l += 0.008548 * sin(4 * dR - 2 * m1R) - e * 0.00791 * sin(mSR - m1R + 2 * dR)
        l -= e * 0.006783 * sin(2 * dR + mSR)
        l += 0.005162 * sin(m1R - dR) + e * 0.005 * sin(mSR + dR) + e * 0.004049 * sin(m1R - mSR + 2 * dR)
        l += 0.003996 * sin(2 * m1R + 2 * dR) + 0.003862 * sin(4 * dR) + 0.003665 * sin(2 * dR - 3 * m1R)
        l += e * 0.002695 * sin(2 * m1R - mSR) + 0.002602 * sin(m1R - 2 * ffR - 2 * dR)
        l += e * 0.002396 * sin(2 * dR - mSR - 2 * m1R)
        l -= 0.002349 * sin(m1R + dR) + e * e * 0.002249 * sin(2 * dR - 2 * mSR)
        l -= e * 0.002125 * sin(2 * m1R + mSR)
        l -= e * e * 0.002079 * sin(2 * mSR) + e * e * 0.002059 * sin(2 * dR - m1R - 2 * mSR)
        l -= 0.001773 * sin(m1R + 2 * dR - 2 * ffR)
        l += e * 0.00122 * sin(4 * dR - mSR - m1R) - 0.00111 * sin(2 * m1R + 2 * ffR) + 0.000892 * sin(m1R - 3 * dR)
        l -= e * 0.000811 * sin(mSR + m1R + 2 * dR) + e * 0.000761 * sin(4 * dR - mSR - 2 * m1R)
        l += e * e * 0.000717 * sin(m1R - 2 * mSR)
        l += e * e * 0.000704 * sin(m1R - 2 * mSR - 2 * dR) + e * 0.000693 * sin(mSR - 2 * m1R + 2 * dR)
        l += e * 0.000598 * sin(2 * dR - mSR - 2 * ffR) + 0.00055 * sin(m1R + 4 * dR)
        l += 0.000538 * sin(4 * m1R) + e * 0.000521 * sin(4 * dR - mSR) + 0.000486 * sin(2 * m1R - dR)
        l -= 0.001595 * sin(2 * ffR + 2 * dR)

        // Elliptic latitude — expand v225 terms
        var b =
            5.128189 * sin(ffR) + 0.280606 * sin(m1R + ffR) + 0.277693 * sin(m1R - ffR) + 0.173238 * sin(2 * dR - ffR)
        b += 0.055413 * sin(2 * dR + ffR - m1R) + 0.046272 * sin(2 * dR - ffR - m1R) + 0.032573 * sin(2 * dR + ffR)
        b += 0.017198 * sin(2 * m1R + ffR) + 9.266999e-03 * sin(2 * dR + m1R - ffR) + 0.008823 * sin(2 * m1R - ffR)
        b += e * 0.008247 * sin(2 * dR - mSR - ffR) + 0.004323 * sin(2 * dR - ffR - 2 * m1R)
        b += 0.0042 * sin(2 * dR + ffR + m1R)
        b += e * 0.003372 * sin(ffR - mSR - 2 * dR) + e * 0.002472 * sin(2 * dR + ffR - mSR - m1R)
        b += e * 0.002222 * sin(2 * dR + ffR - mSR)
        b += 0.002072 * sin(2 * dR - ffR - mSR - m1R) + e * 0.001877 * sin(ffR - mSR + m1R)
        b += 0.001828 * sin(4 * dR - ffR - m1R)
        b -= e * 0.001803 * sin(ffR + mSR) - 0.00175 * sin(3 * ffR)
        b += e * 0.00157 * sin(m1R - mSR - ffR) - 0.001487 * sin(ffR + dR)
        b -= e * 0.001481 * sin(ffR + mSR + m1R) + e * 0.001417 * sin(ffR - mSR - m1R)
        b += e * 0.00135 * sin(ffR - mSR) + 0.00133 * sin(ffR - dR)
        b += 0.001106 * sin(ffR + 3 * m1R) + 0.00102 * sin(4 * dR - ffR) + 0.000833 * sin(ffR + 4 * dR - m1R)
        b += 0.000781 * sin(m1R - 3 * ffR) + 0.00067 * sin(ffR + 4 * dR - 2 * m1R)
        b += 0.000606 * sin(2 * dR - 3 * ffR)
        b += 0.000597 * sin(2 * dR + 2 * m1R - ffR) + e * 0.000492 * sin(2 * dR + m1R - mSR - ffR)
        b += 0.00045 * sin(2 * m1R - ffR - 2 * dR)
        b += 0.000439 * sin(3 * m1R - ffR) + 0.000423 * sin(ffR + 2 * dR + 2 * m1R)
        b += 0.000422 * sin(2 * dR - ffR - 3 * m1R)
        b -= e * 0.000367 * sin(mSR + ffR + 2 * dR - m1R) - e * 0.000353 * sin(mSR + ffR + 2 * dR)
        b += 0.000331 * sin(ffR + 4 * dR)
        b += e * 0.000317 * sin(2 * dR + ffR - mSR + m1R) + e * e * 0.000306 * sin(2 * dR - 2 * mSR - ffR)
        b -= 0.000283 * sin(m1R + 3 * ffR)

        let w1 = 0.0004664 * cos(om)
        let w2 = 0.0000754 * cos(om + (275.05 - 2.3 * t) * DEG2RAD)
        let bt = b * (1.0 - w1 - w2)

        // Parallax — expand v225 terms
        var p =
            0.950724 + 0.051818 * cos(m1R) + 0.009531 * cos(2 * dR - m1R) + 0.007843 * cos(2 * dR) + 0.002824 * cos(2 * m1R)
        p += 0.000857 * cos(2 * dR + m1R) + e * 0.000533 * cos(2 * dR - mSR) + e * 0.000401 * cos(2 * dR - mSR - m1R)
        p += 0.000173 * cos(3 * m1R) + 0.000167 * cos(4 * dR - m1R) - e * 0.000111 * cos(mSR)
        p += 0.000103 * cos(4 * dR - 2 * m1R) - 0.000084 * cos(2 * m1R - 2 * dR) - e * 0.000083 * cos(2 * dR + mSR)
        p += 0.000079 * cos(2 * dR + 2 * m1R)
        p += 0.000072 * cos(4 * dR) + e * 0.000064 * cos(2 * dR - mSR + m1R) - e * 0.000063 * cos(2 * dR + mSR - m1R)
        p += e * 0.000041 * cos(mSR + dR) + e * 0.000035 * cos(2 * m1R - mSR) - 0.000033 * cos(3 * m1R - 2 * dR)
        p -= 0.00003 * cos(m1R + dR) - 0.000029 * cos(2 * ffR - 2 * dR) - e * 0.000029 * cos(2 * m1R + mSR)
        p += e * e * 0.000026 * cos(2 * dR - 2 * mSR) - 0.000023 * cos(2 * ffR - 2 * dR + m1R)
        p += e * 0.000019 * cos(4 * dR - mSR - m1R)

        let bRad = bt * DEG2RAD
        let lm = l * DEG2RAD
        let moonDx = 3.0 / (PI * p)

        // Ecliptic → equatorial. atan2 keeps RA in the right quadrant for any
        // elliptic longitude: the periodic terms above can push l slightly
        // outside [0, 360), and an acos based conversion then mirrors RA around
        // 0h in azimuth.
        let z = (jd - 2415020.5) / 365.2422
        let ob = (23.452294 - (0.46845 * z + 5.9e-07 * z * z) / 3600.0).toRadians()
        let dec = asin(sin(bRad) * cos(ob) + cos(bRad) * sin(ob) * sin(lm))
        let ra = mod2PI(atan2(sin(lm) * cos(ob) - tan(bRad) * sin(ob), cos(lm)))

        let n = observer.latitude * DEG2RAD
        t = (jd - 2451545.0) / 36525.0
        let teg = modulo(
            280.46061837 + 360.98564736629 * (jd - 2451545.0) + (0.000387933 * t - t * t / 38710000.0) * t,
            360.0)
        // LST = GMST + east longitude (positive east convention)
        let th = mod2PI((teg + observer.longitude) * DEG2RAD)
        let h = th - ra
        let azVal = atan2(sin(h), cos(h) * sin(n) - tan(dec) * cos(n)) + PI
        let el = asin(sin(n) * sin(dec) + cos(n) * cos(dec) * cos(h))
        // Geocentric → topocentric. Parallax is up to ~1°, two full Moon
        // diameters, and shifts the Moon along the vertical circle only, so
        // just the elevation needs correcting.
        let elTopo = el / DEG2RAD - p * cos(el)

        // Moon radial velocity approximation (from "Amateur Radio Software",
        // G4ANB, RSG 1985)
        let mm = fixAngle(1.319238 + daynum * 0.228027135)
        let radT2 = 0.10976
        let radT1 = mm + radT2 * sin(mm)
        var dv = 0.01255 * moonDx * moonDx * sin(radT1) * (1.0 + radT2 * cos(mm))
        dv *= 4449.0
        let earthR = 6378.0
        let moonDist = 384401.0
        let radT3 = earthR * moonDist * (cos(dec) * cos(n) * sin(h)) /
                    sqrt(moonDist * moonDist - moonDist * earthR * sin(el))
        let moonDv = dv + radT3 * 0.0753125

        let moonRA = ra / DEG2RAD
        var moonGha = teg - moonRA
        if moonGha < 0.0 { moonGha += 360.0 }

        return MoonPosition(
            azimuth: azVal / DEG2RAD,
            elevation: elTopo,
            rightAscension: moonRA,
            declination: dec / DEG2RAD,
            gha: moonGha,
            angularDiameter: moonDx,
            radialVelocity: moonDv
        )
    }

    // MARK: - Satellite visibility

    /// Classify satellite visibility given its eclipse state and the Sun's
    /// elevation at the observer's location.
    public static func classifyVisibility(
        isEclipsed: Bool,
        sunElevationDeg: Double,
        satElevationDeg: Double
    ) -> SatVisibility {
        if isEclipsed { return SatVisibility.eclipsed }
        return if sunElevationDeg <= -12.0 && satElevationDeg >= 0.0 {
            SatVisibility.visible
        } else {
            SatVisibility.daylight
        }
    }

    // MARK: - Orbital metadata

    /// Compute orbital metadata for a satellite at its current position.
    public static func computeOrbitalMetadata(
        altitudeKm: Double,
        meanMotion: Double,
        bstar: Double,
        meanAnomaly: Double,
        revNumAtEpoch: Int,
        ageDays: Double,
        phase: Double,
        satPosECI: [Double],
        satVelECI: [Double],
        sunPosECI: [Double]
    ) -> OrbitalMetadata {
        // Footprint diameter (km)
        let footprint = 12756.33 * acos(EARTH_RADIUS / (EARTH_RADIUS + altitudeKm))

        // Orbit number
        let xmnvda = 1.44e3
        let orbitNum = Int64(
            (meanMotion * xmnvda / TWO_PI + ageDays * bstar) * Double(ageDays) + meanAnomaly / TWO_PI
        ) + Int64(revNumAtEpoch)

        // Beta angle: angle between orbital plane and Sun direction
        // Orbital plane normal = cross(pos, vel)
        let nx = satPosECI[1] * satVelECI[2] - satPosECI[2] * satVelECI[1]
        let ny = satPosECI[2] * satVelECI[0] - satPosECI[0] * satVelECI[2]
        let nz = satPosECI[0] * satVelECI[1] - satPosECI[1] * satVelECI[0]
        let nMag = sqrt(nx * nx + ny * ny + nz * nz)
        let sMag = sqrt(sunPosECI[0] * sunPosECI[0] + sunPosECI[1] * sunPosECI[1] + sunPosECI[2] * sunPosECI[2])
        let dotNS = nx * sunPosECI[0] + ny * sunPosECI[1] + nz * sunPosECI[2]
        let betaAngle = if nMag > 0 && sMag > 0 {
            (PI / 2.0 - acos(min(1.0, max(-1.0, dotNS / (nMag * sMag))))) * RAD2DEG
        } else {
            0.0
        }

        // Phase (0-256 scale, matching PREDICT convention)
        let orbitalPhase = 256.0 * (phase / TWO_PI)

        return OrbitalMetadata(footprintDiameter: footprint,
                               orbitNumber: orbitNum,
                               betaAngle: betaAngle,
                               orbitalPhase: orbitalPhase)
    }

    // MARK: - Satellite status checks

    /// Check if a satellite is geostationary (mean motion ≈ 1.0027 rev/day).
    public static func isGeostationary(_ meanMotion: Double) -> Bool {
        abs(meanMotion - 1.0027) < 0.0002
    }

    /// Check if a satellite has likely decayed based on drag and time since epoch.
    public static func hasDecayed(meanMotion: Double, drag: Double, epochDaynum: Double, currentDaynum: Double) -> Bool {
        return epochDaynum + ((16.666666 - meanMotion) / (10.0 * abs(drag))) < currentDaynum
    }

    // MARK: - Rise/Set finding

    /// Find the next sunrise and sunset times from [startMillis] for [observer].
    /// Uses elevation threshold of -0.8333° to match the standard civil
    /// definition: upper limb on geometric horizon with standard atmospheric
    /// refraction (~0.57°) and solar semidiameter (~0.27°) corrections
    /// applied, matching USNO/timeanddate.com.
    public static func findSunRiseSet(_ observer: GeoPos, _ startMillis: Int64) -> RiseSetTimes {
        // Standard civil threshold: center elevation when upper limb meets
        // geometric horizon. -0.8333° = standard refraction (~0.5667°) +
        // solar semidiameter (~0.2667°).
        let threshold = 0.8333
        var daynum = millisToDaynum(startMillis)
        var sunPos = getSunPosition(observer, daynumToMillis(daynum))

        // Phase 1: if sun is above threshold, fast-forward well past sunset into night
        var guardCount = 0
        if sunPos.elevation > -threshold {
            while sunPos.elevation > -threshold && guardCount < 500 {
                daynum += 0.008   // fixed ~11.5 min steps past the setting sun
                sunPos = getSunPosition(observer, daynumToMillis(daynum))
                guardCount += 1
            }
            // Now advance until sun is clearly below minimum (deep night)
            guardCount = 0
            while sunPos.elevation > -12.0 && guardCount < 500 {
                daynum += 0.02
                sunPos = getSunPosition(observer, daynumToMillis(daynum))
                guardCount += 1
            }
        }

        // Phase 2: advance until sun starts rising toward threshold (elevation increasing)
        guardCount = 0
        while sunPos.elevation < -threshold && guardCount < 500 {
            daynum += 0.008
            sunPos = getSunPosition(observer, daynumToMillis(daynum))
            guardCount += 1
        }

        // Phase 3: converge symmetrically on elevation = -threshold (sunrise)
        var sunrise = 0.0
        guardCount = 0
        while sunrise == 0.0 && guardCount < 200 {
            let delta = sunPos.elevation + threshold
            if abs(delta) < 0.01 {
                sunrise = daynum
            } else {
                daynum -= 0.004 * delta
                sunPos = getSunPosition(observer, daynumToMillis(daynum))
            }
            guardCount += 1
        }
        if sunrise == 0.0 { sunrise = daynum }

        // Phase 4: fast-forward through the day until sun drops back below threshold.
        // Start from just after sunrise (small offset) so the sun is clearly above
        // the threshold. This prevents a bug where Phase 3 converges to a point
        // slightly below -threshold, causing Phase 4 to skip and Phase 5 to
        // converge to the same time as sunrise, producing identical sunrise/sunset times.
        daynum = sunrise + 0.001
        sunPos = getSunPosition(observer, daynumToMillis(daynum))
        guardCount = 0
        while sunPos.elevation > -threshold && guardCount < 500 {
            daynum += 0.008
            sunPos = getSunPosition(observer, daynumToMillis(daynum))
            guardCount += 1
        }

        // Phase 5: converge symmetrically on elevation = -threshold (sunset)
        var sunset = 0.0
        guardCount = 0
        while sunset == 0.0 && guardCount < 200 {
            let delta = sunPos.elevation + threshold
            if abs(delta) < 0.01 {
                sunset = daynum
            } else {
                daynum += 0.004 * delta
                sunPos = getSunPosition(observer, daynumToMillis(daynum))
            }
            guardCount += 1
        }
        if sunset == 0.0 { sunset = daynum }

        return RiseSetTimes(riseTimeMillis: daynumToMillis(sunrise),
                            setTimeMillis: daynumToMillis(sunset))
    }

    /// Find the next moonrise and moonset times from [startMillis] for [observer].
    /// Uses the adaptive iteration from PREDICT v2.2.5's PredictMoon().
    public static func findMoonRiseSet(_ observer: GeoPos, _ startMillis: Int64) -> RiseSetTimes {
        var daynum = millisToDaynum(startMillis)
        var moonPos = getMoonPosition(observer, daynumToMillis(daynum))

        // If moon is already up, move forward until it sets
        var guardCount = 0
        if moonPos.elevation > 0 {
            while moonPos.elevation > 0 && guardCount < 1000 {
                daynum += 0.004 * sin(DEG2RAD * (moonPos.elevation + 0.5))
                moonPos = getMoonPosition(observer, daynumToMillis(daynum))
                guardCount += 1
            }
            daynum += 0.4
            moonPos = getMoonPosition(observer, daynumToMillis(daynum))
        }
        // Find moonrise
        var moonrise = 0.0
        guardCount = 0
        while moonrise == 0.0 && guardCount < 1000 {
            if abs(moonPos.elevation) < 0.03 {
                moonrise = daynum
            } else {
                daynum -= 0.004 * moonPos.elevation
                moonPos = getMoonPosition(observer, daynumToMillis(daynum))
            }
            guardCount += 1
        }
        if moonrise == 0.0 { moonrise = daynum }

        // Find moonset from moonrise
        daynum = moonrise
        moonPos = getMoonPosition(observer, daynumToMillis(daynum))
        guardCount = 0
        while moonPos.elevation > -1 && guardCount < 1000 {
            daynum += 0.04 * cos(DEG2RAD * (moonPos.elevation + 0.5))
            moonPos = getMoonPosition(observer, daynumToMillis(daynum))
            guardCount += 1
        }
        var moonset = 0.0
        guardCount = 0
        while moonset == 0.0 && guardCount < 1000 {
            if abs(moonPos.elevation) < 0.03 {
                moonset = daynum
            } else {
                daynum += 0.004 * moonPos.elevation
                moonPos = getMoonPosition(observer, daynumToMillis(daynum))
            }
            guardCount += 1
        }
        if moonset == 0.0 { moonset = daynum }

        return RiseSetTimes(riseTimeMillis: daynumToMillis(moonrise),
                            setTimeMillis: daynumToMillis(moonset))
    }

    // MARK: - Visual magnitude estimation

    /// Estimate the apparent visual magnitude of a satellite.
    ///
    /// Uses the standard formula from McCants/Heaven-Abode:
    ///   apparentMag = stdMag + 5 * log10(range / 1000) - 15 * log10(cos(phaseAngle / 2))
    public static func estimateVisualMagnitude(rangeKm: Double, phaseAngleDeg: Double, stdMag: Double = 4.0) -> Double {
        if rangeKm <= 0 { return stdMag }
        let halfPhaseRad = phaseAngleDeg.toRadians() / 2.0
        let cosHalfPhase = cos(halfPhaseRad)
        let phaseTerm = if cosHalfPhase > 1e-6 { -15.0 * log10(cosHalfPhase) } else { 99.0 }
        return stdMag + 5.0 * log10(rangeKm / 1000.0) + phaseTerm
    }

    /// Compute the phase angle (Sun-satellite-observer) in degrees.
    public static func computePhaseAngle(satPosECI: [Double], sunPosECI: [Double], obsPosECI: [Double]) -> Double {
        let toSunX = sunPosECI[0] - satPosECI[0]
        let toSunY = sunPosECI[1] - satPosECI[1]
        let toSunZ = sunPosECI[2] - satPosECI[2]
        let toObsX = obsPosECI[0] - satPosECI[0]
        let toObsY = obsPosECI[1] - satPosECI[1]
        let toObsZ = obsPosECI[2] - satPosECI[2]
        let dot = toSunX * toObsX + toSunY * toObsY + toSunZ * toObsZ
        let magSun = sqrt(toSunX * toSunX + toSunY * toSunY + toSunZ * toSunZ)
        let magObs = sqrt(toObsX * toObsX + toObsY * toObsY + toObsZ * toObsZ)
        if magSun == 0.0 || magObs == 0.0 { return 90.0 }
        let cosAngle = (dot / (magSun * magObs)).clamped(to: -1.0...1.0)
        return acos(cosAngle) * RAD2DEG
    }

    // MARK: - Doppler

    /// Compute Doppler shift for a given base frequency and range rate.
    ///
    /// [rangeRateKmS] is in km/s; negative = approaching (range decreasing).
    public static func dopplerShift(_ frequencyHz: Double, _ rangeRateKmS: Double) -> Double {
        return frequencyHz * (299792.458 - rangeRateKmS) / 299792.458
    }

    // MARK: - Internal helpers

    private static func observerGeodetic(_ pos: GeoPos) -> [Double] {
        // [lat_rad, lon_rad, alt_km] — longitude positive east, matching
        // OrbitalObject convention. LST = thetaGJ1(julUtc) + lon_rad = GMST + lon_rad (correct).
        return [pos.latitude * DEG2RAD, pos.longitude * DEG2RAD, pos.altitude / 1000.0]
    }

    /// Convert az/el observation to Right Ascension / Declination.
    /// Returns [ra_rad, dec_rad].
    /// Based on Calculate_RADec() from PREDICT v2.2.5 (Escobar method).
    private static func calculateRADec(
        julUtc: Double,
        targetPos: [Double],
        targetVel: [Double],
        obsGeo: [Double]
    ) -> [Double] {
        let obsSet = computeObsAngles(julUtc: julUtc, targetPos: targetPos, targetVel: targetVel, obsGeo: obsGeo)
        let az = obsSet[0]
        let el = obsSet[1]
        let phi = obsGeo[0]
        let theta = mod2PI(thetaGJD(jd: julUtc) + obsGeo[1])
        let sinTheta = sin(theta)
        let cosTheta = cos(theta)
        let sinPhi = sin(phi)
        let cosPhi = cos(phi)
        let lxh = -cos(az) * cos(el)
        let lyh = sin(az) * cos(el)
        let lzh = sin(el)
        let sx = sinPhi * cosTheta
        let ex2 = -sinTheta
        let zx = cosTheta * cosPhi
        let sy = sinPhi * sinTheta
        let zy = sinTheta * cosPhi
        let sz = -cosPhi
        let lx = sx * lxh + ex2 * lyh + zx * lzh
        let ly = sy * lxh + cosTheta * lyh + zy * lzh
        let lz = sz * lxh + 0.0 * lyh + sinPhi * lzh
        let dec = asin(lz)
        let cosDelta = sqrt(1.0 - lz * lz)
        let sinAlpha = ly / cosDelta
        let cosAlpha = lx / cosDelta
        let ra = mod2PI(atan2(sinAlpha, cosAlpha))
        return [ra, dec]
    }

    /// Compute observer look-angles (az, el, range, rangeRate) to a target at ECI position.
    /// Returns [azimuth_rad, elevation_rad, range_km, rangeRate_km/s].
    /// Azimuth is north-referenced (0=N, 90=E), matching OrbitalObject's convention.
    private static func computeObsAngles(
        julUtc: Double,
        targetPos: [Double],
        targetVel: [Double],
        obsGeo: [Double] // [lat_rad, lon_rad, alt_km]
    ) -> [Double] {
        let theta = mod2PI(thetaGJD(jd: julUtc) + obsGeo[1])
        let c = 1.0 / sqrt(1.0 + FLAT_FACT * (FLAT_FACT - 2.0) * pow(sin(obsGeo[0]), 2.0))
        let sq = pow((1.0 - FLAT_FACT), 2.0) * c
        let achcp = (EARTH_RADIUS * c + obsGeo[2]) * cos(obsGeo[0])
        let ox = achcp * cos(theta)
        let oy = achcp * sin(theta)
        let oz = (EARTH_RADIUS * sq + obsGeo[2]) * sin(obsGeo[0])
        let ovg = -MFACTOR * oy
        let ovy = MFACTOR * ox

        let rx = targetPos[0] - ox
        let ry = targetPos[1] - oy
        let rz = targetPos[2] - oz
        let rMag = sqrt(rx * rx + ry * ry + rz * rz)
        let rvx = targetVel[0] - ovg
        let rvy = targetVel[1] - ovy
        let rvz = targetVel[2]

        let sinLat = sin(obsGeo[0])
        let cosLat = cos(obsGeo[0])
        let sinTheta = sin(theta)
        let cosTheta = cos(theta)
        let topS = sinLat * cosTheta * rx + sinLat * sinTheta * ry - cosLat * rz
        let topE = -sinTheta * rx + cosTheta * ry
        let topZ = cosLat * cosTheta * rx + cosLat * sinTheta * ry + sinLat * rz

        // Match north-based convention (0=N, 90=E) used by OrbitalObject.calculateObs
        var azim = atan(-topE / topS)
        if topS > 0.0 { azim += PI }
        if azim < 0.0 { azim += TWO_PI }
        let el = asin(topZ / rMag)
        let rangeRate = (rx * rvx + ry * rvy + rz * rvz) / rMag

        return [azim, el, rMag, rangeRate]
    }

    private static let MFACTOR = 7.292115e-5

    private static func primeAngle(_ x: Double) -> Double {
        x - 360.0 * floor(x / 360.0)
    }

    private static func fixAngle(_ x: Double) -> Double {
        var a = x
        while a > TWO_PI { a -= TWO_PI }
        return a
    }
}

// MARK: - Numeric extensions

private extension Double {
    func toRadians() -> Double { self * DEG2RAD }
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
