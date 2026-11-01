//  Look4Sat iOS port — Yaesu FT-817/818/897 CAT protocol (BCD)
//  Ported 1:1 from Kotlin: core/data/.../framework/Ft817CatProtocol.kt
//  License: GPL-3.0
//
//  The FT-817 CAT dialect is a 5-byte little-endian framed protocol:
//    [4 bytes BCD data][1 byte command]
//  Frequency is encoded as 4-byte BCD with 10 Hz resolution.
import Foundation

public enum  Ft817CatProtocol {
    // ── Command bytes ───────────────────────────────────────────────
    // Kotlin sources use `.toByte()` (two's complement) for values ≥ 0x80.
    // Swift Int8 has a −128…127 range, so literal 0x88/0x8A overflows;
    // use `Int8(bitPattern:)` to preserve the exact byte value.
    static let cmdSetFreq: Int8 = 0x01
    static let cmdReadFreqMode: Int8 = 0x03
    static let cmdSetMode: Int8 = 0x07
    static let cmdPttOn: Int8 = 0x08
    static let cmdPttOff: Int8 = Int8(bitPattern: 0x88)
    static let cmdCtcssMode: Int8 = 0x0A
    static let cmdCtcssTone: Int8 = 0x0B
    static let ctcssEncOn: Int8 = 0x2A
    static let ctcssOff: Int8 = Int8(bitPattern: 0x8A)

    /// Mode string (upper-case) → FT-817 mode byte.
    static let modeToByte: [String: Int8] = [
        "LSB": 0x00, "USB": 0x01, "CW": 0x02, "CW-R": 0x03,
        "AM": 0x04, "FM": 0x08, "DIG": 0x0A, "PKT": 0x0C,
    ]
    /// Byte → mode string (inverse of the above).
    static let byteToMode: [Int8: String] = [
        0x00: "LSB", 0x01: "USB", 0x02: "CW", 0x03: "CW-R",
        0x04: "AM", 0x08: "FM", 0x0A: "DIG", 0x0C: "PKT",
    ]

    // MARK: BCD encoding

    /// Encode a frequency in Hz to 4-byte BCD with 10 Hz resolution.
    /// Example: 145 500 000 Hz → [0x14, 0x55, 0x00, 0x00].
    public static func encodeFrequencyBcd(_ frequencyHz: Int64) -> [UInt8] {
        let freq10Hz = frequencyHz / 10
        let digits = String(format: "%08d", freq10Hz)
        var bcd = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            let high = UInt8(digits[digits.index(digits.startIndex, offsetBy: i * 2)].asciiValue! - 0x30)
            let low = UInt8(digits[digits.index(digits.startIndex, offsetBy: i * 2 + 1)].asciiValue! - 0x30)
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    /// Decode 4-byte BCD frequency to Hz.
    public static func decodeFrequencyBcd(_ bcd: [UInt8]) -> Int64 {
        var freq10Hz: Int64 = 0
        for i in 0..<4 {
            let b = Int64(bcd[i])
            let high = b >> 4
            let low = b & 0x0F
            freq10Hz = freq10Hz * 100 + high * 10 + low
        }
        return freq10Hz * 10
    }

    /// Encode a CTCSS tone (Hz, e.g. 67.0) to 2-byte BCD (0.1 Hz resolution).
    public static func encodeCtcssToneBcd(_ toneHz: Double) -> [UInt8] {
        let tone01 = Int64((toneHz * 10).rounded())
        let digits = String(format: "%04d", tone01)
        var bcd = [UInt8](repeating: 0, count: 2)
        for i in 0..<2 {
            let high = UInt8(digits[digits.index(digits.startIndex, offsetBy: i * 2)].asciiValue! - 0x30)
            let low = UInt8(digits[digits.index(digits.startIndex, offsetBy: i * 2 + 1)].asciiValue! - 0x30)
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    // MARK: Command builders

    public static func buildSetFreqCommand(_ frequencyHz: Int64) -> [UInt8] {
        let bcd = encodeFrequencyBcd(frequencyHz)
        return [bcd[0], bcd[1], bcd[2], bcd[3], UInt8(cmdSetFreq)]
    }

    public static func buildSetModeCommand(_ mode: String) -> [UInt8]? {
        guard let b = modeToByte[mode.uppercased()] else { return nil }
        return [UInt8(b), 0x00, 0x00, 0x00, UInt8(cmdSetMode)]
    }

    public static func buildReadFreqModeCommand() -> [UInt8] {
        [0x00, 0x00, 0x00, 0x00, UInt8(cmdReadFreqMode)]
    }

    public static func buildPttOnCommand() -> [UInt8] {
        [0x00, 0x00, 0x00, 0x00, UInt8(cmdPttOn)]
    }

    public static func buildPttOffCommand() -> [UInt8] {
        [0x00, 0x00, 0x00, 0x00, UInt8(bitPattern: cmdPttOff)]
    }

    public static func buildCtcssModeCommand(_ enabled: Bool) -> [UInt8] {
        let sub: Int8 = enabled ? ctcssEncOn : ctcssOff
        return [UInt8(sub), 0x00, 0x00, 0x00, UInt8(cmdCtcssMode)]
    }

    public static func buildSetCtcssToneCommand(_ toneHz: Double) -> [UInt8] {
        let bcd = encodeCtcssToneBcd(toneHz)
        return [bcd[0], bcd[1], 0x00, 0x00, UInt8(cmdCtcssTone)]
    }

    // MARK: Response parsing

    /// Parse the 5-byte READ FREQ+MODE response.
    /// Returns (frequencyHz, modeString), or nil on failure.
    public static func parseReadResponse(_ response: [UInt8]) -> (Int64, String)? {
        guard response.count >= 5 else { return nil }
        let freqHz = decodeFrequencyBcd(Array(response[0..<4]))
        guard let mode = byteToMode[Int8(response[4])] else { return nil }
        return (freqHz, mode)
    }
}
