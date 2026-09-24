//
//  CommandQueueTests.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import XCTest
@testable import G6SensorCore

class CommandQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEnqueueAppendsDistinctCommands() {
        var queue = CommandQueue()
        queue.enqueue(.startSensor(at: now, sensorCode: .none))
        queue.enqueue(.calibrateSensor(toMgDL: 120, at: now))

        XCTAssertEqual(queue.commands.count, 2)
    }

    func testEnqueueSupersedesSameKind() {
        var queue = CommandQueue()
        queue.enqueue(.startSensor(at: now, sensorCode: .none))
        queue.enqueue(.startSensor(at: now, sensorCode: .none))
        queue.enqueue(.calibrateSensor(toMgDL: 100, at: now))
        queue.enqueue(.calibrateSensor(toMgDL: 140, at: now))

        XCTAssertEqual(queue.commands.count, 2)
        guard case let .calibrateSensor(value, _) = queue.commands[1] else {
            return XCTFail("expected calibration")
        }
        XCTAssertEqual(value, 140)
    }

    func testEnqueueReturnsSupersededCount() {
        var queue = CommandQueue()
        queue.enqueue(.calibrateSensor(toMgDL: 100, at: now))
        queue.enqueue(.calibrateSensor(toMgDL: 110, at: now))
        // The 110 enqueue already superseded the 100 one, so a single queued
        // calibration remains for the 120 to replace.
        let superseded = queue.enqueue(.calibrateSensor(toMgDL: 120, at: now))
        XCTAssertEqual(superseded, 1)
        XCTAssertEqual(queue.commands.count, 1)
    }

    func testDequeueDropsStaleCalibrations() {
        var queue = CommandQueue()
        // 6 minutes old at dequeue time: beyond the 5-minute window.
        queue.enqueue(.calibrateSensor(toMgDL: 120, at: now.addingTimeInterval(-360)))
        queue.enqueue(.stopSensor(at: now))

        let (next, dropped) = queue.dequeue(now: now)

        XCTAssertEqual(dropped.count, 1)
        guard case .stopSensor? = next else {
            return XCTFail("expected stopSensor, got \(String(describing: next))")
        }
        XCTAssertTrue(queue.isEmpty)
    }

    func testDequeueKeepsFreshCalibration() {
        var queue = CommandQueue()
        queue.enqueue(.calibrateSensor(toMgDL: 120, at: now.addingTimeInterval(-60)))

        let (next, dropped) = queue.dequeue(now: now)

        XCTAssertTrue(dropped.isEmpty)
        guard case .calibrateSensor? = next else {
            return XCTFail("expected calibration, got \(String(describing: next))")
        }
    }

    func testDequeueEmptyReturnsNil() {
        var queue = CommandQueue()
        let (next, dropped) = queue.dequeue(now: now)
        XCTAssertNil(next)
        XCTAssertTrue(dropped.isEmpty)
    }

    func testRawValuesRoundTrip() {
        var queue = CommandQueue()
        queue.enqueue(.startSensor(at: now, sensorCode: SensorCode("5931") ?? .none))
        queue.enqueue(.calibrateSensor(toMgDL: 123.4, at: now))
        queue.enqueue(.resetTransmitter)

        let restored = CommandQueue(rawValues: queue.rawValues)
        XCTAssertEqual(restored, queue)
    }

    func testRawValuesDropMalformedEntries() {
        let queue = CommandQueue(rawValues: [["action": 99], [:]])
        XCTAssertTrue(queue.isEmpty)
    }
}
