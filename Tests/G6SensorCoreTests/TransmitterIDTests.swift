//
//  TransmitterIDTests.swift
//  xDripG5Tests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import G6SensorCore

class TransmitterIDTests: XCTestCase {

    /// Sanity check the hash computation path
    func testComputeHash() {
        let id = TransmitterID(id: "123456")

        XCTAssertEqual("e60d4a7999b0fbb2", id.computeHash(of: Data(hexadecimalString: "0123456789abcdef")!)!.hexadecimalString)
    }

    /// The prefix decides the model: 8… is G6, 5… and C… are Dexcom ONE.
    func testModelByPrefix() {
        XCTAssertEqual(TransmitterID(id: "8ZXY12").model, .g6)
        XCTAssertEqual(TransmitterID(id: "5ZXY12").model, .one)
        XCTAssertEqual(TransmitterID(id: "CZXY12").model, .one)
        XCTAssertEqual(TransmitterID(id: "cZXY12").model, .one)
    }

    /// An unrecognized prefix is the stock case, not a failure.
    func testUnknownPrefixFallsBackToG6() {
        XCTAssertEqual(TransmitterID(id: "9ZXY12").model, .g6)
    }

}
