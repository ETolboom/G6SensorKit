//
//  Glucose.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit, originally xDripG5,
//  created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved. (MIT License)
//
//  Adaptation: the core is HealthKit-free — glucose values are plain
//  Double mg/dL; unit modeling belongs to the integration layer.
//

import Foundation

enum GlucoseLimits {
    static var minimum: UInt16 = 40
    static var maximum: UInt16 = 400
}

public struct Glucose {
    let glucoseMessage: GlucoseSubMessage
    let timeMessage: TransmitterTimeRxMessage

    init(
        transmitterID: String,
        glucoseMessage: GlucoseRxMessage,
        timeMessage: TransmitterTimeRxMessage,
        calibrationMessage: CalibrationDataRxMessage? = nil,
        activationDate: Date
    ) {
        self.init(
            transmitterID: transmitterID,
            status: glucoseMessage.status,
            glucoseMessage: glucoseMessage.glucose,
            timeMessage: timeMessage,
            calibrationMessage: calibrationMessage,
            activationDate: activationDate
        )
    }

    init(
        transmitterID: String,
        status: UInt8,
        glucoseMessage: GlucoseSubMessage,
        timeMessage: TransmitterTimeRxMessage,
        calibrationMessage: CalibrationDataRxMessage? = nil,
        activationDate: Date
    ) {
        self.transmitterID = transmitterID
        self.glucoseMessage = glucoseMessage
        self.timeMessage = timeMessage
        self.status = TransmitterStatus(rawValue: status)
        self.activationDate = activationDate

        if timeMessage.hasValidSensorSession {
            let sessionStartDate = activationDate.addingTimeInterval(TimeInterval(timeMessage.sessionStartTime))
            self.sessionStartDate = sessionStartDate
            self.sessionExpDate = sessionStartDate.addingTimeInterval(.hours(24 * Double(TransmitterManagerState.defaultSensorLifeDays)))
        } else {
            sessionStartDate = nil
            sessionExpDate = nil
        }
        readDate = activationDate.addingTimeInterval(TimeInterval(glucoseMessage.timestamp))
        lastCalibration = calibrationMessage != nil ? Calibration(calibrationMessage: calibrationMessage!, activationDate: activationDate) : nil
    }

    // MARK: - Transmitter Info
    public let transmitterID: String
    public let status: TransmitterStatus
    public let activationDate: Date
    public let sessionStartDate: Date?
    public internal(set) var sessionExpDate: Date?

    public var hasValidSensorSession: Bool {
        return sessionStartDate != nil
    }

    // MARK: - Glucose Info
    public let lastCalibration: Calibration?
    public let readDate: Date

    public var isDisplayOnly: Bool {
        return glucoseMessage.glucoseIsDisplayOnly
    }

    /// Glucose in mg/dL, clamped to 40…400; nil when the calibration state
    /// says the value is unreliable.
    public var glucoseMgDL: Double? {
        guard state.hasReliableGlucose && glucoseMessage.glucose >= 39 else {
            return nil
        }

        return Double(min(max(glucoseMessage.glucose, GlucoseLimits.minimum), GlucoseLimits.maximum))
    }

    public var state: CalibrationState {
        return CalibrationState(rawValue: glucoseMessage.state)
    }

    public var trend: Int {
        return Int(glucoseMessage.trend)
    }

    /// Rate of change in (mg/dL)/min; nil when the transmitter reports no trend.
    public var trendRateMgDLPerMinute: Double? {
        guard glucoseMessage.trend < Int8.max && glucoseMessage.trend > Int8.min else {
            return nil
        }

        return Double(glucoseMessage.trend) / 10
    }

    /// Transmitter-relative timestamp in Dex seconds. Identical for a given
    /// reading whether it arrives live or via backfill, so it is a stable
    /// de-duplication key.
    public var transmitterTimestamp: UInt32 {
        return glucoseMessage.timestamp
    }

    /// Raw algorithm/calibration state byte, for persistence.
    public var calibrationStateRawValue: UInt8 {
        return glucoseMessage.state
    }

    // An identifier for this reading thatʼs consistent between backfill/live data
    public var syncIdentifier: String {
        return "\(transmitterID) \(glucoseMessage.timestamp)"
    }
}


extension Glucose: Equatable {
    public static func ==(lhs: Glucose, rhs: Glucose) -> Bool {
        return lhs.glucoseMessage == rhs.glucoseMessage && lhs.syncIdentifier == rhs.syncIdentifier
    }
}
