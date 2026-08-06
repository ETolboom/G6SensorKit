//
//  BatteryStatusTxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct BatteryStatusTxMessage: RespondableMessage {
    typealias Response = BatteryStatusRxMessage

    var data: Data {
        return Data(for: .batteryStatusTx).appendingCRC()
    }

    // Response: 23003c012f01cd021f247bae
}
