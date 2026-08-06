//
//  BatteryStatusRxMessage.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Byte layout is a protocol fact (opcode 0x23): status, two battery
//  voltages, resistance, runtime and temperature, CRC-terminated. Short
//  (10-byte) frames from older firmware omit runtime and temperature.
//

import Foundation

public struct BatteryStatusRxMessage: TransmitterRxMessage {
    public let status: UInt8

    /// Battery A voltage in hundredths of a volt (e.g. 316 = 3.16 V)
    public let voltageA: UInt16

    /// Battery B voltage in hundredths of a volt
    public let voltageB: UInt16

    /// Internal resistance; scale unconfirmed
    public let resist: UInt16

    /// Runtime in days; nil when the firmware doesn't report it
    public let runtime: Int?

    /// Temperature in °C; nil when the firmware doesn't report it
    public let temperature: Int?

    public init?(data: Data) {
        guard data.count >= 10,
            data.isCRCValid,
            data.starts(with: .batteryStatusRx)
        else {
            return nil
        }

        status = data[1]
        voltageA = data[2..<4].toInt()
        voltageB = data[4..<6].toInt()
        resist = data[6..<8].toInt()

        if data.count >= 12 {
            runtime = Int(data[8])
            temperature = Int(data[9])
        } else {
            runtime = nil
            temperature = nil
        }
    }
}
