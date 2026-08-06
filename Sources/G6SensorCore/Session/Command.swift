//
//  Command.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit, created by Paul Dickens on 22/03/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved. (MIT License)
//
//  Adaptations: HealthKit-free (glucose as Double mg/dL); session start
//  carries an optional factory sensor code.
//

import Foundation


public enum Command: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    case startSensor(at: Date, sensorCode: SensorCode)
    case stopSensor(at: Date)
    case calibrateSensor(toMgDL: Double, at: Date)
    case resetTransmitter

    public init?(rawValue: RawValue) {
        guard let action = rawValue["action"] as? Action.RawValue else {
            return nil
        }

        let date = rawValue["date"] as? Date

        switch Action(rawValue: action) {
        case .startSensor?:
            guard let date = date else {
                return nil
            }
            let sensorCode = SensorCode(rawValue["sensorCode"] as? String) ?? .none
            self = .startSensor(at: date, sensorCode: sensorCode)
        case .stopSensor?:
            guard let date = date else {
                return nil
            }
            self = .stopSensor(at: date)
        case .calibrateSensor?:
            guard let date = date, let glucoseMgDL = rawValue["glucoseMgDL"] as? Double else {
                return nil
            }
            self = .calibrateSensor(toMgDL: glucoseMgDL, at: date)
        case .resetTransmitter?:
            self = .resetTransmitter
        case .none:
            return nil
        }
    }

    public enum Action: Int {
        case startSensor, stopSensor, calibrateSensor, resetTransmitter
    }

    public var rawValue: RawValue {
        switch self {
        case .startSensor(let date, let sensorCode):
            return [
                "action": Action.startSensor.rawValue,
                "date": date,
                "sensorCode": sensorCode.code
            ]
        case .stopSensor(let date):
            return [
                "action": Action.stopSensor.rawValue,
                "date": date
            ]
        case .calibrateSensor(let glucoseMgDL, let date):
            return [
                "action": Action.calibrateSensor.rawValue,
                "date": date,
                "glucoseMgDL": glucoseMgDL
            ]
        case .resetTransmitter:
            return [
                "action": Action.resetTransmitter.rawValue
            ]
        }
    }
}

extension Command {
    /// Whether `newer` replaces this command outright. Only one pending
    /// session start, stop or calibration is ever meaningful — the most
    /// recent one the user asked for.
    public func supersededBy(_ newer: Command) -> Bool {
        switch (self, newer) {
        case (.startSensor, .startSensor),
             (.stopSensor, .stopSensor),
             (.calibrateSensor, .calibrateSensor),
             (.resetTransmitter, .resetTransmitter):
            return true
        default:
            return false
        }
    }
}
