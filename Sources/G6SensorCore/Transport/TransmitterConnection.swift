//
//  TransmitterConnection.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (BluetoothManager.swift),
//  originally xDripG5, created by Nathan Racklyeft on 10/1/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved. (MIT License)
//
//  This is a close port of CGMBLEKit's connection policy rather than a
//  reimplementation. An earlier version here invented a "connect-pending"
//  scheme that re-armed in the same callback as the disconnect, so it
//  reconnected before iOS had torn the link down: the peripheral came back
//  with an invalidated service cache ("Configured peripheral has no
//  services") and the transmitter was hammered every few seconds. Nate's
//  sequence is kept as written, including the settle delay before scanning
//  again — that pause is load-bearing, not incidental.
//
//  One deliberate deviation: discovery falls back to the advertised local name
//  when `CBPeripheral.name` is nil, and the peripheral identifier is surfaced
//  so the integration layer can persist it — CGMBLEKit accepts one at init but
//  never stores it, so it rediscovers from scratch every launch.
//
//  The central is owned by this instance, as CGMBLEKit does it.
//
//  There is no passive mode. This connection owns the transmitter; it never
//  observes another app's session.
//

import CoreBluetooth
import Foundation
import os.log


protocol TransmitterConnectionDelegate: AnyObject {

    /// Tells the delegate the connection finished connecting to and discovering
    /// all required services of its peripheral, or that it failed to do so.
    func transmitterConnection(_ connection: TransmitterConnection, peripheralManager: PeripheralManager, isReadyWithError error: Error?)

    /// Asks the delegate whether the discovered or restored peripheral should
    /// be connected. `advertisementData` is passed because `peripheral.name`
    /// is nil until iOS has connected to the device at least once.
    func transmitterConnection(_ connection: TransmitterConnection, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool

    /// Informs the delegate that the known peripheral identifier changed and should be persisted.
    func transmitterConnection(_ connection: TransmitterConnection, didUpdatePeripheralIdentifier identifier: UUID?)

    /// New data on the backfill characteristic. Backfill arrives as
    /// notifications rather than as a command response, so it comes through
    /// here rather than the peripheral manager's condition machinery.
    func transmitterConnection(_ connection: TransmitterConnection, didReceiveBackfillResponse response: Data)
}


class TransmitterConnection: NSObject {

    /// Whether to keep re-establishing the link. Cleared before teardown so
    /// the reconnect loop stops.
    var stayConnected: Bool {
        get {
            return lockedStayConnected.value
        }
        set {
            lockedStayConnected.value = newValue
        }
    }
    private let lockedStayConnected: Locked<Bool> = Locked(true)

    weak var delegate: TransmitterConnectionDelegate?

    private let log = OSLog(category: "TransmitterConnection")

    private var manager: CBCentralManager! = nil

    /// Isolated to `managerQueue`
    private var peripheral: CBPeripheral? {
        get {
            return peripheralManager?.peripheral
        }
        set {
            guard let peripheral = newValue else {
                peripheralManager = nil
                return
            }

            if let peripheralManager = peripheralManager {
                peripheralManager.peripheral = peripheral
            } else {
                peripheralManager = PeripheralManager(
                    peripheral: peripheral,
                    configuration: .dexcomG6,
                    centralManager: manager
                )
            }
        }
    }

    var peripheralIdentifier: UUID? {
        get {
            return lockedPeripheralIdentifier.value
        }
        set {
            lockedPeripheralIdentifier.value = newValue
        }
    }
    private let lockedPeripheralIdentifier: Locked<UUID?> = Locked(nil)

    /// Isolated to `managerQueue`
    private var peripheralManager: PeripheralManager? {
        didSet {
            oldValue?.delegate = nil
            peripheralManager?.delegate = self

            let identifier = peripheralManager?.peripheral.identifier
            if identifier != peripheralIdentifier {
                peripheralIdentifier = identifier
                delegate?.transmitterConnection(self, didUpdatePeripheralIdentifier: identifier)
            }
        }
    }

    // MARK: - Synchronization

    private let managerQueue = DispatchQueue(label: "org.nightscout.G6SensorKit.bluetoothManagerQueue", qos: .unspecified)

    init(peripheralIdentifier: UUID? = nil) {
        super.init()

        self.peripheralIdentifier = peripheralIdentifier

        managerQueue.sync {
            self.manager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "org.nightscout.G6SensorKit"]
            )
        }
    }

    // MARK: - Actions

    func scanForPeripheral() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        managerQueue.sync {
            self.managerQueue_scanForPeripheral()
        }
    }

    func disconnect() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        managerQueue.sync {
            if manager.isScanning {
                manager.stopScan()
            }

            if let peripheral = peripheral {
                manager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func managerQueue_scanForPeripheral() {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        guard manager.state == .poweredOn else {
            log.default("Not scanning; central state is %{public}@", String(describing: manager.state.rawValue))
            return
        }

        let currentState = peripheral?.state ?? .disconnected
        guard currentState != .connected else {
            return
        }

        if let peripheralID = peripheralIdentifier, let peripheral = manager.retrievePeripherals(withIdentifiers: [peripheralID]).first {
            log.debug("Re-connecting to known peripheral %{public}@", peripheral.identifier.uuidString)
            self.peripheral = peripheral
            self.manager.connect(peripheral)
        } else if let peripheral = manager.retrieveConnectedPeripherals(withServices: [
                TransmitterServiceUUID.advertisement.cbUUID,
                TransmitterServiceUUID.cgmService.cbUUID
            ]).first,
            delegate == nil || delegate!.transmitterConnection(self, shouldConnectPeripheral: peripheral, advertisementData: [:])
        {
            log.debug("Found system-connected peripheral: %{public}@", peripheral.identifier.uuidString)
            self.peripheral = peripheral
            self.manager.connect(peripheral)
        } else {
            log.debug("Scanning for peripherals")
            manager.scanForPeripherals(withServices: [
                    TransmitterServiceUUID.advertisement.cbUUID
                ],
                options: nil
            )
        }
    }

    /// Persistent connections don't seem to work with the transmitter
    /// shutoff: the OS won't re-wake the app unless it's scanning. The sleep
    /// gives the transmitter time to shut down, but keeps the app running.
    fileprivate func scanAfterDelay() {
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(forTimeInterval: 2)

            self.scanForPeripheral()
        }
    }

    // MARK: - Accessors

    var isScanning: Bool {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        var isScanning = false
        managerQueue.sync {
            isScanning = manager.isScanning
        }
        return isScanning
    }

    override var debugDescription: String {
        return [
            "## TransmitterConnection",
            "peripheralIdentifier: \(peripheralIdentifier?.uuidString ?? "nil")",
            "stayConnected: \(stayConnected)",
            peripheralManager.map(String.init(reflecting:)) ?? "No peripheral",
        ].joined(separator: "\n")
    }
}


extension TransmitterConnection: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        peripheralManager?.centralManagerDidUpdateState(central)
        log.default("%{public}@: %{public}@", #function, String(describing: central.state.rawValue))

        switch central.state {
        case .poweredOn:
            managerQueue_scanForPeripheral()
        case .resetting, .poweredOff, .unauthorized, .unknown, .unsupported:
            fallthrough
        @unknown default:
            if central.isScanning {
                central.stopScan()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                if delegate == nil || delegate!.transmitterConnection(self, shouldConnectPeripheral: peripheral, advertisementData: [:]) {
                    log.default("Restoring peripheral from state: %{public}@", peripheral.identifier.uuidString)
                    self.peripheral = peripheral
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "nil"
        log.default("Discovered peripheral name=%{public}@ advertised=%{public}@ rssi=%{public}@",
                    peripheral.name ?? "nil", advertisedName, RSSI)

        if delegate == nil || delegate!.transmitterConnection(self, shouldConnectPeripheral: peripheral, advertisementData: advertisementData) {
            self.peripheral = peripheral

            central.connect(peripheral, options: nil)

            central.stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.default("%{public}@: %{public}@", #function, peripheral)
        if central.isScanning {
            central.stopScan()
        }

        peripheralManager?.centralManager(central, didConnect: peripheral)

        if case .poweredOn = manager.state, case .connected = peripheral.state, let peripheralManager = peripheralManager {
            self.delegate?.transmitterConnection(self, peripheralManager: peripheralManager, isReadyWithError: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.default("%{public}@: %{public}@", #function, peripheral)
        // Ignore errors indicating the peripheral disconnected remotely, as that's expected behavior
        if let error = error as NSError?, CBError(_nsError: error).code != .peripheralDisconnected {
            log.error("%{public}@: %{public}@", #function, error)
            if let peripheralManager = peripheralManager {
                self.delegate?.transmitterConnection(self, peripheralManager: peripheralManager, isReadyWithError: error)
            }
        }

        if stayConnected {
            scanAfterDelay()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.error("%{public}@: %{public}@", #function, String(describing: error))
        if let error = error, let peripheralManager = peripheralManager {
            self.delegate?.transmitterConnection(self, peripheralManager: peripheralManager, isReadyWithError: error)
        }

        if stayConnected {
            scanAfterDelay()
        }
    }
}


extension TransmitterConnection: PeripheralManagerDelegate {
    func peripheralManager(_ manager: PeripheralManager, didReadRSSI RSSI: NSNumber, error: Error?) {

    }

    func peripheralManagerDidUpdateName(_ manager: PeripheralManager) {

    }

    func completeConfiguration(for manager: PeripheralManager) throws {

    }

    func peripheralManager(_ manager: PeripheralManager, didUpdateValueFor characteristic: CBCharacteristic) {
        // Control and authentication responses are consumed by the peripheral
        // manager's condition machinery as part of the active command flow.
        // Only backfill arrives unsolicited.
        guard let value = characteristic.value,
              case .backfill? = CGMServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString.uppercased())
        else {
            return
        }

        delegate?.transmitterConnection(self, didReceiveBackfillResponse: value)
    }
}
