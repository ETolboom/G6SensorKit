//
//  G6AlertEvaluator.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Decides which lifecycle alerts should currently be raised, and issues or
//  retracts them through LoopKit's alert pipeline.
//
//  G6Alert existed for some time with nothing calling it: the cases and copy
//  were defined, acknowledgements were handled, and no alert was ever
//  raised. This is the missing half.
//
//  Alert delivery is the host's responsibility. Loop routes these through
//  AlertManager; Trio routes them through TrioAlertManager on its dev
//  branch. Trio's older main branch discarded plugin alerts silently, so on
//  those builds none of this reaches the user.
//

import Foundation
import LoopKit
import G6SensorCore

extension G6CGMManager {

    /// A transmitter is called out this far ahead of its reported end of
    /// life, which is enough notice to order a replacement.
    static let transmitterExpiryWarning: TimeInterval = .hours(24 * 3)

    /// Sensor advance notice, matching the alert copy.
    static let sensorExpiryWarning: TimeInterval = .hours(24)
    static let sensorExpiryImminent: TimeInterval = .hours(2)

    /// Re-evaluates every lifecycle alert and raises or retracts as needed.
    /// Safe to call often — an alert already raised is not raised again.
    func evaluateAlerts() {
        var due: Set<G6Alert> = []
        let now = Date()

        // Transmitter first: once it is done, no sensor can be started, so it
        // outranks anything about the current session.
        if state.isTransmitterExpired {
            due.insert(.transmitterExpired)
        } else if let expiration = state.transmitterExpirationDate,
                  expiration.timeIntervalSince(now) <= Self.transmitterExpiryWarning {
            due.insert(.transmitterExpiringSoon)
        }

        // Battery B is the cell that fails first. Only the lower of the two
        // thresholds is raised at a time, so the milder reminder does not sit
        // alongside the urgent one saying the same thing.
        if state.isBatteryVeryLow {
            due.insert(.transmitterBatteryVeryLow)
        } else if state.isBatteryLow {
            due.insert(.transmitterBatteryLow)
        }

        // A transmitter that will expire before another full session could
        // finish is worth flagging while the user still has time to order one.
        // Only meaningful once a session is running and both dates are known;
        // it is superseded by the expiry warnings above.
        if !state.isTransmitterExpired,
           !due.contains(.transmitterExpiringSoon),
           let transmitterExpiration = state.transmitterExpirationDate,
           let sensorExpiration = state.sensorExpirationDate,
           transmitterExpiration < sensorExpiration.addingTimeInterval(state.sensorLife) {
            due.insert(.lastSessionForTransmitter)
        }

        if let reading = state.latestReading {
            if reading.calibrationState.isSensorFailed {
                due.insert(.sensorFailed)
            }
            if reading.calibrationState.needsCalibration {
                due.insert(.calibrationNeeded)
            }
        }

        if state.sensorStartDate != nil, let expiration = state.sensorExpirationDate {
            let remaining = expiration.timeIntervalSince(now)
            if remaining <= 0 {
                due.insert(.sensorExpired)
            } else if remaining <= Self.sensorExpiryImminent {
                due.insert(.sensorExpiringImminently)
            } else if remaining <= Self.sensorExpiryWarning {
                due.insert(.sensorExpiringSoon)
            }
        }

        // Signal loss only counts while a session should be producing data;
        // during warm-up, or with no sensor, silence is expected.
        if state.sensorStartDate != nil, !state.isInWarmup {
            if let last = state.latestReading?.date, now.timeIntervalSince(last) > .minutes(20) {
                due.insert(.signalLoss)
            }
        }

        reconcileAlerts(due: due)
    }

    private func reconcileAlerts(due: Set<G6Alert>) {
        let previously = raisedAlerts

        for alert in due.subtracting(previously) {
            log.default("Issuing alert: %{public}@", alert.rawValue)
            let issued = alert.alert(managerIdentifier: Self.pluginIdentifier)
            delegateForAlerts.notify { delegate in
                delegate?.issueAlert(issued)
            }
        }

        for alert in previously.subtracting(due) {
            log.default("Retracting alert: %{public}@", alert.rawValue)
            let identifier = Alert.Identifier(
                managerIdentifier: Self.pluginIdentifier,
                alertIdentifier: alert.identifier
            )
            delegateForAlerts.notify { delegate in
                delegate?.retractAlert(identifier: identifier)
            }
        }

        raisedAlerts = due
    }
}
