//
//  Calibration.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit, created by Paul Dickens on 17/03/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved. (MIT License)
//
//  Adaptation: HealthKit-free — glucose as Double mg/dL.
//

import Foundation

public struct Calibration {
    init?(calibrationMessage: CalibrationDataRxMessage, activationDate: Date) {
        guard calibrationMessage.glucose > 0 else {
            return nil
        }

        glucoseMgDL = Double(calibrationMessage.glucose)
        date = activationDate.addingTimeInterval(TimeInterval(calibrationMessage.timestamp))
    }

    public let glucoseMgDL: Double
    public let date: Date
}
