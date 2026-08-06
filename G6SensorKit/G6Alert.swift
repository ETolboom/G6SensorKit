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

enum G6Alert: String, CaseIterable {
    case sensorExpiringSoon
    case sensorExpiringImminently
    case sensorExpired
    case sensorFailed
    case signalLoss
    case calibrationNeeded
    case transmitterExpiringSoon
    case transmitterExpired

    init?(rawValue: Alert.AlertIdentifier) {
        guard let match = Self.allCases.first(where: { $0.rawValue == rawValue }) else {
            return nil
        }
        self = match
    }

    var identifier: Alert.AlertIdentifier {
        return rawValue
    }

    var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .sensorExpiringSoon, .transmitterExpiringSoon:
            return .active
        case .sensorExpiringImminently, .sensorExpired, .signalLoss, .calibrationNeeded, .transmitterExpired:
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
        }
    }

    func alert(managerIdentifier: String) -> Alert {
        let content = Alert.Content(
            title: title,
            body: body,
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
