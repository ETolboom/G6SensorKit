//
//  CalibrationStateSemanticsTests.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import XCTest
@testable import G6SensorCore

class CalibrationStateSemanticsTests: XCTestCase {
    func testOkIsReliableAndNotFailed() {
        let state = CalibrationState(rawValue: 6)
        XCTAssertTrue(state.hasReliableGlucose)
        XCTAssertFalse(state.isSensorFailed)
        XCTAssertFalse(state.needsCalibration)
        XCTAssertFalse(state.isInWarmup)
    }

    func testWarmupWithholdsGlucose() {
        let state = CalibrationState(rawValue: 2)
        XCTAssertTrue(state.isInWarmup)
        XCTAssertFalse(state.hasReliableGlucose)
    }

    func testStoppedSession() {
        let state = CalibrationState(rawValue: 1)
        XCTAssertTrue(state.isStopped)
        XCTAssertFalse(state.hasReliableGlucose)
    }

    func testSensorFailureStates() {
        for raw: UInt8 in [11, 12, 15, 16, 17] {
            let state = CalibrationState(rawValue: raw)
            XCTAssertTrue(state.isSensorFailed, "raw \(raw) should be a failure")
            XCTAssertFalse(state.hasReliableGlucose, "raw \(raw) must not yield glucose")
        }
    }

    func testCalibrationRequestStatesStillYieldGlucose() {
        // 7 and 14 request calibration but keep sending usable values.
        for raw: UInt8 in [7, 14] {
            let state = CalibrationState(rawValue: raw)
            XCTAssertTrue(state.needsCalibration)
            XCTAssertTrue(state.hasReliableGlucose)
        }
    }

    func testInitialCalibrationStatesWithholdGlucose() {
        for raw: UInt8 in [4, 5] {
            let state = CalibrationState(rawValue: raw)
            XCTAssertTrue(state.needsCalibration)
            XCTAssertFalse(state.hasReliableGlucose)
        }
    }

    func testUnknownStateIsConservative() {
        let state = CalibrationState(rawValue: 200)
        XCTAssertFalse(state.hasReliableGlucose)
        XCTAssertFalse(state.isSensorFailed)
        XCTAssertFalse(state.needsCalibration)
    }
}
