//
//  G6TrendArrow.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import Foundation

/// The Dexcom trend arrow for a reported rate of change.
///
/// The raw values match LoopKit's `GlucoseTrend` so the integration layer
/// can bridge with `GlucoseTrend(rawValue:)`.
public enum G6TrendArrow: Int, CaseIterable {
    case upUpUp = 1
    case upUp = 2
    case up = 3
    case flat = 4
    case down = 5
    case downDown = 6
    case downDownDown = 7

    /// Beyond this the official apps show no arrow at all. Reachable: the
    /// rate arrives as Int8 tenths (0x7F is the "no trend" sentinel), so
    /// roughly -12.8 to +12.6 comes in over the wire.
    private static let dexcomArrowLimit = 8.0

    /// The Dexcom arrow for the rate the transmitter reported, in
    /// (mg/dL)/min.
    ///
    /// Thresholds match the apps' shared trend-arrow table: every threshold
    /// belongs to the steeper arrow, `flat` excludes both of its ends, and
    /// |rate| above 8 is no arrow. The transmitter sends the rate; the
    /// receiver only buckets it.
    public init?(dexcomRateMgDLPerMinute rate: Double?) {
        guard let rate = rate,
              (-Self.dexcomArrowLimit ... Self.dexcomArrowLimit).contains(rate)
        else { return nil }

        switch rate {
        case ...(-3): self = .downDownDown
        case ...(-2): self = .downDown
        case ...(-1): self = .down
        case ..<1: self = .flat
        case ..<2: self = .up
        case ..<3: self = .upUp
        default: self = .upUpUp
        }
    }
}
