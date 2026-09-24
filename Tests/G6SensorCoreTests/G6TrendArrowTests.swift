//
//  G6TrendArrowTests.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import XCTest
@testable import G6SensorCore

/// Rates are integer tenths on the wire, so every case here is reachable.
class G6TrendArrowTests: XCTestCase {
    func testNoRateHasNoArrow() {
        XCTAssertNil(G6TrendArrow(dexcomRateMgDLPerMinute: nil))
    }

    func testArrowsByRate() {
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -4), .downDownDown)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -2.5), .downDown)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -1.5), .down)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 0), .flat)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 1.5), .up)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 2.5), .upUp)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 4), .upUpUp)
    }

    /// Every threshold belongs to the steeper arrow, on both sides.
    /// The old `..<(-3)` bucketing gave a single-down arrow at exactly -3.0.
    func testThresholdsTakeTheSteeperArrow() {
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -3), .downDownDown)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 3), .upUpUp)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -2), .downDown)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 2), .upUp)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -1), .down)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 1), .up)
    }

    /// Flat excludes both of its ends, so it is the narrowest bucket.
    func testFlatIsOnlyBetweenTheUnitThresholds() {
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -0.9), .flat)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 0.9), .flat)
    }

    /// Past +/-8 the official apps show no arrow rather than a triple one.
    /// The wire carries Int8 tenths, so this reaches roughly +/-12.6.
    func testImplausibleRatesHaveNoArrow() {
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: -8), .downDownDown)
        XCTAssertEqual(G6TrendArrow(dexcomRateMgDLPerMinute: 8), .upUpUp)
        XCTAssertNil(G6TrendArrow(dexcomRateMgDLPerMinute: -8.1))
        XCTAssertNil(G6TrendArrow(dexcomRateMgDLPerMinute: 8.1))
        XCTAssertNil(G6TrendArrow(dexcomRateMgDLPerMinute: 12.6))
    }
}
