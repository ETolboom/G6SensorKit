//
//  G6SharedCentral.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  One process-wide CBCentralManager, shared by every TransmitterConnection.
//
//  A central created with a restoration identifier is retained by the system
//  for the lifetime of the app. Creating a second one with the same
//  identifier is API misuse: the new central never reaches .poweredOn, so
//  scanning never starts and setup sits on "Looking for your transmitter…"
//  forever. That is exactly what removing a CGM and adding it again in one
//  app session used to do, because each manager built its own central.
//
//  LibreLoop hit and documented the same trap; the fix is the same one.
//

import CoreBluetooth
import Foundation
import os.log

final class G6SharedCentral: NSObject {

    static let shared = G6SharedCentral()

    static let restoreIdentifier = "org.nightscout.G6SensorKit.central"

    /// All CoreBluetooth work happens here; the central is created with this
    /// queue and delegate callbacks arrive on it.
    let queue = DispatchQueue(label: "org.nightscout.G6SensorKit.bluetoothQueue", qos: .userInitiated)

    private(set) var manager: CBCentralManager!

    /// The connection currently driving the radio. Weak, so a discarded
    /// manager cannot keep receiving callbacks or keep itself alive.
    weak var activeDelegate: CBCentralManagerDelegate?

    private let log = OSLog(category: "G6SharedCentral")

    private override init() {
        super.init()

        queue.sync {
            manager = CBCentralManager(
                delegate: self,
                queue: queue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
        }
    }

    /// Takes over the radio. The previous owner stops receiving callbacks.
    func setActiveDelegate(_ delegate: CBCentralManagerDelegate?) {
        activeDelegate = delegate

        // A delegate arriving after the central already powered on would
        // otherwise never learn its state, since didUpdateState has been and
        // gone. Replay it.
        if let delegate = delegate, manager.state == .poweredOn {
            queue.async { [weak self] in
                guard let self = self else { return }
                delegate.centralManagerDidUpdateState(self.manager)
            }
        }
    }
}

extension G6SharedCentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.default("Shared central state: %{public}@", String(describing: central.state.rawValue))
        activeDelegate?.centralManagerDidUpdateState(central)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        activeDelegate?.centralManager?(central, willRestoreState: dict)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        activeDelegate?.centralManager?(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activeDelegate?.centralManager?(central, didConnect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        activeDelegate?.centralManager?(central, didDisconnectPeripheral: peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        activeDelegate?.centralManager?(central, didFailToConnect: peripheral, error: error)
    }
}
