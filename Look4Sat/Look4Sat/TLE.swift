//  Look4Sat iOS port — TLE parser
//  Ported from the TLE parsing logic in Look4Sat's data layer.
//  License: GPL-3.0
//
//  Parses Two-Line Element (TLE) sets into OrbitalData structures.
//  TLE format (standard NORAD), each element set is 3 lines:
//    Line 0: name (max 24 chars)
//    Line 1: "1 NNNNNNNNNN CYYYYDDDD.ffffff 00000-0 00000-0 0 00000"
//    Line 2: "2 NNNNNNNNNN I I I I I I I I I I I I I I I I I I I I I I I I"
//
//  Column positions below are 0-indexed, matching the standard TLE layout:
//    Line 1:  epoch      18-32 (cols 18...32, 15 chars)
//              ndot/2     34-43
//              bstar      54-62
//              catnum      2-6
//    Line 2:  catnum      2-6
//              incl        8-15
//              raan        16-23
//              ecc         26-32 (stored without leading zero)
//              argper      34-41
//              meanan      44-51
//              meanmo      53-62
import Foundation

/// A single parsed TLE set.
public struct TLE: Hashable, Codable {
    public let name: String
    public let line1: String
    public let line2: String
    public let checksumOk: Bool

    /// Parsed into the orbital data used by the propagator.
    public var data: OrbitalData? {
        guard line1.count >= 69, line2.count >= 69 else { return nil }

        func col(_ line: String, _ from: Int, _ to: Int) -> String {
            guard to < line.count else { return "" }
            let start = line.index(line.startIndex, offsetBy: from)
            let end = line.index(line.startIndex, offsetBy: to + 1)
            return String(line[start..<end]).trimmingCharacters(in: .whitespaces)
        }

        // --- Line 1 ---
        let epochStr = col(line1, 18, 32)
        let ndotStr = col(line1, 34, 43)
        let bstarStr = col(line1, 54, 62)
        let catnumStr = col(line1, 2, 6)

        guard let epoch = Double(epochStr), epoch != 0.0 else { return nil }
        let ndot = Double(ndotStr) ?? 0.0
        let bstar = Double(bstarStr) ?? 0.0
        let catnum = Int(catnumStr) ?? 0

        // --- Line 2 ---
        // Standard TLE columns (0-indexed, half-open slices; the 69-char layout):
        //   incl   cols 8..15    e.g. " 51.6332"
        //   raan   cols 16..23
        //   ecc    cols 25..32   (8 digits, leading "0." implicit; col 24 is the group space)
        //   argper cols 34..41
        //   meanan cols 43..50   (col 42 is the group space, col 43 carries a '-' if negative)
        //   meanmo cols 52..62   (10 chars incl. decimal point, e.g. "15.4913171")
        let inclStr = col(line2, 8, 15)
        let raanStr = col(line2, 16, 23)
        let eccStr = col(line2, 25, 32)
        let argperStr = col(line2, 34, 41)
        let meananStr = col(line2, 43, 50)
        let meanmoStr = col(line2, 52, 62)

        guard let incl = Double(inclStr) else { return nil }
        let raan = Double(raanStr) ?? 0.0
        // Eccentricity is stored without a leading zero: "0006703" → 0.0006703
        let eccn = Double("0.\(eccStr)") ?? 0.0
        let argper = Double(argperStr) ?? 0.0
        let meanan = Double(meananStr) ?? 0.0
        guard let meanmo = Double(meanmoStr) else { return nil }

        return OrbitalData(
            name: name,
            epoch: epoch,
            meanmo: meanmo,
            eccn: eccn,
            incl: incl,
            raan: raan,
            argper: argper,
            meanan: meanan,
            catnum: catnum,
            bstar: bstar,
            ndot: ndot
        )
    }

    /// Parse a multi-record TLE text block. Each record is:
    ///   optional name line (not the "1 ..." / "2 ..." lines)
    ///   1 <line>
    ///   2 <line>
    public static func parse(_ text: String) -> [TLE] {
        // Normalize CRLF → LF.
        let lines = text.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")

        var result: [TLE] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("1"), i + 1 < lines.count, lines[i + 1].hasPrefix("2")
            else {
                i += 1
                continue
            }
            // Pad both element lines to 69 chars so column slices stay valid.
            let l1 = line.count >= 69 ? line : line.padding69()
            let l2 = lines[i + 1].count >= 69 ? lines[i + 1] : lines[i + 1].padding69()
            let nameLine = i > 0 && !lines[i - 1].hasPrefix("1") ? lines[i - 1] : ""

            result.append(TLE(
                name: String(nameLine.prefix(24)).trimmingCharacters(in: .whitespaces),
                line1: l1,
                line2: l2,
                checksumOk: TLE.verifyChecksum(l1) && TLE.verifyChecksum(l2)
            ))
            i += 2
        }
        return result
    }

    /// Verify the TLE checksum (col 69, i.e. 0-indexed 68; single digit).
    /// A '-' in the body counts as 1 per the standard.
    public static func verifyChecksum(_ line: String) -> Bool {
        guard line.count >= 69 else { return false }
        let body = line.prefix(68)
        var sum = 0
        for ch in body {
            if ch == "-" {
                sum += 1
            } else if let d = ch.wholeNumberValue {
                sum += d
            }
        }
        let expected = sum % 10
        let actual = Int(line[line.index(line.endIndex, offsetBy: -1)].wholeNumberValue ?? -1)
        return actual == expected
    }
}

private extension String {
    /// Pad (or truncate) to exactly 69 chars, right-justifying with spaces.
    func padding69() -> String {
        if count >= 69 { return String(prefix(69)) }
        return self + String(repeating: " ", count: 69 - count)
    }
}
