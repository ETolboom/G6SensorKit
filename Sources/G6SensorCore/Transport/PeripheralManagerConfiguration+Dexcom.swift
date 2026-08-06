//
//  PeripheralManagerConfiguration+Dexcom.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (BluetoothServices.swift),
//  originally xDripG5, created by Nate Racklyeft on 10/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved. (MIT License)
//

import Foundation

extension PeripheralManager.Configuration {
    /// Dexcom G6 / ONE transmitter service layout. (Same GATT layout as G5;
    /// G5 transmitters themselves are unsupported by this package.)
    static var dexcomG6: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                TransmitterServiceUUID.cgmService.cbUUID: [
                    CGMServiceCharacteristicUUID.communication.cbUUID,
                    CGMServiceCharacteristicUUID.authentication.cbUUID,
                    CGMServiceCharacteristicUUID.control.cbUUID,
                    CGMServiceCharacteristicUUID.backfill.cbUUID,
                ]
            ],
            notifyingCharacteristics: [:],
            valueUpdateMacros: [:]
        )
    }
}
