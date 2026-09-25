//
//  PassiveMessageHandlerTests.swift
//  G6SensorKitTests
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  The captured-traffic fixtures come from CGMBLEKit's test suite
//  (GlucoseTests, GlucoseBackfillMessageTests), originally xDripG5.
//  Copyright © 2016-2018 LoopKit Authors. (MIT License)
//

import XCTest
@testable import G6SensorCore

class PassiveMessageHandlerTests: XCTestCase {

    // Captured G6 traffic, same fixtures as the codec tests.
    let timeFrame = Data(hexadecimalString: "2500470272007cff710001000000fa1d")!
    let glucoseFrame = Data(hexadecimalString: "3100680a00008a715700cc0006ffc42a")!
    let calibrationFrame = Data(hexadecimalString: "33002b290090012900ae00800050e929001225")!
    let versionFrame = Data(hexadecimalString: "4b0001000011df2900005100037000f00009b6")!
    let backfillAck = Data(hexadecimalString: "51000100b7ff52006604530032000000e6cb9805")!
    let backfillFrames = [
        Data(hexadecimalString: "0100bc460000b7ff52008b0006eee30053008500")!,
        Data(hexadecimalString: "020006eb0f025300800006ee3a0353007e0006f5")!,
        Data(hexadecimalString: "030066045300790006f8")!,
    ]

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func handler(seedActivation: Bool = false) -> PassiveMessageHandler {
        PassiveMessageHandler(
            transmitterID: "123456",
            activationDate: seedActivation ? now.addingTimeInterval(-1_000_000) : nil
        )
    }

    // MARK: - Authentication

    func testAuthChallengeIsReported() {
        let events = handler().handleAuthentication(Data(hexadecimalString: "050101")!)

        guard case .observedAuthentication(let isAuthenticated, let isBonded) = events.first else {
            return XCTFail("Expected observedAuthentication, got \(events)")
        }
        XCTAssertTrue(isAuthenticated)
        XCTAssertTrue(isBonded)
    }

    func testOtherAuthTrafficIsIgnored() {
        // AuthRequestRx (0x03) carries nothing worth reporting.
        XCTAssertTrue(handler().handleAuthentication(Data(hexadecimalString: "0300a1b2c3d4e5f6a7b8")!).isEmpty)
    }

    // MARK: - Time and glucose

    func testGlucoseDroppedBeforeAnyTimeFrame() {
        let events = handler().handleControl(glucoseFrame, at: now)

        guard case .error(let error) = events.first, events.count == 1 else {
            return XCTFail("Expected a single error, got \(events)")
        }
        guard case .observationError = error else {
            return XCTFail("Expected observationError, got \(error)")
        }
    }

    func testSeededActivationDateAloneCannotDateGlucose() {
        // The session start time comes from the time message, not the
        // activation date, so a seeded date alone is not enough.
        let events = handler(seedActivation: true).handleControl(glucoseFrame, at: now)

        guard case .error = events.first, events.count == 1 else {
            return XCTFail("Expected a single error, got \(events)")
        }
    }

    func testTimeFrameDerivesActivationDate() {
        let handler = handler()
        let events = handler.handleControl(timeFrame, at: now)

        let currentTime = TransmitterTimeRxMessage(data: timeFrame)!.currentTime
        let expected = now.addingTimeInterval(-TimeInterval(currentTime))

        guard case .transmitterTime(let activationDate) = events.first, events.count == 1 else {
            return XCTFail("Expected transmitterTime, got \(events)")
        }
        XCTAssertEqual(expected, activationDate)
        XCTAssertEqual(expected, handler.activationDate)
    }

    func testGlucoseAfterTimeFrame() {
        let handler = handler()
        handler.handleControl(timeFrame, at: now)
        let events = handler.handleControl(glucoseFrame, at: now)

        guard case .glucose(let glucose) = events.first, events.count == 1 else {
            return XCTFail("Expected glucose, got \(events)")
        }
        XCTAssertEqual(204, glucose.glucoseMgDL)
        XCTAssertEqual(.known(.ok), glucose.state)
        XCTAssertTrue(glucose.hasValidSensorSession)
        XCTAssertNil(glucose.lastCalibration)
    }

    // MARK: - Calibration

    func testCalibrationIsCachedAndAttachedToLaterReadings() {
        let handler = handler()
        XCTAssertTrue(handler.handleControl(calibrationFrame, at: now).isEmpty)

        handler.handleControl(timeFrame, at: now)
        let events = handler.handleControl(glucoseFrame, at: now)

        guard case .glucose(let glucose) = events.first else {
            return XCTFail("Expected glucose, got \(events)")
        }
        XCTAssertNotNil(glucose.lastCalibration)
    }

    // MARK: - Transmitter version

    func testTransmitterVersionIsForwarded() {
        let events = handler().handleControl(versionFrame, at: now)

        guard case .transmitterVersion(let message) = events.first, events.count == 1 else {
            return XCTFail("Expected transmitterVersion, got \(events)")
        }
        XCTAssertEqual(112, message.transmitterExpiryInDays)
    }

    // MARK: - Backfill

    private func primedHandler() -> PassiveMessageHandler {
        let handler = handler()
        handler.handleControl(timeFrame, at: now)
        return handler
    }

    func testCompleteBackfill() {
        let handler = primedHandler()
        for frame in backfillFrames {
            handler.handleBackfill(frame)
        }
        let events = handler.handleControl(backfillAck, at: now)

        guard case .backfill(let readings) = events.first, events.count == 1 else {
            return XCTFail("Expected backfill, got \(events)")
        }
        XCTAssertEqual(5, readings.count)
        XCTAssertEqual(139, readings.first?.glucoseMgDL)
        XCTAssertEqual(121, readings.last?.glucoseMgDL)
    }

    func testBackfillAckWithoutFramesIsAnError() {
        let events = primedHandler().handleControl(backfillAck, at: now)

        guard case .error = events.first, events.count == 1 else {
            return XCTFail("Expected a single error, got \(events)")
        }
    }

    func testBackfillEmptyWindowIsNotAnError() {
        // An ack reporting zero bytes stored is an empty result.
        var ack = Data([0x51, 0x00, 0x00, 0x00])
        ack.append(UInt32(1000))
        ack.append(UInt32(2000))
        ack.append(UInt32(0))
        ack.append(UInt16(0))
        ack = ack.appendingCRC()

        XCTAssertTrue(primedHandler().handleControl(ack, at: now).isEmpty)
    }

    func testBackfillCRCMismatch() {
        let handler = primedHandler()
        for frame in backfillFrames {
            handler.handleBackfill(frame)
        }

        // Same ack but a corrupted buffer CRC (message CRC recomputed so the
        // ack itself still parses).
        var bytes = [UInt8](backfillAck)
        bytes[16] ^= 0xff
        let corrupted = Data(bytes[0..<18]).appendingCRC()

        let events = handler.handleControl(corrupted, at: now)

        guard case .error = events.first, events.count == 1 else {
            return XCTFail("Expected a single error, got \(events)")
        }
    }

    func testPartialBackfillDeliversPrefixWithError() {
        let handler = primedHandler()
        // Two of the three frames; the buffer is a valid prefix.
        handler.handleBackfill(backfillFrames[0])
        handler.handleBackfill(backfillFrames[1])
        let events = handler.handleControl(backfillAck, at: now)

        guard case .backfill(let readings) = events.first else {
            return XCTFail("Expected backfill, got \(events)")
        }
        // Each full frame carries two 8-byte sub-messages past the header.
        XCTAssertEqual(4, readings.count)
        guard case .error = events.last, events.count == 2 else {
            return XCTFail("Expected a trailing incompleteness error, got \(events)")
        }
    }

    func testBackfillDroppedBeforeAnyTimeFrame() {
        let handler = handler()
        for frame in backfillFrames {
            handler.handleBackfill(frame)
        }
        let events = handler.handleControl(backfillAck, at: now)

        guard case .error = events.first, events.count == 1 else {
            return XCTFail("Expected a single error, got \(events)")
        }
    }

    // MARK: - Unknown traffic

    func testUnknownOpcode() {
        // 0x09 (disconnectTx) is a known opcode but meaningless as observed
        // traffic; 0x7f is not an opcode at all.
        for hex in ["0900aa55", "7f00aa55"] {
            let events = handler().handleControl(Data(hexadecimalString: hex)!, at: now)
            guard case .unknown(let data) = events.first, events.count == 1 else {
                return XCTFail("Expected unknown for \(hex), got \(events)")
            }
            XCTAssertEqual(hex, data.hexadecimalString)
        }
    }
}
