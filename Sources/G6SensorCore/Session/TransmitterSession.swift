//
//  TransmitterSession.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (Transmitter.swift),
//  originally xDripG5, created by Nathan Racklyeft on 11/22/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved. (MIT License)
//
//  Adaptations (behavioral reference: xDrip4iOS — no code copied):
//  - Active/native mode ONLY: the passive "observe another app's session"
//    path is removed by design. G6SensorKit owns the transmitter.
//  - Per-connection flow follows the Firefly ordering: authenticate →
//    bond if needed → subscribe control + backfill → time → pending
//    commands (session stop / session start / calibrate / reset) →
//    battery (when requested) → glucose → transmitter version (when
//    requested) → backfill (when requested) → disconnect.
//  - Backfill is actively requested for a caller-supplied window and
//    validated against the acknowledgement's length/CRC before delivery.
//  - Pairing keep-alive window is 60 s, giving the user time to accept
//    the iOS pairing prompt.
//

import Foundation
import CoreBluetooth
import os.log


public protocol TransmitterSessionDelegate: AnyObject {
    func transmitterSessionDidConnect(_ session: TransmitterSession)

    func transmitterSession(_ session: TransmitterSession, didError error: Error)

    func transmitterSession(_ session: TransmitterSession, didRead glucose: Glucose)

    func transmitterSession(_ session: TransmitterSession, didReadBackfill glucose: [Glucose])

    func transmitterSession(_ session: TransmitterSession, didReadTransmitterVersion message: TransmitterVersionRxMessage)

    func transmitterSession(_ session: TransmitterSession, didReadBattery message: BatteryStatusRxMessage)

    /// The transmitter's clock was read, which means authentication
    /// succeeded. Reported separately from glucose because a stopped or
    /// failed sensor produces no usable reading, and the app still needs to
    /// know it is talking to the transmitter.
    func transmitterSession(_ session: TransmitterSession, didReadTransmitterTime activationDate: Date)

    func transmitterSession(_ session: TransmitterSession, didReadUnknownData data: Data)

    /// The known peripheral identifier changed; persist it.
    func transmitterSession(_ session: TransmitterSession, didUpdatePeripheralIdentifier identifier: UUID?)

    /// A bond request was sent; the user must accept the iOS pairing prompt
    /// within the keep-alive window (~60 s).
    func transmitterSessionDidRequestBond(_ session: TransmitterSession)
}

/// These methods are called on a private background queue. It is the responsibility of the client to ensure thread-safety.
public protocol TransmitterCommandSource: AnyObject {
    func dequeuePendingCommand(for session: TransmitterSession) -> Command?

    func transmitterSession(_ session: TransmitterSession, didFail command: Command, with error: Error)

    func transmitterSession(_ session: TransmitterSession, didComplete command: Command, response: TransmitterRxMessage?)
}

public enum TransmitterError: Error {
    case authenticationError(String)
    case controlError(String)
    case observationError(String)
}

extension TransmitterError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authenticationError(let description):
            return description
        case .controlError(let description):
            return description
        case .observationError(let description):
            return description
        }
    }
}


public final class TransmitterSession: TransmitterConnectionDelegate {

    /// Seconds the transmitter is asked to keep the link alive while the user
    /// responds to the iOS pairing prompt.
    static let pairingKeepAliveSeconds: UInt8 = 60

    /// How long to wait for the authentication reply.
    ///
    /// CGMBLEKit's per-command default is two seconds. Field logs show the
    /// transmitter holding the connection open for fifteen and answering
    /// after more than two under load, so the exchange was being abandoned
    /// while the reply was still in flight — reported as a protocol failure
    /// when it was only impatience. Ten seconds sits inside the window the
    /// transmitter actually offers, leaving room for the rest of the flow.
    static let authTimeout: TimeInterval = 10

    /// The ID of the transmitter to connect to
    public var ID: String {
        return id.id
    }

    private var id: TransmitterID

    public weak var delegate: TransmitterSessionDelegate?

    public weak var commandSource: TransmitterCommandSource?

    /// When set, the next connection cycle reads the transmitter version
    /// (firmware + reported expiry, i.e. Anubis detection).
    public var shouldReadTransmitterVersion: Bool {
        get { lockedShouldReadVersion.value }
        set { lockedShouldReadVersion.value = newValue }
    }
    private let lockedShouldReadVersion: Locked<Bool> = Locked(true)

    /// When set, the next connection cycle reads battery status.
    public var shouldReadBattery: Bool {
        get { lockedShouldReadBattery.value }
        set { lockedShouldReadBattery.value = newValue }
    }
    private let lockedShouldReadBattery: Locked<Bool> = Locked(false)

    /// When set, the next connection cycle requests backfill for the window.
    /// Cleared after a successful backfill delivery.
    public var requestedBackfillWindow: DateInterval? {
        get { lockedBackfillWindow.value }
        set { lockedBackfillWindow.value = newValue }
    }
    private let lockedBackfillWindow: Locked<DateInterval?> = Locked(nil)

    /// The backfill data buffer; confined to the connection's manager queue.
    private var backfillBuffer: GlucoseBackfillFrameBuffer?

    private let log = OSLog(category: "TransmitterSession")

    private let connection: TransmitterConnection

    private let delegateQueue = DispatchQueue(label: "org.nightscout.G6SensorKit.sessionDelegateQueue", qos: .unspecified)

    public init(id: String, peripheralIdentifier: UUID? = nil) {
        self.id = TransmitterID(id: id)
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

    public var peripheralIdentifier: UUID? {
        get {
            return connection.peripheralIdentifier
        }
        set {
            connection.peripheralIdentifier = newValue
        }
    }

    // MARK: - TransmitterConnectionDelegate

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
                // The transmitter answers the authentication exchange with
                // indications on the auth characteristic, not with read
                // responses. Notifications must therefore be enabled before
                // the request is written, or readMessage's readValue returns
                // nothing and the exchange times out. This mirrors xDrip's
                // sequence (subscribe, wait for the notification state to
                // apply, then send AuthRequestTx).
                self.log.debug("Subscribing to authentication characteristic")
                try peripheral.setNotifyValue(true, for: .authentication, timeout: Self.authTimeout)

                self.log.debug("Authenticating with transmitter")
                let started = Date()
                let status = try peripheral.authenticate(id: self.id)
                self.log.default("Authenticated in %{public}@s (bonded: %{public}@)",
                                 String(format: "%.1f", Date().timeIntervalSince(started)),
                                 String(describing: status.isBonded))

                if !status.isBonded {
                    self.log.debug("Requesting bond")
                    try peripheral.requestBond(keepAliveSeconds: Self.pairingKeepAliveSeconds)

                    self.log.debug("Bonding request sent. Waiting for user to respond.")
                    self.delegateQueue.async {
                        self.delegate?.transmitterSessionDidRequestBond(self)
                    }
                }

                try peripheral.enableNotify(shouldWaitForBond: !status.isBonded)
                defer {
                    self.log.debug("Initiating a disconnect")
                    peripheral.disconnect()
                }

                // Subscribe to backfill before any request that could produce
                // backfill traffic.
                try peripheral.listenToCharacteristic(.backfill)

                self.log.debug("Reading time")
                let timeMessage = try peripheral.readTimeMessage()

                let activationDate = Date(timeIntervalSinceNow: -TimeInterval(timeMessage.currentTime))
                self.log.debug("Determined activation date: %@", String(describing: activationDate))

                self.delegateQueue.async {
                    self.delegate?.transmitterSession(self, didReadTransmitterTime: activationDate)
                }

                while let command = self.commandSource?.dequeuePendingCommand(for: self) {
                    self.log.debug("Sending command: %@", String(describing: command))
                    do {
                        let response = try peripheral.sendCommand(command, activationDate: activationDate)

                        if let start = response as? SessionStartRxMessage {
                            // Logged for diagnosis, but not treated as a
                            // verdict. A transmitter activated two minutes
                            // earlier answered with the code xDrip labels
                            // "end of life" and then went straight into
                            // warm-up, so the session had in fact started.
                            // Whether a session is running is decided from
                            // the transmitter's own state, not from here.
                            self.log.default("Session start response: status=%{public}@ received=%{public}@ (%{public}@)",
                                             String(describing: start.status),
                                             String(describing: start.received),
                                             String(describing: SessionStartResponse(rawValue: start.received)))
                        } else if let stop = response as? SessionStopRxMessage {
                            self.log.default("Session stop response: status=%{public}@", String(describing: stop.status))
                        } else if response is CalibrateGlucoseRxMessage {
                            self.log.default("Calibration accepted by transmitter")
                        }

                        self.commandSource?.transmitterSession(self, didComplete: command, response: response)
                    } catch let error {
                        self.commandSource?.transmitterSession(self, didFail: command, with: error)
                    }
                }

                if self.shouldReadBattery {
                    self.log.debug("Reading battery status")
                    if let batteryMessage = try? peripheral.readBatteryStatus() {
                        self.shouldReadBattery = false
                        self.delegateQueue.async {
                            self.delegate?.transmitterSession(self, didReadBattery: batteryMessage)
                        }
                    }
                }

                self.log.debug("Reading glucose")
                let glucoseMessage = try peripheral.readGlucose()

                self.log.debug("Reading calibration data")
                let calibrationMessage = try? peripheral.readCalibrationData()

                if self.shouldReadTransmitterVersion {
                    // Best-effort: surfaces firmware + transmitter-reported
                    // expiry (Anubis detection) without failing the cycle.
                    self.log.debug("Reading transmitter version")
                    if let versionMessage = try? peripheral.readTransmitterVersion() {
                        self.shouldReadTransmitterVersion = false
                        self.log.default("Transmitter firmware %{public}@, reported lifetime %{public}@ days",
                                         versionMessage.firmwareVersion.map(String.init).joined(separator: "."),
                                         String(describing: versionMessage.transmitterExpiryInDays))
                        self.delegateQueue.async {
                            self.delegate?.transmitterSession(self, didReadTransmitterVersion: versionMessage)
                        }
                    }
                }

                let glucose = Glucose(
                    transmitterID: self.id.id,
                    glucoseMessage: glucoseMessage,
                    timeMessage: timeMessage,
                    calibrationMessage: calibrationMessage,
                    activationDate: activationDate
                )

                self.delegateQueue.async {
                    self.delegate?.transmitterSession(self, didRead: glucose)
                }

                if let window = self.requestedBackfillWindow, glucose.state.hasReliableGlucose {
                    self.log.debug("Requesting backfill for %{public}@", String(describing: window))
                    do {
                        try self.performBackfill(window: window, on: peripheral, timeMessage: timeMessage, activationDate: activationDate)
                        self.requestedBackfillWindow = nil
                    } catch let error {
                        self.log.error("Backfill failed: %{public}@", String(describing: error))
                        self.delegateQueue.async {
                            self.delegate?.transmitterSession(self, didError: error)
                        }
                    }
                }
            } catch let error {
                self.delegateQueue.async {
                    self.delegate?.transmitterSession(self, didError: error)
                }
            }
        }
    }

    func transmitterConnection(_ connection: TransmitterConnection, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // G6/ONE transmitters advertise a name of "DexcomXX", where "XX" is
        // the last two characters of the transmitter ID.
        //
        // `peripheral.name` is nil until iOS has connected to the device at
        // least once, so on a fresh install the only identity available is
        // the advertised local name. Checking `peripheral.name` alone means
        // every discovery is rejected and the scan never terminates.
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
        // Dexcom advertisement service, so this is a transmitter of some
        // kind; attempt it and let the authentication handshake reject it if
        // it belongs to someone else. Refusing here would strand setup.
        log.default("Peripheral advertised no name; attempting connection and letting auth decide")
        return true
    }

    func transmitterConnection(_ connection: TransmitterConnection, didUpdatePeripheralIdentifier identifier: UUID?) {
        delegateQueue.async {
            self.delegate?.transmitterSession(self, didUpdatePeripheralIdentifier: identifier)
        }
    }


    func transmitterConnection(_ connection: TransmitterConnection, didReceiveBackfillResponse response: Data) {
        guard response.count > 2 else {
            return
        }

        if response[0] == 1 {
            log.info("Starting new backfill buffer with ID %d", response[1])

            self.backfillBuffer = GlucoseBackfillFrameBuffer(identifier: response[1])
        }

        log.info("appending to backfillBuffer: %@", response.hexadecimalString)

        self.backfillBuffer?.append(response)
    }


    // MARK: - Backfill

    /// Requests, assembles and validates a backfill for `window`, delivering
    /// the result to the delegate. Runs on the peripheral's session queue.
    private func performBackfill(window: DateInterval, on peripheral: PeripheralManager, timeMessage: TransmitterTimeRxMessage, activationDate: Date) throws {
        // Pad the window by ±5 minutes so boundary readings aren't lost.
        let padding = TimeInterval(minutes: 5)
        let startTime = UInt32(max(0, window.start.addingTimeInterval(-padding).timeIntervalSince(activationDate)))
        let endTime = UInt32(max(0, window.end.addingTimeInterval(padding).timeIntervalSince(activationDate)))

        guard endTime > startTime else {
            throw TransmitterError.controlError("Invalid backfill window \(window)")
        }

        backfillBuffer = nil

        let ack = try peripheral.requestBackfill(startTime: startTime, endTime: endTime)

        guard let backfillBuffer = backfillBuffer else {
            throw TransmitterError.observationError("Backfill acknowledged but no data frames received")
        }

        guard ack.bufferLength == backfillBuffer.count else {
            throw TransmitterError.observationError("Backfill expected buffer length \(ack.bufferLength), but was \(backfillBuffer.count)")
        }

        guard ack.bufferCRC == backfillBuffer.crc16 else {
            throw TransmitterError.observationError("Backfill expected CRC \(String(format: "%04x", ack.bufferCRC)), but was \(String(format: "%04x", backfillBuffer.crc16))")
        }

        let glucose = backfillBuffer.glucose.map {
            Glucose(transmitterID: id.id, status: ack.status, glucoseMessage: $0, timeMessage: timeMessage, activationDate: activationDate)
        }

        guard glucose.count > 0 else {
            return
        }

        guard glucose.first!.glucoseMessage.timestamp == ack.startTime,
            glucose.last!.glucoseMessage.timestamp == ack.endTime,
            glucose.first!.glucoseMessage.timestamp <= glucose.last!.glucoseMessage.timestamp
        else {
            throw TransmitterError.observationError("Backfill time interval not reflected in glucose: \(ack.startTime) - \(ack.endTime), buffer: \(glucose.first!.glucoseMessage.timestamp) - \(glucose.last!.glucoseMessage.timestamp)")
        }

        delegateQueue.async {
            self.delegate?.transmitterSession(self, didReadBackfill: glucose)
        }
    }
}

extension TransmitterSession: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## TransmitterSession",
            String(reflecting: connection),
        ].joined(separator: "\n")
    }
}


// MARK: - Helpers
fileprivate extension PeripheralManager {
    func authenticate(id: TransmitterID) throws -> AuthChallengeRxMessage {
        let authMessage = AuthRequestTxMessage()

        guard let expectedTokenHash = id.computeHash(of: authMessage.singleUseToken) else {
            throw TransmitterError.authenticationError("Failed to compute token hash for transmitter ID")
        }

        // Only accept the reply that answers this token. A value cached from
        // an earlier exchange parses as a valid response but carries the
        // previous token's hash, and would otherwise look like a rejection.
        let authResponse: AuthRequestRxMessage
        do {
            authResponse = try writeMessage(
                authMessage,
                for: .authentication,
                expecting: AuthRequestRxMessage.self,
                matching: { $0.tokenHash == expectedTokenHash },
                timeout: TransmitterSession.authTimeout
            )
        } catch let error {
            throw TransmitterError.authenticationError(
                "No reply to our auth token \(authMessage.singleUseToken.hexadecimalString) "
                + "(expected hash \(expectedTokenHash.hexadecimalString)): \(error)"
            )
        }

        guard let challengeHash = id.computeHash(of: authResponse.challenge) else {
            throw TransmitterError.authenticationError("Failed to compute challenge hash for transmitter ID")
        }

        let challengeResponse: AuthChallengeRxMessage
        do {
            challengeResponse = try writeMessage(
                AuthChallengeTxMessage(challengeHash: challengeHash),
                for: .authentication,
                expecting: AuthChallengeRxMessage.self,
                matching: { _ in true },
                timeout: TransmitterSession.authTimeout
            )
        } catch let error {
            throw TransmitterError.authenticationError("Error exchanging challenge response: \(error)")
        }

        guard challengeResponse.isAuthenticated else {
            throw TransmitterError.authenticationError(
                "Transmitter rejected the challenge (bonded: \(challengeResponse.isBonded)) — "
                + "this usually means the transmitter ID is not the one printed on this transmitter"
            )
        }

        return challengeResponse
    }

    func requestBond(keepAliveSeconds: UInt8) throws {
        do {
            try writeMessage(KeepAliveTxMessage(time: keepAliveSeconds), for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing keep-alive for bond: \(error)")
        }

        do {
            try writeMessage(BondRequestTxMessage(), for: .authentication)
        } catch let error {
            throw TransmitterError.authenticationError("Error writing bond request: \(error)")
        }
    }

    func enableNotify(shouldWaitForBond: Bool = false) throws {
        do {
            if shouldWaitForBond {
                // Cover the pairing keep-alive window so the user has time
                // to accept the iOS pairing prompt.
                try setNotifyValue(true, for: .control, timeout: TimeInterval(TransmitterSession.pairingKeepAliveSeconds))
            } else {
                try setNotifyValue(true, for: .control)
            }
        } catch let error {
            throw TransmitterError.controlError("Error enabling notification: \(error)")
        }
    }

    func readTimeMessage() throws -> TransmitterTimeRxMessage {
        do {
            return try writeMessage(TransmitterTimeTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting time: \(error)")
        }
    }

    /// - Throws: TransmitterError.controlError
    func sendCommand(_ command: Command, activationDate: Date) throws -> TransmitterRxMessage {
        do {
            switch command {
            case .startSensor(let date, let sensorCode):
                let startTime = UInt32(date.timeIntervalSince(activationDate))
                let secondsSince1970 = UInt32(date.timeIntervalSince1970)
                return try writeMessage(SessionStartTxMessage(startTime: startTime, secondsSince1970: secondsSince1970, sensorCode: sensorCode), for: .control)
            case .stopSensor(let date):
                let stopTime = UInt32(date.timeIntervalSince(activationDate))
                return try writeMessage(SessionStopTxMessage(stopTime: stopTime), for: .control)
            case .calibrateSensor(let glucoseMgDL, let date):
                let glucoseValue = UInt16(glucoseMgDL.rounded())
                let time = UInt32(date.timeIntervalSince(activationDate))
                return try writeMessage(CalibrateGlucoseTxMessage(time: time, glucose: glucoseValue), for: .control)
            case .resetTransmitter:
                return try writeMessage(ResetTxMessage(), for: .control)
            }
        } catch let error {
            throw TransmitterError.controlError("Error during \(command): \(error)")
        }
    }

    func readGlucose() throws -> GlucoseRxMessage {
        do {
            return try writeMessage(GlucoseG6TxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting glucose: \(error)")
        }
    }

    func readCalibrationData() throws -> CalibrationDataRxMessage {
        do {
            return try writeMessage(CalibrationDataTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting calibration data: \(error)")
        }
    }

    func readBatteryStatus() throws -> BatteryStatusRxMessage {
        do {
            return try writeMessage(BatteryStatusTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting battery status: \(error)")
        }
    }

    func readTransmitterVersion() throws -> TransmitterVersionRxMessage {
        do {
            return try writeMessage(TransmitterVersionTxMessage(), for: .control)
        } catch let error {
            throw TransmitterError.controlError("Error getting transmitter version: \(error)")
        }
    }

    /// The backfill stream must complete before the acknowledgement arrives
    /// on the control characteristic, so this write uses a generous timeout.
    func requestBackfill(startTime: UInt32, endTime: UInt32) throws -> GlucoseBackfillRxMessage {
        do {
            return try writeMessage(
                GlucoseBackfillTxMessage(byte1: 5, byte2: 2, identifier: 0, startTime: startTime, endTime: endTime),
                for: .control,
                timeout: 30
            )
        } catch let error {
            throw TransmitterError.controlError("Error requesting backfill: \(error)")
        }
    }

    func disconnect() {
        do {
            try setNotifyValue(false, for: .control)
            try writeMessage(DisconnectTxMessage(), for: .control)
        } catch {
        }
    }

    func listenToCharacteristic(_ characteristic: CGMServiceCharacteristicUUID) throws {
        do {
            try setNotifyValue(true, for: characteristic)
        } catch let error {
            throw TransmitterError.controlError("Error enabling notification for \(characteristic): \(error)")
        }
    }
}
