//
//  BatteryStatusRxMessageTests.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Full-frame fixture is the wire sample documented alongside
//  BatteryStatusTxMessage.
//

import XCTest
@testable import G6SensorCore

class BatteryStatusRxMessageTests: XCTestCase {
    func testFullMessage() {
        let data = Data(hexadecimalString: "23003c012f01cd021f247bae")!
        let message = BatteryStatusRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(316, message.voltageA)
        XCTAssertEqual(303, message.voltageB)
        XCTAssertEqual(717, message.resist)
        XCTAssertEqual(31, message.runtime)
        XCTAssertEqual(36, message.temperature)
    }

    func testShortMessageOmitsRuntimeAndTemperature() {
        // 10-byte frame from older firmware: no runtime/temperature bytes.
        let data = Data(hexadecimalString: "23003c012f01cd02")!.appendingCRC()
        XCTAssertEqual(10, data.count)
        let message = BatteryStatusRxMessage(data: data)!

        XCTAssertEqual(316, message.voltageA)
        XCTAssertEqual(303, message.voltageB)
        XCTAssertEqual(717, message.resist)
        XCTAssertNil(message.runtime)
        XCTAssertNil(message.temperature)
    }

    func testInvalidCRCReturnsNil() {
        var data = Data(hexadecimalString: "23003c012f01cd021f247bae")!
        data[data.count - 1] ^= 0xff
        XCTAssertNil(BatteryStatusRxMessage(data: data))
    }

    func testWrongOpcodeReturnsNil() {
        let data = Data(hexadecimalString: "22003c012f01cd02")!.appendingCRC()
        XCTAssertNil(BatteryStatusRxMessage(data: data))
    }
}
