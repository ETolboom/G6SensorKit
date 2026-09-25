//
//  PassiveTransmitterSession.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (Transmitter.swift, passive path),
//  originally xDripG5, created by Nathan Racklyeft on 11/22/15.
//  Copyright © 2015 Nathan Racklyeft. (MIT License)
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Adaptations:
//  - All three subscriptions happen once, at connect, and are never toggled.
//    CGMBLEKit subscribes to control only after observing an authenticated
//    session (commit dec4ff0) because toggling subscriptions mid-exchange
//    confused CoreBluetooth; subscribing everything up front sidesteps that
//    entirely. If field testing shows missed traffic, gate the control
//    subscription on `PassiveEvent.observedAuthentication` — the handler
//    already parses it.
//  - There is no write API in scope here at all: no auth, no bonding, no
//    commands, no active reads, no disconnect request. The link drops when
//    the driving client is done, and TransmitterConnection's reconnect loop
//    picks the transmitter up again on its next cycle.
//
//  A passive session never writes a request to the transmitter. It connects,
//  subscribes to the authentication, control and backfill characteristics
//  once, and decodes the notification traffic another client on the same
//  phone (the Dexcom app, or the transmitter's bonded session) generates.
//  iOS shares the system-level connection between apps, so the Dexcom app's
//  five-minute polling drives the exchange and this session observes it.
//
//  Because nothing here writes, passive mode cannot start or stop sessions,
//  calibrate, read battery status, or request backfill.
//

import Foundation
import CoreBluetooth
import os.log


public final class PassiveTransmitterSession: TransmitterSessioning {

    /// The ID of the transmitter to connect to
    public var ID: String {
        return id.id
    }

    private var id: TransmitterID

    public weak var delegate: TransmitterSessionDelegate?

    /// Frames are decoded on the Bluetooth queue while `retarget` swaps the
    /// handler from the caller's thread, so every access goes through here.
    private let handler: Locked<PassiveMessageHandler>

    private let log = OSLog(category: "PassiveTransmitterSession")

    private let connection: TransmitterConnection

    private let delegateQueue = DispatchQueue(label: "org.nightscout.G6SensorKit.passiveSessionDelegateQueue", qos: .unspecified)

    /// - Parameter activationDate: the persisted transmitter start date. It
    ///   seeds the decoder, but readings still wait for an observed time
    ///   frame (see `PassiveMessageHandler.activationDate`).
    public init(id: String, peripheralIdentifier: UUID? = nil, activationDate: Date? = nil) {
        self.id = TransmitterID(id: id)
        self.handler = Locked(PassiveMessageHandler(transmitterID: id, activationDate: activationDate))
        self.connection = TransmitterConnection(peripheralIdentifier: peripheralIdentifier)

        connection.delegate = self
    }

    /// Starts (or resumes) looking for the transmitter. Idempotent.
    public func start() {
        connection.stayConnected = true
        connection.scanForPeripheral()
    }

    /// Stops the reconnect loop and drops any live connection.
    public func stop() {
        connection.stayConnected = false
        connection.disconnect()
    }

    /// Points this session at a different transmitter, keeping the existing
    /// connection and its central manager.
    public func retarget(id newID: String) {
        log.default("Retargeting session to transmitter %{public}@", newID)

        connection.stayConnected = false
        connection.disconnect()

        self.id = TransmitterID(id: newID)
        handler.value = PassiveMessageHandler(transmitterID: newID)
        connection.peripheralIdentifier = nil

        start()
    }

    public var peripheralIdentifier: UUID? {
        get {
            return connection.peripheralIdentifier
        }
        set {
            connection.peripheralIdentifier = newValue
        }
    }

    // MARK: - Event forwarding

    private func forward(_ events: [PassiveEvent]) {
        guard !events.isEmpty else {
            return
        }

        delegateQueue.async {
            for event in events {
                switch event {
                case .observedAuthentication(let isAuthenticated, let isBonded):
                    self.log.default("Observed authentication exchange (authenticated: %{public}@, bonded: %{public}@)",
                                     String(describing: isAuthenticated), String(describing: isBonded))
                case .transmitterTime(let activationDate):
                    self.delegate?.transmitterSession(self, didReadTransmitterTime: activationDate)
                case .glucose(let glucose):
                    self.delegate?.transmitterSession(self, didRead: glucose)
                case .backfill(let glucose):
                    self.delegate?.transmitterSession(self, didReadBackfill: glucose)
                case .transmitterVersion(let message):
                    self.delegate?.transmitterSession(self, didReadTransmitterVersion: message)
                case .unknown(let data):
                    self.delegate?.transmitterSession(self, didReadUnknownData: data)
                case .error(let error):
                    // A frame this session could not use — seen before a time
                    // frame, or a partial backfill — says nothing about the
                    // link, which the other client is still driving. Reporting
                    // it as a session error would flip the UI to searching
                    // and raise CGM errors in the host while all is well.
                    self.log.error("Observation: %{public}@", String(describing: error))
                }
            }
        }
    }
}


extension PassiveTransmitterSession: TransmitterConnectionDelegate {

    func transmitterConnection(_ connection: TransmitterConnection, peripheralManager: PeripheralManager, isReadyWithError error: Error?) {
        if let error = error {
            delegateQueue.async {
                self.delegate?.transmitterSession(self, didError: error)
            }
            return
        }

        delegateQueue.async {
            self.delegate?.transmitterSessionDidConnect(self)
        }

        peripheralManager.perform { (peripheral) in
            do {
                // The whole setup: subscribe and get out of the way. No
                // writes, and crucially no disconnect — the link belongs to
                // the client driving the exchange.
                try peripheral.listenToCharacteristic(.authentication)
                try peripheral.listenToCharacteristic(.control)
                try peripheral.listenToCharacteristic(.backfill)
                self.log.default("Listening for another client's session traffic")
            } catch let error {
                self.delegateQueue.async {
                    self.delegate?.transmitterSession(self, didError: error)
                }
            }
        }
    }

    func transmitterConnection(_ connection: TransmitterConnection, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // G6/ONE transmitters advertise a name of "DexcomXX", where "XX" is
        // the last two characters of the transmitter ID. Unlike the active
        // session there is no auth handshake to reject a wrong transmitter,
        // so this name match is the only identity check.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let expected = id.id.suffix(2).uppercased()

        if let name = advertisedName ?? peripheral.name {
            let matches = name.suffix(2).uppercased() == expected
            if matches {
                log.default("Matched transmitter %{public}@", name)
            } else {
                log.info("Ignoring peripheral %{public}@ (expected suffix %{public}@)", name, String(expected))
            }
            return matches
        }

        // No name from either source. The scan is already filtered to the
        // Dexcom advertisement service, and a system-connected peripheral on
        // the user's own phone is virtually always their transmitter, so
        // attempt the connection rather than stranding setup.
        log.default("Peripheral advertised no name; attempting connection anyway (passive mode has no auth check)")
        return true
    }

    func transmitterConnection(_ connection: TransmitterConnection, didUpdatePeripheralIdentifier identifier: UUID?) {
        delegateQueue.async {
            self.delegate?.transmitterSession(self, didUpdatePeripheralIdentifier: identifier)
        }
    }

    func transmitterConnection(_ connection: TransmitterConnection, didReceiveAuthenticationResponse response: Data) {
        var events: [PassiveEvent] = []
        handler.mutate { events = $0.handleAuthentication(response) }
        forward(events)
    }

    func transmitterConnection(_ connection: TransmitterConnection, didReceiveControlResponse response: Data) {
        var events: [PassiveEvent] = []
        handler.mutate { events = $0.handleControl(response) }
        forward(events)
    }

    func transmitterConnection(_ connection: TransmitterConnection, didReceiveBackfillResponse response: Data) {
        handler.mutate { $0.handleBackfill(response) }
    }
}


extension PassiveTransmitterSession: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## PassiveTransmitterSession",
            String(reflecting: connection),
        ].joined(separator: "\n")
    }
}
