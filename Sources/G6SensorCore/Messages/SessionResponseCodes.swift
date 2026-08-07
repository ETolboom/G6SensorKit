//
//  SessionResponseCodes.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Response codes the transmitter returns for session commands. These are
//  protocol facts, observable on the wire. The G6 protocol was reverse
//  engineered over years by several people — Nathan Racklyeft and Pete
//  Schwamb first, then others; xDrip4iOS and xDrip+ are where the codes are
//  written down, not where they were worked out.
//
//  They were previously discarded: a rejected session start logged
//  "Command completed" exactly like an accepted one, so the app showed
//  "No Sensor" with no indication that the transmitter had refused.
//

import Foundation

public enum SessionStartResponse: UInt8 {
    case sessionStarted = 0x01
    case sessionAlreadyInProgress = 0x02
    /// The start time was too far in the past for the transmitter to accept.
    case staleStartCommand = 0x03
    case error = 0x04
    case transmitterEndOfLife = 0x05
    case autoCalibrationSessionInProgress = 0x06

    public var isAccepted: Bool {
        switch self {
        case .sessionStarted, .sessionAlreadyInProgress, .autoCalibrationSessionInProgress:
            return true
        case .staleStartCommand, .error, .transmitterEndOfLife:
            return false
        }
    }
}

public enum SessionStopResponse: UInt8 {
    case stopped = 0x01
    case noSessionInProgress = 0x02
    case staleStopCommand = 0x03

    public var isAccepted: Bool {
        return self == .stopped
    }
}
