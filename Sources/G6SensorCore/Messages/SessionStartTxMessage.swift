//
//  SessionStartTxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//
//  Adapted for G6SensorKit: optionally carries the two factory-calibration
//  parameters derived from the 4-digit sensor code. The parameter bytes are
//  appended only when present — a code-less start keeps the original,
//  shorter frame (protocol fact; firmware rejects zero-valued parameters).
//

import Foundation


struct SessionStartTxMessage: RespondableMessage {
    typealias Response = SessionStartRxMessage

    /// Time since activation in Dex seconds
    let startTime: UInt32

    /// Time in seconds since Unix Epoch
    let secondsSince1970: UInt32

    /// Factory calibration parameters from the sensor code, when it carries any.
    let sensorCode: SensorCode

    init(startTime: UInt32, secondsSince1970: UInt32, sensorCode: SensorCode = .none) {
        self.startTime = startTime
        self.secondsSince1970 = secondsSince1970
        self.sensorCode = sensorCode
    }

    var data: Data {
        var data = Data(for: .sessionStartTx)
        data.append(startTime)
        data.append(secondsSince1970)
        if sensorCode.carriesParameters {
            data.append(UInt16(bitPattern: sensorCode.parameter1))
            data.append(UInt16(bitPattern: sensorCode.parameter2))
        }
        return data.appendingCRC()
    }
}
