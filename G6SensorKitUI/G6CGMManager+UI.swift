//
//  G6CGMManager+UI.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  CGMManagerUI conformance. Setup and settings are both hosted by
//  G6UICoordinator; SwiftUI screens are wrapped in LoopKitUI's
//  DismissibleHostingController (the G7SensorKit / LibreLoop pattern).
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore
import HealthKit

extension G6CGMManager: CGMManagerUI {

    public static var onboardingImage: UIImage? {
        return UIImage(named: "g6-transmitter", in: Bundle(for: G6UICoordinator.self), compatibleWith: nil)
    }

    public var smallImage: UIImage? {
        return UIImage(named: "g6-transmitter-small", in: Bundle(for: G6UICoordinator.self), compatibleWith: nil)
    }

    public static func setupViewController(
        bluetoothProvider: BluetoothProvider,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        prefersToSkipUserInteraction: Bool
    ) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        // Always requires interaction: the transmitter ID and sensor code can
        // only come from the user.
        return .userInteractionRequired(
            G6UICoordinator(
                cgmManager: nil,
                bluetoothProvider: bluetoothProvider,
                displayGlucosePreference: displayGlucosePreference,
                colorPalette: colorPalette,
                allowDebugFeatures: allowDebugFeatures
            )
        )
    }

    public func settingsViewController(
        bluetoothProvider: BluetoothProvider,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool
    ) -> CGMManagerViewController {
        return G6UICoordinator(
            cgmManager: self,
            bluetoothProvider: bluetoothProvider,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures
        )
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        // Ordered by urgency: a failed sensor outranks warm-up, which outranks
        // a stale signal.
        if let reading = state.latestReading, reading.calibrationState.isSensorFailed {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Sensor Failed", comment: "Status highlight for failed sensor"),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        // An expired transmitter cannot start a sensor at all, so saying
        // "No Sensor" points at the wrong thing entirely — the user would go
        // looking for a sensor problem that does not exist.
        // Warm-up first: a session in progress is the more useful fact, and an
        // expired transmitter can still run the session it already has.
        if let raw = state.algorithmStateRawValue, CalibrationState(rawValue: raw).isInWarmup {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Sensor Warmup", comment: "Status highlight during warm-up"),
                imageName: "clock.fill",
                state: .normalCGM
            )
        }

        if state.isTransmitterExpired, !state.hasActiveSession {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Transmitter Expired", comment: "Status highlight when the transmitter is past end of life"),
                imageName: "hourglass.bottomhalf.filled",
                state: .critical
            )
        }

        if !state.hasActiveSession {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("No Sensor", comment: "Status highlight when no session is running"),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        if let expiration = state.sensorExpirationDate, expiration < Date() {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Sensor Expired", comment: "Status highlight for expired sensor"),
                imageName: "clock.fill",
                state: .critical
            )
        }

        if state.isInWarmup {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Sensor Warmup", comment: "Status highlight during warm-up"),
                imageName: "clock.fill",
                state: .normalCGM
            )
        }

        if let reading = state.latestReading, reading.calibrationState.needsCalibration {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Calibration Needed", comment: "Status highlight when a calibration is requested"),
                imageName: "drop.fill",
                state: .normalCGM
            )
        }

        if isSignalLost {
            return G6StatusHighlight(
                localizedMessage: LocalizedString("Signal Loss", comment: "Status highlight for signal loss"),
                imageName: "antenna.radiowaves.left.and.right.slash",
                state: .critical
            )
        }

        return nil
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        // During warm-up, show progress toward first readings; afterwards,
        // progress through the session.
        if state.isInWarmup, let start = state.sensorStartDate {
            let elapsed = Date().timeIntervalSince(start)
            return G6LifecycleProgress(
                percentComplete: min(max(elapsed / state.warmupPeriod, 0), 1),
                progressState: .normalCGM
            )
        }

        guard let start = state.sensorStartDate, let expiration = state.sensorExpirationDate else {
            return nil
        }

        let total = expiration.timeIntervalSince(start)
        guard total > 0 else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = expiration.timeIntervalSince(Date())

        let progressState: DeviceLifecycleProgressState
        if remaining <= 0 {
            progressState = .critical
        } else if remaining <= .hours(24) {
            progressState = .warning
        } else {
            progressState = .normalCGM
        }

        return G6LifecycleProgress(
            percentComplete: min(max(elapsed / total, 0), 1),
            progressState: progressState
        )
    }

    public var cgmStatusBadge: DeviceStatusBadge? {
        if let reading = state.latestReading, reading.calibrationState.needsCalibration {
            return G6StatusBadge(image: UIImage(systemName: "drop.fill"), state: .warning)
        }
        return nil
    }

    private var isSignalLost: Bool {
        guard let date = state.latestReading?.date else {
            return state.sensorStartDate != nil && !state.isInWarmup
        }
        return Date().timeIntervalSince(date) > .minutes(20)
    }
}


struct G6StatusHighlight: DeviceStatusHighlight {
    var localizedMessage: String
    var imageName: String
    var state: DeviceStatusHighlightState
}

struct G6LifecycleProgress: DeviceLifecycleProgress {
    var percentComplete: Double
    var progressState: DeviceLifecycleProgressState
}

struct G6StatusBadge: DeviceStatusBadge {
    var image: UIImage?
    var state: DeviceStatusBadgeState
}
