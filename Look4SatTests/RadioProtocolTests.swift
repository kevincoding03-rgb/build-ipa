//  Look4Sat iOS port — radio CAT protocol tests (hardware-independent)
//  These exercise the BCD / CI-V encoders and decoders that have no
//  dependency on a physical radio.  License: GPL-3.0
import XCTest
@testable import Look4SatCore

final class RadioProtocolTests: XCTestCase {
    // MARK: FT-817 BCD round-trips

    func testFt817FreqBcdRoundTrip() {
        // 145 500 000 Hz → BCD [0x14, 0x55, 0x00, 0x00] (10 Hz resolution)
        let bcd = Ft817CatProtocol.encodeFrequencyBcd(145_500_000)
        XCTAssertEqual(bcd.count, 4)
        XCTAssertEqual(bcd[0], 0x14)
        XCTAssertEqual(bcd[1], 0x55)
        XCTAssertEqual(bcd[2], 0x00)
        XCTAssertEqual(bcd[3], 0x00)
        XCTAssertEqual(Ft817CatProtocol.decodeFrequencyBcd(bcd), 145_500_000)
    }

    func testFt817SetFreqCommandShape() {
        // Command must be 4 BCD bytes + 1 command byte (0x01).
        let cmd = Ft817CatProtocol.buildSetFreqCommand(435_000_000)
        XCTAssertEqual(cmd.count, 5)
        XCTAssertEqual(cmd[4], 0x01)
    }

    func testFt817ModeByteMapping() {
        XCTAssertEqual(Ft817CatProtocol.buildSetModeCommand("USB")?[0], 0x01)
        XCTAssertEqual(Ft817CatProtocol.buildSetModeCommand("LSB")?[0], 0x00)
        XCTAssertNil(Ft817CatProtocol.buildSetModeCommand("BOGUS"))
    }

    func testFt817ReadResponseParse() {
        // Simulate a READ FREQ+MODE response: BCD of 145.5 MHz + mode USB (0x01)
        let bcd = Ft817CatProtocol.encodeFrequencyBcd(145_500_000)
        let response = [UInt8](bcd) + [0x01]
        let parsed = Ft817CatProtocol.parseReadResponse(response)
        XCTAssertEqual(parsed?.0, 145_500_000)
        XCTAssertEqual(parsed?.1, "USB")
    }

    func testFt817CtcssToneBcd() {
        // 67.0 Hz → 670 (0.1 Hz) → BCD [0x06, 0x70]
        let bcd = Ft817CatProtocol.encodeCtcssToneBcd(67.0)
        XCTAssertEqual(bcd, [0x06, 0x70])
    }

    // MARK: IC-705 CI-V BCD round-trips

    func testIc705FreqBcdRoundTrip() {
        // 145 500 000 Hz → 5-byte BCD (LSB pair first): [00, 00, 50, 45, 01]
        let bcd = IcomCivProtocol.encodeFrequencyBcd(145_500_000)
        XCTAssertEqual(bcd.count, 5)
        XCTAssertEqual(bcd, [0x00, 0x00, 0x50, 0x45, 0x01])
        XCTAssertEqual(IcomCivProtocol.decodeFrequencyBcd(bcd), 145_500_000)
    }

    func testIc705SetFreqCommandFrame() {
        let cmd = IcomCivProtocol.buildSetFreqCommand(435_000_000)
        // Frame: FE FE A4 E0 05 [5 BCD] FD  → 2+2+1+5+1 = 11 bytes
        XCTAssertEqual(cmd.count, 11)
        XCTAssertEqual(cmd[0], 0xFE)
        XCTAssertEqual(cmd[1], 0xFE)
        XCTAssertEqual(cmd[2], 0xA4)
        XCTAssertEqual(cmd[3], 0xE0)
        XCTAssertEqual(cmd[4], 0x05)
        XCTAssertEqual(cmd.last, 0xFD)
    }

    func testIc705BandCodeMapping() {
        XCTAssertEqual(IcomCivProtocol.bandCodeForFrequency(1_450_000), 0x01)  // 160m
        XCTAssertEqual(IcomCivProtocol.bandCodeForFrequency(7_100_000), 0x03)  // 40m
        XCTAssertEqual(IcomCivProtocol.bandCodeForFrequency(14_000_000), 0x05) // 20m
        XCTAssertEqual(IcomCivProtocol.bandCodeForFrequency(145_000_000), 0x11) // 2m
        XCTAssertEqual(IcomCivProtocol.bandCodeForFrequency(435_000_000), 0x12) // 70cm
        XCTAssertNil(IcomCivProtocol.bandCodeForFrequency(999_999))           // out of band
    }

    func testIc705ResponseParse() {
        // Build a plausible READ_FREQ reply: FE FE E0 A4 03 [5 freq bytes] FD
        let freqBcd = IcomCivProtocol.encodeFrequencyBcd(7_074_000)
        let frame: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0x03] + freqBcd + [0xFD]
        let parsed = IcomCivProtocol.parseResponse(frame, expectCmd: 0x03)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.cmd, 0x03)
        XCTAssertEqual(parsed?.payload, freqBcd)
        let fm = IcomCivProtocol.parseFreqModePayload(parsed?.payload ?? [])
        XCTAssertEqual(fm?.0, 7_074_000)
    }

    func testIc705AckDetection() {
        // OK ack frame: FE FE E0 A4 FB FD
        let ok: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0xFB, 0xFD]
        XCTAssertTrue(IcomCivProtocol.containsAck(ok))
        // NG ack frame: FE FE E0 A4 FA FD
        let ng: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0xFA, 0xFD]
        XCTAssertFalse(IcomCivProtocol.containsAck(ng))
    }

    func testIc705CtcssToneBcd() {
        // 77.0 Hz → 770 → BCD [0x07, 0x70]
        let bcd = IcomCivProtocol.encodeCtcssToneBcd(77.0)
        XCTAssertEqual(bcd, [0x07, 0x70])
    }
}
