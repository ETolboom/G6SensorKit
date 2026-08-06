//
//  GlucoseG6TxMessage.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  G6-generation glucose request (opcode 0x4e; protocol fact). The response
//  arrives as opcode 0x4f, which GlucoseRxMessage already parses.
//

import Foundation


struct GlucoseG6TxMessage: RespondableMessage {
    typealias Response = GlucoseRxMessage

    var data: Data {
        return Data(for: .glucoseG6Tx).appendingCRC()
    }
}
