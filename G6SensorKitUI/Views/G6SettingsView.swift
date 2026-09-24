//
//  G6SettingsView.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Layout follows the shape used by EversenseKit and LibreLoop: a hero header
//  with the device and its live state, a session progress bar, a compact
//  metadata grid, then grouped actions and detail navigation.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore

final class G6SettingsViewModel: ObservableObject, G6CGMManagerObserver {

    private let cgmManager: G6CGMManager

    let toCalibration: () -> Void
    let toTransmitterDetails: () -> Void
    let toBatteryDetails: () -> Void
    let toSensorLifeSettings: () -> Void
    let toShareUpload: () -> Void
    let toReadingDetail: () -> Void
    let toPlacementGuide: () -> Void
    let didRequestDeletion: () -> Void
    let didFinish: () -> Void

    @Published private(set) var state: G6CGMManagerState

    init(
        cgmManager: G6CGMManager,
        toCalibration: @escaping () -> Void,
        toTransmitterDetails: @escaping () -> Void,
        toBatteryDetails: @escaping () -> Void,
        toSensorLifeSettings: @escaping () -> Void,
        toShareUpload: @escaping () -> Void,
        toReadingDetail: @escaping () -> Void,
        toPlacementGuide: @escaping () -> Void,
        didRequestDeletion: @escaping () -> Void,
        didFinish: @escaping () -> Void
    ) {
        self.cgmManager = cgmManager
        state = cgmManager.state
        self.toCalibration = toCalibration
        self.toTransmitterDetails = toTransmitterDetails
        self.toBatteryDetails = toBatteryDetails
        self.toSensorLifeSettings = toSensorLifeSettings
        self.toShareUpload = toShareUpload
        self.toReadingDetail = toReadingDetail
        self.toPlacementGuide = toPlacementGuide
        self.didRequestDeletion = didRequestDeletion
        self.didFinish = didFinish

        cgmManager.addStateObserver(self)
    }

    func g6CGMManagerDidUpdateState(_ manager: G6CGMManager) {
        DispatchQueue.main.async {
            self.state = manager.state
        }
    }

    // MARK: - Derived presentation

    var phase: G6SessionPhase {
        if let reading = state.latestReading, reading.calibrationState.isSensorFailed {
            return .failed
        }
        // Warm-up reported by the transmitter counts even when no start time
        // has come through yet — the session is real, we just cannot date it.
        if let raw = state.algorithmStateRawValue, CalibrationState(rawValue: raw).isInWarmup {
            return .warmup
        }
        // Only meaningful when nothing is running: an expired transmitter
        // cannot start a sensor, but it can certainly still run one.
        if state.isTransmitterExpired, !state.hasActiveSession {
            return .transmitterExpired
        }
        guard state.hasActiveSession else {
            return .noSession
        }
        if state.isInWarmup {
            return .warmup
        }
        if let expiration = state.sensorExpirationDate {
            if expiration <= Date() {
                return .expired
            }
            if expiration.timeIntervalSinceNow <= .hours(24) {
                return .expiringSoon
            }
        }
        if isSignalLost {
            return .signalLoss
        }
        return .active
    }

    var isSignalLost: Bool {
        guard let date = state.latestReading?.date else {
            return state.sensorStartDate != nil && !state.isInWarmup
        }
        return Date().timeIntervalSince(date) > .minutes(20)
    }

    /// Warm-up shows warm-up progress; otherwise progress through the session.
    var progressFraction: Double {
        if state.isInWarmup, let start = state.sensorStartDate {
            return min(max(Date().timeIntervalSince(start) / state.warmupPeriod, 0), 1)
        }
        guard let start = state.sensorStartDate, let expiration = state.sensorExpirationDate else {
            return 0
        }
        let total = expiration.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(start) / total, 0), 1)
    }

    /// Right-hand detail on the lifecycle bar; the phase name carries the
    /// meaning, so this is just the time.
    var progressDetail: String {
        if state.hasSessionWithUnknownStart {
            return LocalizedString("Start time unknown", comment: "Detail when a session is running but its start is unknown")
        }
        if state.isInWarmup, let end = state.warmupEndDate {
            return String(
                format: LocalizedString("%@ until ready", comment: "Warm-up remaining (1: duration)"),
                Self.durationText(end.timeIntervalSinceNow)
            )
        }
        guard let expiration = state.sensorExpirationDate else {
            return ""
        }
        let remaining = expiration.timeIntervalSinceNow
        if remaining <= 0 {
            return LocalizedString("Replace sensor", comment: "Detail when the session is over")
        }
        return String(
            format: LocalizedString("%@ remaining", comment: "Session remaining (1: duration)"),
            Self.durationText(remaining)
        )
    }

    var glucoseText: String? {
        guard let reading = state.latestReading, !isSignalLost, !state.isInWarmup else {
            return nil
        }
        return "\(Int(reading.glucoseMgDL))"
    }

    var trendSymbol: String? {
        guard !isSignalLost,
              let arrow = G6TrendArrow(dexcomRateMgDLPerMinute: state.latestReading?.trendRateMgDLPerMinute)
        else {
            return nil
        }
        switch arrow {
        case .downDownDown, .downDown: return "arrow.down"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        case .up, .upUp: return "arrow.up.right"
        case .upUpUp: return "arrow.up"
        }
    }

    var lastReadingText: String {
        guard let date = state.latestReading?.date else {
            return LocalizedString("—", comment: "Placeholder for missing value")
        }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 {
            return LocalizedString("Just now", comment: "Reading received less than a minute ago")
        }
        return String(format: LocalizedString("%d min ago", comment: "Minutes since last reading (1: minutes)"), minutes)
    }

    var canCalibrate: Bool {
        state.sensorStartDate != nil && !state.isInWarmup
    }

    /// Headline battery level for the settings row; nil until the first
    /// battery read, so the row stays hidden for transmitters we have
    /// never heard battery from.
    var batteryLevelText: String? {
        switch state.batteryLevel {
        case .unknown:
            return nil
        case .high:
            return LocalizedString("High", comment: "Battery level: high")
        case .low:
            return LocalizedString("Low", comment: "Battery level: low")
        case .veryLow:
            return LocalizedString("Replace Now", comment: "Battery level: very low, replace transmitter")
        }
    }

    var canStartSensor: Bool {
        state.sensorStartDate == nil
    }

    /// A queued start has not reached the transmitter yet. It only goes out
    /// on the next connection, which can be five minutes away, and without
    /// this the screen looked identical to having done nothing at all.
    var isSessionStartPending: Bool {
        state.pendingCommands.contains { raw in
            guard let command = Command(rawValue: raw) else { return false }
            if case .startSensor = command { return true }
            return false
        }
    }

    func stopSensor() {
        cgmManager.enqueue(.stopSensor(at: Date()))
    }

    /// Current and previous log files. The manager's state is written out
    /// first so the export carries the configuration alongside the traffic.
    func logFilesForExport() -> [URL] {
        cgmManager.logStateSnapshot()
        return G6Logger.shared.debugLogURLs()
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return String(format: LocalizedString("%dd %dh", comment: "Duration in days and hours"), days, hours)
        }
        if hours > 0 {
            return String(format: LocalizedString("%dh %dm", comment: "Duration in hours and minutes"), hours, minutes)
        }
        return String(format: LocalizedString("%dm", comment: "Duration in minutes"), minutes)
    }
}

struct G6SettingsView: View {

    @ObservedObject var viewModel: G6SettingsViewModel

    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    @State private var showingStopConfirmation = false
    @State private var showingLogShare = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            sensorImageHeader
            sensorSection
            lastReadingSection
            metadataSection
            actionsSection
            detailsSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationBarItems(trailing: Button(LocalizedString("Done", comment: "Settings done button"), action: viewModel.didFinish))
    }

    // MARK: - Header

    /// Image alone on a clear row, as LibreLoop presents its sensor.
    private var sensorImageHeader: some View {
        Section {
            HStack {
                Spacer()
                G6TransmitterImage(
                    size: 200,
                    isActive: viewModel.phase == .active,
                    assetName: viewModel.state.isAnubis ? "anubis" : "G6Transmitter"
                )
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var sensorSection: some View {
        Section {
            G6LifecycleBar(
                phase: viewModel.phase,
                fraction: viewModel.progressFraction,
                detail: viewModel.progressDetail
            )
            .padding(.vertical, 4)

            if viewModel.isSessionStartPending {
                Label {
                    Text(LocalizedString("Sensor start queued — it is sent the next time the transmitter connects, which can take up to 5 minutes.", comment: "Shown while a session start is waiting for the next connection"))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    ProgressView()
                }
            }

            // Only meaningful when nothing is running. A stored failure can
            // outlive the situation that produced it — it is persisted, so it
            // survives relaunches and rebuilds — and a warning about not being
            // able to start a sensor is plainly wrong next to a session that
            // is warming up.
            if !viewModel.state.hasActiveSession, let failure = viewModel.state.lastSessionStartFailure {
                Label {
                    Text(failure)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(LocalizedString("Sensor", comment: "Settings section: sensor"))
        }
    }

    private var lastReadingSection: some View {
        Section(LocalizedString("Last Reading", comment: "Settings section: last reading")) {
            if let reading = viewModel.state.latestReading, !viewModel.state.isInWarmup {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayGlucosePreference.format(
                        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: reading.glucoseMgDL),
                        includeUnit: false))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(viewModel.isSignalLost ? .secondary : .primary)
                    Text(displayGlucosePreference.unit.localizedShortUnitString)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let symbol = viewModel.trendSymbol {
                        Image(systemName: symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(reading.date, style: .relative)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let rate = reading.trendRateMgDLPerMinute {
                        Text(String(format: LocalizedString("%1$@%2$@/min", comment: "Trend rate (1: sign, 2: formatted rate with unit)"),
                                    rate > 0 ? "+" : "",
                                    displayGlucosePreference.formatMinuteRate(
                                        HKQuantity(unit: HKUnit.milligramsPerDeciliter.unitDivided(by: .minute()), doubleValue: rate),
                                        includeUnit: false)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.footnote)

                if reading.isDisplayOnly {
                    Label(LocalizedString("Display only", comment: "Reading is display-only, not used for dosing"),
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.phase == .failed {
                Text(LocalizedString("No readings — replace the sensor.", comment: "Placeholder when the sensor has failed"))
                    .foregroundStyle(.secondary)
            } else if viewModel.phase == .warmup {
                Text(LocalizedString("Warming up — readings start soon.", comment: "Placeholder during warm-up"))
                    .foregroundStyle(.secondary)
            } else {
                Text(LocalizedString("Waiting for first reading…", comment: "Placeholder before the first reading"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      spacing: 14) {
                metaCell(
                    LocalizedString("Sensor started", comment: "Metadata label for sensor start"),
                    viewModel.state.sensorStartDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
                )
                metaCell(
                    LocalizedString("Session ends", comment: "Metadata label for session end"),
                    viewModel.state.sensorExpirationDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
                )
                metaCell(
                    LocalizedString("Transmitter", comment: "Metadata label for transmitter ID"),
                    viewModel.state.transmitterID
                )
                metaCell(
                    LocalizedString("Sensor code", comment: "Metadata label for sensor code"),
                    viewModel.state.sensorCode
                        ?? (viewModel.state.hasActiveSession
                            ? LocalizedString("Not used", comment: "Value when a session runs without a sensor code")
                            : nil)
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func metaCell(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? LocalizedString("—", comment: "Placeholder for missing value"))
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            if viewModel.canStartSensor {
                Button {
                    viewModel.toPlacementGuide()
                } label: {
                    Label(LocalizedString("Start New Sensor", comment: "Button to begin a new sensor session"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(G6RowButtonStyle())
                .disabled(viewModel.state.isTransmitterExpired)
            } else {
                Button {
                    viewModel.toCalibration()
                } label: {
                    HStack {
                        Label(LocalizedString("Enter Calibration", comment: "Button to enter a calibration"), systemImage: "drop.fill")
                        if !viewModel.canCalibrate {
                            Spacer()
                            Text(viewModel.state.isInWarmup
                                 ? LocalizedString("After warm-up", comment: "Why calibration is unavailable during warm-up")
                                 : LocalizedString("No sensor", comment: "Why calibration is unavailable without a session"))
                                .font(.footnote)
                        }
                    }
                }
                .buttonStyle(G6RowButtonStyle())
                .disabled(!viewModel.canCalibrate)

                Button(role: .destructive) {
                    showingStopConfirmation = true
                } label: {
                    Label(LocalizedString("Stop Sensor Session", comment: "Button to stop the sensor session"), systemImage: "stop.circle")
                }
                .confirmationDialog(
                    LocalizedString("Stop this sensor session?", comment: "Confirmation title for stopping a session"),
                    isPresented: $showingStopConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedString("Stop Session", comment: "Confirm stop session"), role: .destructive, action: viewModel.stopSensor)
                } message: {
                    Text(LocalizedString("You will stop getting readings until you start a new sensor. A stopped session cannot be restarted.", comment: "Confirmation message for stopping a session"))
                }
            }
        } footer: {
            if viewModel.state.isInWarmup {
                Text(LocalizedString("Calibration becomes available once warm-up finishes. Do not make insulin decisions from early readings — use a fingerstick meter and follow your care team's guidance.", comment: "Footer explaining warm-up restrictions"))
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section {
            if viewModel.state.latestReading != nil {
                navRow(LocalizedString("Latest Reading", comment: "Row to the latest reading detail"), "drop.circle", viewModel.toReadingDetail)
            }

            navRow(LocalizedString("Transmitter Details", comment: "Row to transmitter details"), "cpu", viewModel.toTransmitterDetails)

            if let batteryLevel = viewModel.batteryLevelText {
                Button(action: viewModel.toBatteryDetails) {
                    HStack {
                        Label(LocalizedString("Battery", comment: "Row to transmitter battery details"), systemImage: "battery.75")
                        Spacer()
                        Text(batteryLevel)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(G6RowButtonStyle())
            }

            if viewModel.state.isAnubis {
                navRow(LocalizedString("Session Length", comment: "Row to session length settings"), "calendar", viewModel.toSensorLifeSettings)
            }

            navRow(LocalizedString("Dexcom Share Upload", comment: "Row to Share upload settings"), "icloud.and.arrow.up", viewModel.toShareUpload)
            navRow(LocalizedString("How to Apply a Sensor", comment: "Row to the placement guide"), "questionmark.circle", viewModel.toPlacementGuide)

            Button {
                showingLogShare = true
            } label: {
                Label(LocalizedString("Share Logs", comment: "Row to export the log files"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(G6RowButtonStyle())
            .sheet(isPresented: $showingLogShare) {
                G6ActivityViewController(activityItems: viewModel.logFilesForExport())
            }
        }
    }

    private func navRow(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        // A plain .foregroundStyle(.primary) here would override the system's
        // disabled dimming; the style defers to the environment instead.
        .buttonStyle(G6RowButtonStyle())
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text(LocalizedString("Remove CGM from App", comment: "Button to delete the CGM manager"))
                    .frame(maxWidth: .infinity)
            }
            .confirmationDialog(
                LocalizedString("Remove this CGM?", comment: "Confirmation title for removing the CGM"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(LocalizedString("Remove CGM", comment: "Confirm CGM removal"), role: .destructive, action: viewModel.didRequestDeletion)
            } message: {
                Text(LocalizedString("This app will stop reading from your transmitter. Your sensor session keeps running on the transmitter itself.", comment: "Confirmation message for removing the CGM"))
            }
        } footer: {
            Text(LocalizedString("“Dexcom”, “G6”, and “ONE” are trademarks of Dexcom, Inc., used here only to describe which devices are compatible. This app is not made by or endorsed by Dexcom.", comment: "Trademark attribution footer"))
                .font(.footnote)
        }
    }
}
