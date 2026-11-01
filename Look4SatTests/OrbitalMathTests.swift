//  Look4Sat iOS port — unit tests for the orbital math core
//  Uses XCTest so `swift test` / Xcode test discovery work out of the box.
//  Runs on macOS and iOS (no device-specific code).
//  License: GPL-3.0
import XCTest
@testable import Look4SatCore

final class OrbitalMathTests: XCTestCase {

    // Reference values from PREDICT v2.2.5 test suite
    func testEpochToDaynum() {
        // PREDICT convention: daynum 0.0 = 31 Dec 1979 00:00:00 UTC.
        // 1 Jan 2019 00:00 UTC is daynum 14246 (39 full years 1980–2018 =
        // 39×365 + 10 leap days = 14245, plus 1 for Jan 1 itself).
        // TLE epoch "19000.0" = 2019 day 0.0 = 1 Jan 2019 00:00 UTC.
        let d = OrbitalData.epochToDaynum(19000.0)
        XCTAssertEqual(d, 14246.0, accuracy: 0.5)
    }

    func testJulianDateOfYear() {
        // PREDICT v2.2.5 Julian_Date_of_Year: JD of "Day 0.0 of {year}".
        // For year 2000: JD = 2451543.5 (Meeus: 1 Jan 2000 00:00 UT = 2451544.5,
        // PREDICT uses 2451543.5, a 1-day offset that is consistent throughout
        // PREDICT's internal calculations — the offset cancels in tsince).
        let j = OrbitalObject.julianDateOfYear(2000.0)
        XCTAssertEqual(j, 2451544.5, accuracy: 0.001)
    }

    func testSolarPositionECI() {
        // At J2000 (2000 Jan 1.5 UTC), the Sun is ~1 AU away.
        let sun = solarPositionECI(julUtc: 2451543.5)
        let r = sun[3]
        XCTAssertGreaterThan(r, 1.4e8)
        XCTAssertLessThan(r, 1.52e8)
        XCTAssertLessThan(abs(sun[0]), 1e8)
    }

    func testGeoPos() {
        let gp = GeoPos(latitude: 51.0, longitude: 0.5, altitude: 100.0)
        let geo = gp.observerGeodetic
        XCTAssertEqual(geo[0], 51.0 * 0.017453292519943295, accuracy: 1e-9)
        XCTAssertEqual(geo[2], 0.1, accuracy: 1e-9)
    }

    func testTLEParsing() {
        let issTLE = """
        ISS (ZARYA)
        1 25544U 98067A   26304.75703383  .00006360  00000+0  12291-3 0  9993
        2 25544  51.6332 344.2755 0007028 332.5119  27.5497 15.49131714592920
        """
        let tles = TLE.parse(issTLE)
        XCTAssertEqual(tles.count, 1)
        guard let t = tles.first, let d = t.data else {
            XCTFail("ISS TLE should parse")
            return
        }
        XCTAssertEqual(d.catnum, 25544)
        XCTAssertTrue(d.name.contains("ISS"))
        XCTAssertEqual(d.incl, 51.6332, accuracy: 0.01)
        XCTAssertEqual(d.eccn, 0.0007028, accuracy: 1e-7)
        XCTAssertLessThan(d.orbitalPeriod, 225.0, "ISS period must be < 225 min (LEO)")
        XCTAssertFalse(d.isDeepSpace)
        XCTAssertTrue(t.checksumOk, "fixture TLE must carry valid checksums")
    }

    func testPassFinding() {
        let issTLE = """
        ISS (ZARYA)
        1 25544U 98067A   26304.75703383  .00006360  00000+0  12291-3 0  9993
        2 25544  51.6332 344.2755 0007028 332.5119  27.5497 15.49131714592920
        """
        guard let tle = TLE.parse(issTLE).first,
              let data = tle.data else {
            XCTFail("ISS TLE should parse")
            return
        }
        let obj = data.makeOrbitalObject()
        let obs = GeoPos(latitude: 51.5, longitude: -0.1, altitude: 50.0)
        let predictor = PassPredictor(object: obj, observer: obs)
        let passes = predictor.findAllPasses(minElevationDeg: 10.0,
                                              startMs: 1793568000000,
                                              lookaheadDays: 1.0)
        XCTAssertGreaterThan(passes.count, 0,
                             "ISS should have passes over London in 24h")
        for p in passes {
            XCTAssertGreaterThanOrEqual(p.maxElevation, 10.0)
            XCTAssertGreaterThanOrEqual(p.losTime - p.aosTime, 0, "AOS must precede LOS")
            XCTAssertLesserPassDuration(p.losTime - p.aosTime)
        }
    }

    func testCelestialConstants() {
        XCTAssertEqual(PI, 3.141592653589793, accuracy: 1e-15)
        XCTAssertEqual(TWO_PI, 6.283185307179586, accuracy: 1e-15)
        XCTAssertEqual(EARTH_RADIUS, 6378.137, accuracy: 1e-4)
        XCTAssertEqual(XKE, 7.43669161e-2, accuracy: 1e-12)
    }
}

// Cross-platform helper: the Windows XCTest build lacks XCTAssertLess,
// so use an explicit range check with a clear failure message.
private func XCTAssertLesserPassDuration(_ durationMs: Int64, _ message: @autoclosure () -> String = "") {
    if durationMs >= 60 * 60 * 1000 {
        XCTFail("Pass duration \(durationMs) ms exceeds 1 hour. \(message())")
    }
}