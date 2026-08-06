//
//  HarnessViewModel.swift
//  G6SensorHarness
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Drives a TransmitterSession directly for on-device validation of the
//  core: pairing, per-cycle reads, session start/stop with sensor codes,
//  calibration, battery, and backfill — with an in-app event log so
//  background behavior can be inspected without a debugger.
//

import Foundation
import Combine
import G6SensorCore

struct LogLine: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

final class HarnessViewModel: ObservableObject, TransmitterSessionDelegate, TransmitterCommandSource {

    @Published var transmitterID: String = UserDefaults.standard.string(forKey: "harness.transmitterID") ?? ""
    @Published var isRunning = false
    @Published var latestReading: String = "—"
    @Published var lastConnect: Date?
    @Published var log: [LogLine] = []
    @Published var pendingCommands: [Command] = []

    private var session: TransmitterSession?

    private var peripheralIdentifier: UUID? {
        get { UserDefaults.standard.string(forKey: "harness.peripheralIdentifier").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "harness.peripheralIdentifier") }
    }

    // MARK: - Controls

    func start() {
        guard transmitterID.count == 6 else {
            append("Transmitter ID must be 6 characters")
            return
        }
        guard !transmitterID.hasPrefix("4") else {
            append("IDs starting with 4 are G5-generation transmitters, which are unsupported")
            return
        }

        UserDefaults.standard.set(transmitterID, forKey: "harness.transmitterID")

        let session = TransmitterSession(id: transmitterID, peripheralIdentifier: peripheralIdentifier)
        session.delegate = self
        session.commandSource = self
        self.session = session
        session.start()
        isRunning = true
        append("Session armed for \(transmitterID); waiting for transmitter advertisement (~5 min cycle)")
    }

    func stop() {
        session?.stop()
        session = nil
        isRunning = false
        append("Session stopped")
    }

    func enqueueStartSensor(code: String?) {
        guard let sensorCode = SensorCode(code) else {
            append("Unknown sensor code")
            return
        }
        enqueue(.startSensor(at: Date(), sensorCode: sensorCode))
    }

    func enqueueStopSensor() {
        enqueue(.stopSensor(at: Date()))
    }

    func enqueueCalibration(mgDL: Double) {
        guard (40...400).contains(mgDL) else {
            append("Calibration must be 40–400 mg/dL")
            return
        }
        enqueue(.calibrateSensor(toMgDL: mgDL, at: Date()))
    }

    func requestBattery() {
        session?.shouldReadBattery = true
        append("Battery read queued for next connection")
    }

    func requestBackfill(hours: Double) {
        let end = Date()
        session?.requestedBackfillWindow = DateInterval(start: end.addingTimeInterval(-hours * 3600), end: end)
        append("Backfill queued for last \(Int(hours))h")
    }

    private func enqueue(_ command: Command) {
        DispatchQueue.main.async {
            self.pendingCommands.append(command)
            self.append("Queued: \(String(describing: command))")
        }
    }

    private func append(_ text: String) {
        DispatchQueue.main.async {
            self.log.insert(LogLine(date: Date(), text: text), at: 0)
            if self.log.count > 500 {
                self.log.removeLast(self.log.count - 500)
            }
        }
    }

    // MARK: - TransmitterSessionDelegate (background queue)

    func transmitterSessionDidConnect(_ session: TransmitterSession) {
        DispatchQueue.main.async { self.lastConnect = Date() }
        append("Connected")
    }

    func transmitterSession(_ session: TransmitterSession, didError error: Error) {
        append("Error: \(error)")
    }

    func transmitterSession(_ session: TransmitterSession, didRead glucose: Glucose) {
        let value = glucose.glucoseMgDL.map { "\(Int($0)) mg/dL" } ?? "unreliable (\(glucose.state))"
        DispatchQueue.main.async { self.latestReading = value }
        append("Glucose: \(value), state: \(glucose.state), trend: \(glucose.trend)")
    }

    func transmitterSession(_ session: TransmitterSession, didReadBackfill glucose: [Glucose]) {
        append("Backfill: \(glucose.count) readings")
    }

    func transmitterSession(_ session: TransmitterSession, didReadTransmitterVersion message: TransmitterVersionRxMessage) {
        append("Version: fw \(message.firmwareVersion.map(String.init).joined(separator: ".")), expiry \(message.transmitterExpiryInDays)d\(message.isAnubis ? " (Anubis)" : "")")
    }

    func transmitterSession(_ session: TransmitterSession, didReadBattery message: BatteryStatusRxMessage) {
        append("Battery: A \(Double(message.voltageA)/100)V, B \(Double(message.voltageB)/100)V")
    }

    func transmitterSession(_ session: TransmitterSession, didReadUnknownData data: Data) {
        append("Unknown data: \(data.map { String(format: "%02x", $0) }.joined())")
    }

    func transmitterSession(_ session: TransmitterSession, didUpdatePeripheralIdentifier identifier: UUID?) {
        DispatchQueue.main.async { self.peripheralIdentifier = identifier }
        append("Peripheral identifier: \(identifier?.uuidString ?? "nil")")
    }

    func transmitterSessionDidRequestBond(_ session: TransmitterSession) {
        append("⚠️ Accept the iOS pairing prompt within 60 seconds")
    }

    // MARK: - TransmitterCommandSource (background queue)

    func dequeuePendingCommand(for session: TransmitterSession) -> Command? {
        var command: Command?
        DispatchQueue.main.sync {
            if !pendingCommands.isEmpty {
                command = pendingCommands.removeFirst()
            }
        }
        return command
    }

    func transmitterSession(_ session: TransmitterSession, didFail command: Command, with error: Error) {
        append("Command failed: \(String(describing: command)) — \(error)")
    }

    func transmitterSession(_ session: TransmitterSession, didComplete command: Command, response: TransmitterRxMessage?) {
        append("Command completed: \(String(describing: command))")
    }
}
