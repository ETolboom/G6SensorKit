//
//  SensorCodeTests.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import XCTest
@testable import G6SensorCore

class SensorCodeTests: XCTestCase {
    func testKnownCodePairsShareParameters() {
        let a = SensorCode("5915")!
        let b = SensorCode("9759")!
        XCTAssertEqual(3100, a.parameter1)
        XCTAssertEqual(3600, a.parameter2)
        XCTAssertEqual(a.parameter1, b.parameter1)
        XCTAssertEqual(a.parameter2, b.parameter2)
        XCTAssertTrue(a.carriesParameters)
    }

    func testNullCodeAndNilAreCodeless() {
        XCTAssertEqual(SensorCode.none, SensorCode("0000"))
        XCTAssertEqual(SensorCode.none, SensorCode(nil))
        XCTAssertFalse(SensorCode.none.carriesParameters)
    }

    func testUnknownCodeIsRejected() {
        XCTAssertNil(SensorCode("1234"))
        XCTAssertNil(SensorCode(""))
    }

    func testSessionStartFrameWithoutCodeKeepsOriginalLayout() {
        let message = SessionStartTxMessage(startTime: 100, secondsSince1970: 200)
        // opcode + 4 + 4 + CRC(2) = 11 bytes
        XCTAssertEqual(11, message.data.count)
        XCTAssertEqual(0x26, message.data[0])
        XCTAssertTrue(message.data.isCRCValid)
    }

    func testSessionStartFrameWithCodeAppendsParameters() {
        let code = SensorCode("9713")!
        let message = SessionStartTxMessage(startTime: 100, secondsSince1970: 200, sensorCode: code)
        // opcode + 4 + 4 + 2 + 2 + CRC(2) = 15 bytes
        XCTAssertEqual(15, message.data.count)
        // parameter1 = 2300 little-endian at bytes 9..10
        XCTAssertEqual(UInt16(2300), message.data[9..<11].to(UInt16.self))
        XCTAssertEqual(UInt16(2900), message.data[11..<13].to(UInt16.self))
        XCTAssertTrue(message.data.isCRCValid)
    }
}
