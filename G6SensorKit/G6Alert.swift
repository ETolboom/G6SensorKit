//
//  G6Alert.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Sensor lifecycle alerts issued through LoopKit's alert pipeline.
//  Interruption levels follow LibreLoop's reasoning: advance notice is
//  informational, imminent expiry and failures are time-sensitive, and a
//  failed sensor that stops all data is critical.
//
//  NOTE: alert delivery is the host's responsibility. Loop routes these
//  through AlertManager; Trio routes them through TrioAlertManager on the
//  dev branch. Trio's older main branch discarded plugin alerts silently.
//

import Foundation
import LoopKit
import G6SensorCore

enum G6Alert: String, CaseIterable {
    case sensorExpiringSoon
    case sensorExpiringImminently
    case sensorExpired
    case sensorFailed
    case signalLoss
    case calibrationNeeded
    case transmitterExpiringSoon
    case transmitterExpired
    case transmitterBatteryLow
    case transmitterBatteryVeryLow
    case lastSessionForTransmitter
    case commandDelayed
    case commandFailed

    init?(rawValue: Alert.AlertIdentifier) {
        guard let match = Self.allCases.first(where: { $0.rawValue == rawValue }) else {
            return nil
        }
        self = match
    }

    var identifier: Alert.AlertIdentifier {
        return rawValue
    }

    /// Replacement reminders are things to act on in your own time; alerts are
    /// things that have already stopped, or are about to stop, your readings.
    var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .sensorExpiringSoon,
             .transmitterExpiringSoon,
             .transmitterBatteryLow,
             .lastSessionForTransmitter:
            return .active
        case .sensorExpiringImminently,
             .sensorExpired,
             .signalLoss,
             .calibrationNeeded,
             .transmitterExpired,
             .transmitterBatteryVeryLow,
             .commandDelayed,
             .commandFailed:
            return .timeSensitive
        case .sensorFailed:
            return .critical
        }
    }

    var title: String {
        switch self {
        case .sensorExpiringSoon:
            return LocalizedString("Sensor expires in 24 hours", comment: "Alert title for sensor expiring in a day")
        case .sensorExpiringImminently:
            return LocalizedString("Sensor expires in 2 hours", comment: "Alert title for sensor expiring soon")
        case .sensorExpired:
            return LocalizedString("Sensor session ended", comment: "Alert title for expired sensor")
        case .sensorFailed:
            return LocalizedString("Sensor failed", comment: "Alert title for failed sensor")
        case .signalLoss:
            return LocalizedString("No sensor readings", comment: "Alert title for signal loss")
        case .calibrationNeeded:
            return LocalizedString("Calibration needed", comment: "Alert title for calibration request")
        case .transmitterExpiringSoon:
            return LocalizedString("Transmitter expiring soon", comment: "Alert title for a transmitter nearing end of life")
        case .transmitterExpired:
            return LocalizedString("Transmitter expired", comment: "Alert title for an expired transmitter")
        case .transmitterBatteryLow:
            return LocalizedString("Transmitter battery getting low", comment: "Alert title for a low transmitter battery")
        case .transmitterBatteryVeryLow:
            return LocalizedString("Transmitter battery very low", comment: "Alert title for a very low transmitter battery")
        case .lastSessionForTransmitter:
            return LocalizedString("Last session for this transmitter", comment: "Alert title when a transmitter cannot fit another full session")
        case .commandDelayed:
            return LocalizedString("Transmitter not responding", comment: "Alert title when a queued command has waited several connection cycles")
        case .commandFailed:
            return LocalizedString("Request not sent", comment: "Alert title when a command failed to send or expired unsent")
        }
    }

    var body: String {
        switch self {
        case .sensorExpiringSoon:
            return LocalizedString("Your sensor session ends in about 24 hours. Plan to have a new sensor ready.", comment: "Alert body for sensor expiring in a day")
        case .sensorExpiringImminently:
            return LocalizedString("Your sensor session ends in about 2 hours. Change your sensor soon to avoid a gap in readings.", comment: "Alert body for sensor expiring soon")
        case .sensorExpired:
            return LocalizedString("Your sensor session has ended and no new readings will arrive. Start a new sensor when you are ready.", comment: "Alert body for expired sensor")
        case .sensorFailed:
            return LocalizedString("Your sensor stopped working and is not sending readings. Remove it and start a new sensor. Check your glucose with a fingerstick meter in the meantime.", comment: "Alert body for failed sensor")
        case .signalLoss:
            return LocalizedString("No readings have arrived for 20 minutes. Keep your phone near your transmitter. If this continues, check your glucose with a fingerstick meter.", comment: "Alert body for signal loss")
        case .calibrationNeeded:
            return LocalizedString("Your transmitter is asking for a fingerstick calibration to keep readings accurate.", comment: "Alert body for calibration request")
        case .transmitterExpiringSoon:
            return LocalizedString("Your transmitter reaches the end of its life soon. Once it does, your current sensor keeps running but you will not be able to start a new one. Order a replacement now.", comment: "Alert body for a transmitter nearing end of life")
        case .transmitterExpired:
            return LocalizedString("Your transmitter has reached the end of its life. It cannot start a new sensor session. You need a new transmitter to keep using this app for glucose readings.", comment: "Alert body for an expired transmitter")
        case .transmitterBatteryLow:
            return LocalizedString("Your transmitter's battery is getting low. It should finish the sensor you are wearing, but order a replacement transmitter now so you are not caught out.", comment: "Alert body for a low transmitter battery")
        case .transmitterBatteryVeryLow:
            return LocalizedString("Your transmitter's battery is very low and it may stop sending readings at any time, even mid-session. Replace the transmitter as soon as you can, and check your glucose with a fingerstick meter if readings stop.", comment: "Alert body for a very low transmitter battery")
        case .lastSessionForTransmitter:
            return LocalizedString("Your transmitter does not have enough life left for another full sensor session after this one. Have a replacement transmitter ready before this sensor ends.", comment: "Alert body when a transmitter cannot fit another full session")
        case .commandDelayed:
            return LocalizedString("A request is still waiting for your transmitter. It is sent as soon as the transmitter connects. Keep your phone close to the transmitter; if its battery is low, it may not connect.", comment: "Alert body when a queued command has waited several connection cycles")
        case .commandFailed:
            return LocalizedString("A request could not be sent to your transmitter and will not be retried. Open the CGM settings and try again.", comment: "Alert body when a command failed to send")
        }
    }

    /// The body, naming the command when the alert is about one. What the
    /// user needs to do differs: a stop or start leaves the session in the
    /// wrong state, a lost calibration needs a fresh fingerstick.
    func body(delayed: Command?, undelivered: UndeliveredCommand?) -> String {
        switch self {
        case .commandDelayed:
            switch delayed {
            case .stopSensor?:
                return LocalizedString("Your sensor session has not stopped yet: the request is still waiting for your transmitter and is sent as soon as it connects. Keep your phone close to the transmitter; if its battery is low, it may not connect.", comment: "Alert body when a session stop has waited several connection cycles")
            case .startSensor?:
                return LocalizedString("Your new sensor session has not started yet: the request is still waiting for your transmitter and is sent as soon as it connects. Keep your phone close to the transmitter; if its battery is low, it may not connect.", comment: "Alert body when a session start has waited several connection cycles")
            default:
                return body
            }
        case .commandFailed:
            guard let undelivered = undelivered else {
                return body
            }
            switch undelivered.entry.command {
            case .stopSensor:
                return LocalizedString("Your sensor session was not stopped: the request could not be sent to your transmitter and will not be retried. Open the CGM settings and stop the session again, with your phone close to the transmitter.", comment: "Alert body when a session stop failed to send")
            case .startSensor:
                return LocalizedString("Your new sensor session was not started: the request could not be sent to your transmitter and will not be retried. Open the CGM settings and start the sensor again, with your phone close to the transmitter.", comment: "Alert body when a session start failed to send")
            case .calibrateSensor:
                return LocalizedString("Your calibration was not applied: it could not be sent to your transmitter in time and will not be retried. If you still want to calibrate, take a new fingerstick and enter it.", comment: "Alert body when a calibration failed to send or expired unsent")
            case .resetTransmitter:
                return body
            }
        default:
            return body
        }
    }

    func alert(managerIdentifier: String, delayed: Command? = nil, undelivered: UndeliveredCommand? = nil) -> Alert {
        let content = Alert.Content(
            title: title,
            body: body(delayed: delayed, undelivered: undelivered),
            acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Alert acknowledgment button label")
        )

        return Alert(
            identifier: Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: identifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: interruptionLevel
        )
    }
}
