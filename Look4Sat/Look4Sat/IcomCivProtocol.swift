//  Look4Sat iOS port — Icom CI-V protocol for IC-705 (with band + SPLIT)
//  Ported 1:1 from Kotlin: core/data/.../framework/IcomCivProtocol.kt
//  License: GPL-3.0
//
//  Frame structure:  FE FE [dest] [src] [payload…] FD
//  IC-705 default CI-V address = 0xA4; controller address = 0xE0.
//  Frequency is 5-byte BCD (LSB pair first), 1 Hz resolution.
import Foundation

public enum  IcomCivProtocol {
    // ── Framing constants ────────────────────────────────────────────
    // Kotlin uses `.toByte()` for values ≥ 0x80. Swift Int8 is −128…127,
    // so use `Int8(bitPattern:)` to hold the raw byte value.
    static let preamble: Int8 = Int8(bitPattern: 0xFE)
    static let endOfMsg: Int8 = Int8(bitPattern: 0xFD)
    static let ackOk: Int8 = Int8(bitPattern: 0xFB)
    static let ackNg: Int8 = Int8(bitPattern: 0xFA)

    // ── Address constants ───────────────────────────────────────────
    /// Default CI-V address of the IC-705.
    static let addrIc705: Int8 = Int8(bitPattern: 0xA4)
    /// Default CI-V address of the controller (us).
    static let addrCtrl: Int8 = Int8(bitPattern: 0xE0)

    // ── Command bytes ───────────────────────────────────────────────
    static let cmdReadFreq: Int8 = 0x03        // read operating frequency
    static let cmdSetFreq: Int8 = 0x05         // set operating frequency
    static let cmdSetMode: Int8 = 0x06         // set mode
    static let cmdSelectVfo: Int8 = 0x07       // select VFO / memory
    static let cmdSelectOpMode: Int8 = 0x08   // VFO vs memory-channel
    static let cmdDuplexSplit: Int8 = 0x0F    // SPLIT on/off
    static let cmdBandSelect: Int8 = 0x1A     // band stacking select
    static let cmdCtcssTone: Int8 = 0x1B      // CTCSS tone read/write
    static let cmdMiscSetting: Int8 = 0x16     // misc settings
    static let cmdSelectedVfoFreq: Int8 = 0x25 // selected-VFO freq

    // ── Sub-command bytes ───────────────────────────────────────────
    static let subVfoA: Int8 = 0x00
    static let subVfoB: Int8 = 0x01
    static let subSplitOff: Int8 = 0x00
    static let subSplitOn: Int8 = 0x01
    static let subSelectedVfo: Int8 = 0x00
    static let subUnselectedVfo: Int8 = 0x01
    static let subCtcssSetting: Int8 = 0x42

    // ── Mode bytes ──────────────────────────────────────────────────
    static let modeToByte: [String: Int8] = [
        "LSB": 0x00, "USB": 0x01, "AM": 0x02, "CW": 0x03,
        "RTTY": 0x04, "FM": 0x05, "WFM": 0x06, "CW-R": 0x07,
        "RTTY-R": 0x08, "DV": 0x12,
    ]
    static let byteToMode: [Int8: String] = [
        0x00: "LSB", 0x01: "USB", 0x02: "AM", 0x03: "CW",
        0x04: "RTTY", 0x05: "FM", 0x06: "WFM", 0x07: "CW-R",
        0x08: "RTTY-R", 0x12: "DV",
    ]

    // MARK: BCD frequency encoding (5 bytes, 1 Hz)

    /// Encode frequency Hz to the IC-705 5-byte BCD (LSB pair first).
    /// 145 500 000 Hz → [0x00, 0x00, 0x50, 0x45, 0x01].
    public static func encodeFrequencyBcd(_ frequencyHz: Int64) -> [UInt8] {
        let digits = String(format: "%010d", frequencyHz)
        var bcd = [UInt8](repeating: 0, count: 5)
        for i in 0..<5 {
            let pairIndex = 4 - i
            let hi = digits.index(digits.startIndex, offsetBy: pairIndex * 2)
            let lo = digits.index(digits.startIndex, offsetBy: pairIndex * 2 + 1)
            let high = UInt8(digits[hi].asciiValue! - 0x30)
            let low = UInt8(digits[lo].asciiValue! - 0x30)
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    /// Decode 5-byte BCD (LSB pair first) to Hz.
    public static func decodeFrequencyBcd(_ bcd: [UInt8]) -> Int64 {
        var freqHz: Int64 = 0
        for i in stride(from: 4, through: 0, by: -1) {
            let b = Int64(bcd[i])
            let high = b >> 4
            let low = b & 0x0F
            freqHz = freqHz * 100 + high * 10 + low
        }
        return freqHz
    }

    /// Encode a CTCSS tone (Hz, e.g. 67.0) to 2-byte BCD (0.1 Hz).
    public static func encodeCtcssToneBcd(_ toneHz: Double) -> [UInt8] {
        let tone01 = Int64((toneHz * 10).rounded())
        let digits = String(format: "%04d", tone01)
        var bcd = [UInt8](repeating: 0, count: 2)
        for i in 0..<2 {
            let hi = digits.index(digits.startIndex, offsetBy: i * 2)
            let lo = digits.index(digits.startIndex, offsetBy: i * 2 + 1)
            let high = UInt8(digits[hi].asciiValue! - 0x30)
            let low = UInt8(digits[lo].asciiValue! - 0x30)
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    // MARK: Frame builder

    /// Wrap payload bytes in a CI-V frame: FE FE ADDR_IC705 ADDR_CTRL … FD.
    public static func frame(_ payload: [UInt8]) -> [UInt8] {
        [0xFE, 0xFE, UInt8(bitPattern: addrIc705), UInt8(bitPattern: addrCtrl)] + payload + [UInt8(bitPattern: endOfMsg)]
    }

    // MARK: Command builders

    public static func buildSetFreqCommand(_ frequencyHz: Int64) -> [UInt8] {
        frame([UInt8(cmdSetFreq)] + encodeFrequencyBcd(frequencyHz))
    }

    /// Set the selected (active) VFO frequency via CMD 0x25 sub 0x00.
    public static func buildSetWorkingFreqCommand(_ frequencyHz: Int64) -> [UInt8] {
        frame([UInt8(bitPattern: cmdSelectedVfoFreq), UInt8(subSelectedVfo)] + encodeFrequencyBcd(frequencyHz))
    }

    /// Set the unselected VFO (RX VFO while split+PTT) via CMD 0x25 sub 0x01.
    public static func buildSetUnselectedVfoFreqCommand(_ frequencyHz: Int64) -> [UInt8] {
        frame([UInt8(bitPattern: cmdSelectedVfoFreq), UInt8(subUnselectedVfo)] + encodeFrequencyBcd(frequencyHz))
    }

    public static func buildReadFreqCommand() -> [UInt8] {
        frame([UInt8(cmdReadFreq)])
    }

    public static func buildReadWorkingFreqCommand() -> [UInt8] {
        frame([UInt8(bitPattern: cmdSelectedVfoFreq), UInt8(subSelectedVfo)])
    }

    public static func buildReadTxVfoFreqCommand() -> [UInt8] {
        frame([UInt8(bitPattern: cmdSelectedVfoFreq), UInt8(subUnselectedVfo)])
    }

    /// Band select via CMD 0x1A sub 0x00, BCD band number in data.
    /// Returns nil if the frequency falls in no known amateur band.
    public static func buildBandSelectCommand(_ frequencyHz: Int64) -> [UInt8]? {
        guard let code = bandCodeForFrequency(frequencyHz) else { return nil }
        return frame([UInt8(bitPattern: cmdBandSelect), 0x00, code])
    }

    /// Map a frequency to the IC-705 band-register BCD code.
    public static func bandCodeForFrequency(_ f: Int64) -> UInt8? {
        if (1_000_000...1_999_999).contains(f) { return 0x01 }       // 160 m
        if (3_500_000...3_999_999).contains(f) { return 0x02 }       // 80 m
        if (7_000_000...7_299_999).contains(f) { return 0x03 }       // 40 m
        if (10_100_000...10_149_999).contains(f) { return 0x04 }    // 30 m
        if (14_000_000...14_349_999).contains(f) { return 0x05 }    // 20 m
        if (18_068_000...18_167_999).contains(f) { return 0x06 }    // 17 m
        if (21_000_000...21_449_999).contains(f) { return 0x07 }    // 15 m
        if (24_890_000...24_989_999).contains(f) { return 0x08 }    // 12 m
        if (28_000_000...29_699_999).contains(f) { return 0x09 }    // 10 m
        if (50_000_000...53_999_999).contains(f) { return 0x10 }    // 6 m
        if (144_000_000...147_999_999).contains(f) { return 0x11 }  // 2 m
        if (420_000_000...449_999_999).contains(f) { return 0x12 }  // 70 cm
        if (1_240_000_000...1_299_999_999).contains(f) { return 0x13 } // 23 cm
        return nil
    }

    public static func buildSetModeCommand(_ mode: String) -> [UInt8]? {
        guard let b = modeToByte[mode.uppercased()] else { return nil }
        return frame([UInt8(cmdSetMode), UInt8(b)])
    }

    public static func buildSelectVfoACommand() -> [UInt8] {
        frame([UInt8(cmdSelectVfo), UInt8(subVfoA)])
    }

    public static func buildSelectVfoBCommand() -> [UInt8] {
        frame([UInt8(cmdSelectVfo), UInt8(subVfoB)])
    }

    /// Enter VFO operating mode (must be sent after connect if the radio
    /// is in memory-channel mode, else frequency/mode commands return FA).
    public static func buildEnterVfoModeCommand() -> [UInt8] {
        frame([UInt8(cmdSelectOpMode), 0x00])
    }

    public static func buildSplitModeCommand(_ enable: Bool) -> [UInt8] {
        let sub: Int8 = enable ? subSplitOn : subSplitOff
        return frame([UInt8(cmdDuplexSplit), UInt8(sub)])
    }

    public static func buildCtcssModeCommand(_ enabled: Bool) -> [UInt8] {
        let value: UInt8 = enabled ? 0x01 : 0x00
        return frame([UInt8(bitPattern: cmdMiscSetting), UInt8(subCtcssSetting), value])
    }

    public static func buildSetCtcssToneCommand(_ toneHz: Double) -> [UInt8] {
        frame([UInt8(bitPattern: cmdCtcssTone), 0x00] + encodeCtcssToneBcd(toneHz))
    }

    // MARK: Response parsing

    /// A parsed CI-V response frame.
    public struct ParsedResponse {
        public let cmd: Int8
        public let payload: [UInt8]
        /// Index in the source buffer immediately after the FD terminator.
        public let nextOffset: Int
    }

    /// Find and parse a complete CI-V response frame from a buffer.
    /// Tolerant of interleaved broadcast traffic.
    public static func parseResponse(_ buf: [UInt8], expectCmd: Int8? = nil) -> ParsedResponse? {
        var i = 0
        while i < buf.count - 5 {
            guard buf[i] == UInt8(bitPattern: preamble), buf[i + 1] == UInt8(bitPattern: preamble) else { i += 1; continue }
            let dest = Int8(bitPattern: buf[i + 2])
            let src = Int8(bitPattern: buf[i + 3])
            let cmd = Int8(bitPattern: buf[i + 4])
            if dest != addrCtrl || src != addrIc705 { i += 1; continue }
            let fdIdx = buf.indexOf(UInt8(bitPattern: endOfMsg), from: i + 5)
            if fdIdx < 0 { break } // incomplete frame, wait for more data
            let payload = Array(buf[(i + 5)..<fdIdx])
            if expectCmd == nil || cmd == expectCmd {
                return ParsedResponse(cmd: cmd, payload: payload, nextOffset: fdIdx + 1)
            }
            i = fdIdx + 1
        }
        return nil
    }

    /// Check whether a buffer contains an OK acknowledgement (FB) frame.
    public static func containsAck(_ buf: [UInt8]) -> Bool {
        var i = 0
        while i < buf.count - 5 {
            guard buf[i] == UInt8(bitPattern: preamble), buf[i + 1] == UInt8(bitPattern: preamble) else { i += 1; continue }
            let dest = Int8(bitPattern: buf[i + 2])
            let src = Int8(bitPattern: buf[i + 3])
            let cmd = Int8(bitPattern: buf[i + 4])
            if dest != addrCtrl || src != addrIc705 { i += 1; continue }
            let fdIdx = buf.indexOf(UInt8(bitPattern: endOfMsg), from: i + 5)
            if fdIdx < 0 { break }
            if cmd == ackOk { return true }
            if cmd == ackNg { return false }
            i = fdIdx + 1
        }
        return false
    }

    /// Parse frequency (+ optional mode) from a READ_FREQ reply payload.
    public static func parseFreqModePayload(_ payload: [UInt8]) -> (Int64, String)? {
        guard payload.count >= 5 else { return nil }
        let freqHz = decodeFrequencyBcd(Array(payload[0..<5]))
        let mode: String
        if payload.count > 5 {
            guard let m = byteToMode[Int8(bitPattern: payload[5])] else { return nil }
            mode = m
        } else {
            mode = ""
        }
        return (freqHz, mode)
    }

    /// Hex-dump bytes for debug logging.
    public static func toHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - UInt8Array helper

extension Array where Element == UInt8 {
    /// Find the first index of `value` at or after `startIndex`, or -1.
    /// Mirrors the Kotlin private `ByteArray.indexOf(b, startIndex)` helper.
    public func indexOf(_ value: UInt8, from startIndex: Int) -> Int {
        var idx = startIndex
        if idx < 0 { idx = 0 }
        while idx < count {
            if self[idx] == value { return idx }
            idx += 1
        }
        return -1
    }
}
