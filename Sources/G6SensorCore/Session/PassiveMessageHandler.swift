//
//  PassiveMessageHandler.swift
//  G6SensorKit
//
//  Adapted for G6SensorKit from CGMBLEKit (Transmitter.swift's passive
//  control-response dispatcher), originally xDripG5, created by Nathan
//  Racklyeft on 11/22/15.
//  Copyright © 2015 Nathan Racklyeft. (MIT License)
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Adaptation: the opcode switch, time-message caching and backfill frame
//  validation follow CGMBLEKit's passive path, restructured into a pure type
//  with no CoreBluetooth so the whole decode path is unit-testable.
//

import Foundation
import os.log


/// What an observed frame turned into. Forwarded to the session delegate.
enum PassiveEvent {
    /// Another client completed the auth exchange. Informational: control
    /// subscription is not gated on this (CGMBLEKit's `dec4ff0` gating was a
    /// workaround for toggling subscriptions mid-exchange, which this design
    /// avoids by subscribing everything once at connect).
    case observedAuthentication(isAuthenticated: Bool, isBonded: Bool)

    /// A time frame was observed; carries the derived activation date.
    case transmitterTime(activationDate: Date)

    case glucose(Glucose)

    case backfill([Glucose])

    case transmitterVersion(TransmitterVersionRxMessage)

    case unknown(Data)

    case error(TransmitterError)
}


/// Stateful decoder for observed traffic. A glucose frame cannot be dated
/// until a time frame has been observed (the glucose timestamp is seconds
/// since transmitter activation), so time frames are cached; frames arriving
/// before the first one are dropped with an observation error.
final class PassiveMessageHandler {

    private let transmitterID: String

    /// Seeded from persisted state and corrected by every observed time
    /// frame. The seed alone does not let a reading through: the sensor
    /// session start only comes from a time frame, and a reading without one
    /// would look like the session ended. Frames before the first time frame
    /// are therefore still dropped.
    private(set) var activationDate: Date?

    private var lastTimeMessage: TransmitterTimeRxMessage?

    private var lastCalibration: CalibrationDataRxMessage?

    /// Frames accumulate whenever they arrive; the acknowledgement on the
    /// control characteristic is what validates and triggers decoding.
    private var backfillBuffer: GlucoseBackfillFrameBuffer?

    private let log = OSLog(category: "PassiveMessageHandler")

    init(transmitterID: String, activationDate: Date? = nil) {
        self.transmitterID = transmitterID
        self.activationDate = activationDate
    }

    // MARK: - Authentication characteristic

    func handleAuthentication(_ data: Data) -> [PassiveEvent] {
        // Only the challenge response carries anything worth reporting; the
        // rest of the auth exchange is ignored.
        guard let message = AuthChallengeRxMessage(data: data) else {
            return []
        }

        return [.observedAuthentication(isAuthenticated: message.isAuthenticated, isBonded: message.isBonded)]
    }

    // MARK: - Control characteristic

    func handleControl(_ data: Data, at date: Date = Date()) -> [PassiveEvent] {
        guard let first = data.first, let opcode = Opcode(rawValue: first) else {
            return [.unknown(data)]
        }

        switch opcode {
        case .transmitterTimeRx:
            guard let message = TransmitterTimeRxMessage(data: data) else {
                return [.unknown(data)]
            }

            lastTimeMessage = message
            let activation = date.addingTimeInterval(-TimeInterval(message.currentTime))
            activationDate = activation
            return [.transmitterTime(activationDate: activation)]

        case .glucoseRx, .glucoseG6Rx:
            guard let message = GlucoseRxMessage(data: data) else {
                return [.unknown(data)]
            }

            guard let timeMessage = lastTimeMessage, let activationDate = activationDate else {
                return [.error(.observationError(
                    "Glucose frame observed before any time frame; cannot date it, dropping"))]
            }

            let glucose = Glucose(
                transmitterID: transmitterID,
                glucoseMessage: message,
                timeMessage: timeMessage,
                calibrationMessage: lastCalibration,
                activationDate: activationDate
            )
            return [.glucose(glucose)]

        case .glucoseBackfillRx:
            guard let ack = GlucoseBackfillRxMessage(data: data) else {
                return [.unknown(data)]
            }
            return handleBackfillAcknowledgement(ack)

        case .calibrationDataRx:
            guard let message = CalibrationDataRxMessage(data: data) else {
                return [.unknown(data)]
            }
            lastCalibration = message
            return []

        case .transmitterVersionRx:
            guard let message = TransmitterVersionRxMessage(data: data) else {
                return [.unknown(data)]
            }
            return [.transmitterVersion(message)]

        default:
            return [.unknown(data)]
        }
    }

    // MARK: - Backfill characteristic

    /// Appends an observed frame to the buffer. Decoding happens when the
    /// acknowledgement arrives on the control characteristic.
    func handleBackfill(_ data: Data) {
        guard data.count > 2 else {
            return
        }

        // Byte 0 is the frame index, byte 1 the buffer identifier.
        if data[0] == 1 {
            log.default("Starting new observed backfill buffer with ID %d", data[1])
            backfillBuffer = GlucoseBackfillFrameBuffer(identifier: data[1])
        }

        backfillBuffer?.append(data)
    }

    // MARK: - Private

    private func handleBackfillAcknowledgement(_ ack: GlucoseBackfillRxMessage) -> [PassiveEvent] {
        defer { backfillBuffer = nil }

        guard let buffer = backfillBuffer, buffer.count > 0 else {
            // Nothing observed for the window: an empty result, not a failure.
            if ack.bufferLength == 0 {
                return []
            }
            return [.error(.observationError(
                "Backfill acknowledged \(ack.bufferLength) bytes but no frames were observed"))]
        }

        let complete = buffer.count == Int(ack.bufferLength)

        if complete {
            guard ack.bufferCRC == buffer.crc16 else {
                return [.error(.observationError(
                    "Backfill expected CRC \(String(format: "%04x", ack.bufferCRC)), but was \(String(format: "%04x", buffer.crc16))"))]
            }
        } else {
            // The CRC covers the whole buffer, so it cannot check a prefix.
            log.default("Observed backfill incomplete: %{public}@ of %{public}@ bytes; delivering what arrived",
                        String(buffer.count), String(ack.bufferLength))
        }

        guard let timeMessage = lastTimeMessage, let activationDate = activationDate else {
            return [.error(.observationError(
                "Backfill observed before any time frame; cannot date it, dropping"))]
        }

        let glucose = buffer.glucose.map {
            Glucose(transmitterID: transmitterID, status: ack.status, glucoseMessage: $0, timeMessage: timeMessage, activationDate: activationDate)
        }

        guard !glucose.isEmpty else {
            return []
        }

        guard glucose.first!.glucoseMessage.timestamp <= glucose.last!.glucoseMessage.timestamp else {
            return [.error(.observationError(
                "Backfill timestamps out of order: \(glucose.first!.glucoseMessage.timestamp) - \(glucose.last!.glucoseMessage.timestamp)"))]
        }

        var events: [PassiveEvent] = [.backfill(glucose)]

        if !complete {
            events.append(.error(.observationError(
                "Backfill delivered \(glucose.count) readings but was incomplete")))
        }

        return events
    }
}
