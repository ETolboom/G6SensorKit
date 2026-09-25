//
//  G6DetailViews.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Calibration entry, transmitter and battery details, Anubis session-length
//  settings, and optional Dexcom Share upload configuration.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore

// MARK: - Calibration

/// Keeps the calibration screen's "current reading" live. State updates
/// alone are not enough: they only arrive WITH a reading, so without the
/// tick a disconnected transmitter would leave an old reading looking
/// fresh forever.
final class G6CalibrationViewModel: ObservableObject, G6CGMManagerObserver {
    @Published private(set) var latestReading: G6StoredReading?
    @Published private(set) var now = Date()

    private var tick: Timer?

    init(cgmManager: G6CGMManager) {
        latestReading = cgmManager.state.latestReading
        cgmManager.addStateObserver(self)

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    deinit {
        tick?.invalidate()
    }

    func g6CGMManagerDidUpdateState(_ manager: G6CGMManager) {
        DispatchQueue.main.async {
            self.latestReading = manager.state.latestReading
        }
    }

    /// Readings arrive every 5 minutes; one missed reading closes the gate.
    /// The extra 30 seconds absorb delivery jitter so a slightly late reading
    /// does not flicker the gate.
    static let readingFreshnessInterval: TimeInterval = .minutes(5.5)

    /// Why calibration is or is not currently possible.
    enum Readiness {
        case ready
        case noFreshReading
        case notFlat
    }

    var freshReading: G6StoredReading? {
        guard let reading = latestReading,
              now.timeIntervalSince(reading.date) <= Self.readingFreshnessInterval
        else {
            return nil
        }
        return reading
    }

    /// Calibrating teaches the sensor from the difference between the
    /// fingerstick and the current reading; a reading that is moving cannot
    /// be compared fairly, so calibration requires a flat trend.
    var readiness: Readiness {
        guard let reading = freshReading else {
            return .noFreshReading
        }
        guard G6TrendArrow(dexcomRateMgDLPerMinute: reading.trendRateMgDLPerMinute) == .flat else {
            return .notFlat
        }
        return .ready
    }
}

struct G6CalibrationView: View {

    let cgmManager: G6CGMManager
    let didSubmit: () -> Void

    @StateObject private var viewModel: G6CalibrationViewModel

    @State private var entry: String = ""
    @State private var validationMessage: String?
    @State private var showingGuide = false
    @State private var showingDeviationWarning = false

    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    private static let minimumMgDL: Double = 40
    private static let maximumMgDL: Double = 400

    /// Deviation from the current reading at or beyond which the big-change
    /// warning shows (mg/dL).
    private static let largeDeviationWarningMgDL: Double = 40

    init(cgmManager: G6CGMManager, didSubmit: @escaping () -> Void) {
        self.cgmManager = cgmManager
        self.didSubmit = didSubmit
        _viewModel = StateObject(wrappedValue: G6CalibrationViewModel(cgmManager: cgmManager))
    }

    private var unit: HKUnit {
        return displayGlucosePreference.unit
    }

    private var usesDecimals: Bool {
        return unit != .milligramsPerDeciliter
    }

    private var decimalSeparator: String {
        return Locale.current.decimalSeparator ?? "."
    }

    private func quantity(fromMgDL value: Double) -> HKQuantity {
        return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value)
    }

    private func formatted(mgdl value: Double) -> String {
        return displayGlucosePreference.format(quantity(fromMgDL: value))
    }

    /// Latest sensor reading in mg/dL, if one exists and is fresh enough to
    /// calibrate against.
    private var currentValueMgDL: Double? {
        return viewModel.freshReading?.glucoseMgDL
    }

    private var isCalibrationBlocked: Bool {
        return viewModel.readiness != .ready
    }

    private var enteredMgDL: Double? {
        let normalized = entry.replacingOccurrences(of: decimalSeparator, with: ".")
        return Double(normalized).map {
            HKQuantity(unit: unit, doubleValue: $0).doubleValue(for: .milligramsPerDeciliter)
        }
    }

    private var deviationMgDL: Double? {
        guard let entered = enteredMgDL, let current = currentValueMgDL else {
            return nil
        }
        return abs(entered - current)
    }

    private var showsLargeDeviationWarning: Bool {
        return (deviationMgDL ?? 0) >= Self.largeDeviationWarningMgDL
    }

    private func sanitize(_ input: String) -> String {
        guard usesDecimals else {
            return String(input.filter(\.isNumber).prefix(3))
        }

        var seenSeparator = false
        var result = ""
        for character in input {
            if character.isNumber {
                result.append(character)
            } else if String(character) == decimalSeparator, !seenSeparator {
                seenSeparator = true
                result.append(character)
            }
        }
        return String(result.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedString("Enter a fingerstick value", comment: "Calibration screen heading"))
                        .font(.title2.bold())

                    Text(LocalizedString("Use a fresh fingerstick reading from your meter, taken just now. Wash and dry your hands first — a value from unwashed fingers can be badly wrong and will teach the sensor the wrong thing.", comment: "Calibration instructions"))

                    Button {
                        showingGuide = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                            Text(LocalizedString("HOW TO CALIBRATE", comment: "Calibration help button"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    HStack {
                        Text(LocalizedString("Current sensor reading", comment: "Calibration: current reading label"))
                        Spacer()
                        if let current = currentValueMgDL {
                            Text(formatted(mgdl: current))
                                .foregroundColor(.secondary)
                        } else {
                            Text(LocalizedString("—", comment: "Placeholder for missing value"))
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)

                    TextField(unit.localizedShortUnitString, text: $entry)
                        .keyboardType(usesDecimals ? .decimalPad : .numberPad)
                        .font(.title3.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .onChange(of: entry) { _, newValue in
                            let sanitized = sanitize(newValue)
                            if sanitized != newValue {
                                entry = sanitized
                            }
                            validationMessage = nil
                        }

                    if let validationMessage = validationMessage {
                        Text(validationMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    G6CalloutBox(
                        symbolName: "clock.fill",
                        tint: .blue,
                        title: LocalizedString("It may take a few minutes", comment: "Calibration callout title"),
                        body: LocalizedString("The calibration is sent the next time your transmitter connects, which can be up to 5 minutes away. The transmitter may accept it, ask for a second value, or reject it — this screen's status will tell you which.", comment: "Calibration callout body about delivery timing")
                    )

                    switch viewModel.readiness {
                    case .ready:
                        EmptyView()
                    case .noFreshReading:
                        G6CalloutBox(
                            symbolName: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: LocalizedString("No recent sensor reading", comment: "Calibration unavailable: title"),
                            body: LocalizedString("Calibrating compares your fingerstick to what the sensor reads right now, so it needs a recent reading. Wait for the next reading, then calibrate.", comment: "Calibration unavailable: explanation")
                        )
                    case .notFlat:
                        G6CalloutBox(
                            symbolName: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: LocalizedString("Glucose is changing", comment: "Calibration unavailable while trend is not flat: title"),
                            body: LocalizedString("Calibrating compares your fingerstick to the current reading, which only works when your glucose is steady. Wait for a flat trend arrow (→), then calibrate.", comment: "Calibration unavailable while trend is not flat: explanation")
                        )
                    }

                }
                .padding()
            }

            Button(action: submitTapped) {
                Text(LocalizedString("Send Calibration", comment: "Calibration submit button"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(G6PrimaryButtonStyle())
            .disabled(entry.isEmpty || isCalibrationBlocked)
            .padding()
        }
        .sheet(isPresented: $showingGuide) {
            G6CalibrationGuideView(onDone: { showingGuide = false })
        }
        .alert(
            Text(LocalizedString("Large calibration change", comment: "Calibration deviation warning title")),
            isPresented: $showingDeviationWarning
        ) {
            Button(role: .cancel, action: {}) {
                Text(LocalizedString("Cancel", comment: "Cancel button"))
            }
            Button(action: submit) {
                Text(LocalizedString("Send Anyway", comment: "Confirm calibration despite large deviation"))
            }
        } message: {
            Text(String(
                format: LocalizedString("This is %1$@ away from the current sensor reading. A change this large can be bad for sensor accuracy; try to limit each calibration to at most %2$@ at a time.", comment: "Calibration deviation warning (1: deviation with unit, 2: recommended maximum with unit)"),
                formatted(mgdl: deviationMgDL ?? 0),
                formatted(mgdl: Self.largeDeviationWarningMgDL)
            ))
        }
    }

    private func submitTapped() {
        // A large jump from the current reading gets a confirmation first;
        // big corrections can teach the sensor the wrong thing.
        guard showsLargeDeviationWarning else {
            submit()
            return
        }
        showingDeviationWarning = true
    }

    private func submit() {
        guard let valueMgDL = enteredMgDL else {
            validationMessage = LocalizedString("Enter a number.", comment: "Validation message for non-numeric calibration entry")
            return
        }

        guard (Self.minimumMgDL...Self.maximumMgDL).contains(valueMgDL) else {
            validationMessage = String(
                format: LocalizedString("Calibrations must be between %1$@ and %2$@. If your meter reads outside that range, treat it and follow your care team's guidance instead of calibrating.", comment: "Validation message for out-of-range calibration (1: minimum with unit, 2: maximum with unit)"),
                displayGlucosePreference.format(quantity(fromMgDL: Self.minimumMgDL)),
                displayGlucosePreference.format(quantity(fromMgDL: Self.maximumMgDL))
            )
            return
        }

        cgmManager.enqueue(.calibrateSensor(toMgDL: valueMgDL, at: Date()))
        didSubmit()
    }
}

// MARK: - Transmitter details

struct G6TransmitterDetailsView: View {

    let cgmManager: G6CGMManager
    let onPairNewTransmitter: () -> Void

    @State private var showingPairConfirmation = false

    /// Mirrors the persisted mode; writes go through the manager, which
    /// rebuilds the session as the other kind.
    @State private var passiveModeEnabled = false

    var body: some View {
        List {
            // Top of the transmitter screen, matching where the
            // manufacturer's app puts it.
            Section {
                Button {
                    showingPairConfirmation = true
                } label: {
                    Label(LocalizedString("Pair New Transmitter", comment: "Row to pair a different transmitter"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(G6RowButtonStyle())
                .confirmationDialog(
                    LocalizedString("Pair a new transmitter?", comment: "Confirmation title for pairing a new transmitter"),
                    isPresented: $showingPairConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedString("Continue", comment: "Confirm pairing a new transmitter"), action: onPairNewTransmitter)
                } message: {
                    Text(cgmManager.state.sensorStartDate != nil
                         ? LocalizedString("Your current sensor session will end. A session lives on the transmitter, so it cannot move to a new one — you will start a fresh session after pairing, and can reuse the sensor you are wearing. Stop the sensor first if your old transmitter is still attached and you want it stopped cleanly. Your other settings are kept.", comment: "Confirmation message for pairing a new transmitter while a session is running")
                         : LocalizedString("You will enter the new transmitter's ID and can then start a sensor session on it. Your other settings are kept.", comment: "Confirmation message for pairing a new transmitter with no session running"))
                }
            }

            Section {
                Toggle(LocalizedString("Passive Mode", comment: "Toggle label for passive (listen-only) mode"), isOn: $passiveModeEnabled)
                    .onChange(of: passiveModeEnabled) { newValue in
                        guard newValue != cgmManager.state.passiveModeEnabled else {
                            return
                        }
                        cgmManager.setPassiveModeEnabled(newValue)
                    }
            } header: {
                Text(LocalizedString("Connection", comment: "Transmitter details section header for connection mode"))
            } footer: {
                if passiveModeEnabled {
                    Text(LocalizedString("Passive mode listens to the Dexcom G6 or ONE app on this phone, which must be installed and running a sensor session with this transmitter. Start, stop and calibrate from the Dexcom app.", comment: "Footer explaining passive mode"))
                } else {
                    Text(LocalizedString("Direct mode talks to the transmitter itself, which allows starting, stopping and calibrating sessions here. The Dexcom app must not be connected to this transmitter while direct mode is on.", comment: "Footer explaining direct mode"))
                }
            }

            Section {
                row(
                    LocalizedString("Model", comment: "Transmitter detail label for model"),
                    cgmManager.state.isAnubis ? "Anubis" : cgmManager.state.deviceModel
                )
                row(LocalizedString("Transmitter ID", comment: "Transmitter detail label for ID"), cgmManager.state.transmitterID)
                row(
                    LocalizedString("Firmware", comment: "Transmitter detail label for firmware"),
                    cgmManager.state.firmwareVersion ?? LocalizedString("Unknown", comment: "Placeholder for unknown value")
                )
            }

            Section {
                if let start = cgmManager.state.transmitterStartDate {
                    row(
                        LocalizedString("First used", comment: "Transmitter detail label for activation date"),
                        start.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let expiration = cgmManager.state.transmitterExpirationDate {
                    row(
                        LocalizedString("Expected to expire", comment: "Transmitter detail label for expiry"),
                        expiration.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let days = cgmManager.state.transmitterExpiryInDays {
                    row(
                        LocalizedString("Reported lifetime", comment: "Transmitter detail label for reported lifetime"),
                        String(format: LocalizedString("%d days", comment: "Number of days (1: day count)"), Int(days))
                    )
                }
            } header: {
                Text(LocalizedString("Lifetime", comment: "Transmitter details section header for lifetime"))
            } footer: {
                if cgmManager.state.isTransmitterExpired {
                    Text(LocalizedString("This transmitter is past the end of its life. It still reports readings for a running session, but cannot start a new sensor.", comment: "Footer shown when the transmitter has expired"))
                } else if cgmManager.state.isAnubis {
                    Text(LocalizedString("This transmitter reports an extended 180-day lifetime, which means it has been modified. Warm-up is shorter and you can choose how long sessions run.", comment: "Footer explaining Anubis detection"))
                }
            }

        }
        .listStyle(.insetGrouped)
        .onAppear { passiveModeEnabled = cgmManager.state.passiveModeEnabled }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}

// MARK: - Battery details

struct G6BatteryDetailsView: View {

    let cgmManager: G6CGMManager

    var body: some View {
        List {
            if let voltageA = cgmManager.state.batteryVoltageAMillivolts,
               let voltageB = cgmManager.state.batteryVoltageBMillivolts {
                Section {
                    row(
                        LocalizedString("Voltage A", comment: "Transmitter detail label for battery A"),
                        String(format: LocalizedString("%d mV", comment: "Voltage in millivolts (1: millivolts)"), voltageA)
                    )
                    HStack {
                        Text(LocalizedString("Voltage B", comment: "Transmitter detail label for battery B"))
                        Spacer()
                        Text(String(format: LocalizedString("%d mV", comment: "Voltage in millivolts (1: millivolts)"), voltageB))
                            .foregroundColor(cgmManager.state.isBatteryLow ? .orange : .secondary)
                    }
                    if let resistance = cgmManager.state.batteryResistance {
                        row(
                            LocalizedString("Resistance", comment: "Transmitter detail label for battery resistance"),
                            String(Int(resistance))
                        )
                    }
                    if let temperature = cgmManager.state.batteryTemperature {
                        row(
                            LocalizedString("Temperature", comment: "Transmitter detail label for temperature"),
                            String(format: LocalizedString("%d °C", comment: "Temperature in Celsius (1: degrees)"), temperature)
                        )
                    }
                    if let read = cgmManager.state.lastBatteryReadDate {
                        row(
                            LocalizedString("Last checked", comment: "Transmitter detail label for last battery read"),
                            read.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                } header: {
                    Text(LocalizedString("Battery", comment: "Transmitter details section header for battery"))
                } footer: {
                    if cgmManager.state.isBatteryVeryLow {
                        Text(LocalizedString("Voltage B is very low. This transmitter may stop sending readings at any time, even during a session. Replace it as soon as you can.", comment: "Footer shown when battery B is very low"))
                    } else if cgmManager.state.isBatteryLow {
                        Text(LocalizedString("Voltage B is getting low. The transmitter should finish the sensor you are wearing, but order a replacement now.", comment: "Footer shown when battery B is low"))
                    } else {
                        Text(LocalizedString("Battery B is the cell that runs down first and determines whether the transmitter can finish a session.", comment: "Footer explaining what battery B means"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}

// MARK: - Session length (Anubis only)

struct G6SensorLifeSettingsView: View {

    let cgmManager: G6CGMManager

    @State private var days: Int
    @State private var savedDays: Int

    init(cgmManager: G6CGMManager) {
        self.cgmManager = cgmManager
        let initial = cgmManager.state.sensorLifeDays
        _days = State(initialValue: initial)
        _savedDays = State(initialValue: initial)
    }

    private var isDirty: Bool {
        return days != savedDays
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(LocalizedString("Session length", comment: "Session length picker label"))
                    Spacer()
                    Text(String(
                        format: LocalizedString("%d days", comment: "Session length value (1: day count)"),
                        savedDays
                    ))
                    .foregroundColor(.secondary)
                }

                Picker(selection: $days) {
                    ForEach(TransmitterManagerState.sensorLifeDaysRange, id: \.self) { value in
                        Text(String(
                            format: LocalizedString("%d days", comment: "Session length option (1: day count)"),
                            value
                        ))
                        .tag(value)
                    }
                } label: {
                    Text(LocalizedString("Session length", comment: "Session length picker label"))
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            } footer: {
                Text(LocalizedString("Modified transmitters can keep a sensor running past the standard 10 days. This setting only changes when this app treats the session as finished; it does not change the sensor's accuracy. Sensor readings can drift the longer a sensor is worn, so check against a fingerstick meter if a reading does not match how you feel.", comment: "Footer explaining extended session length and its accuracy caveat"))
            }

            // Applied explicitly: a wheel picker fires intermediate values
            // while scrolling, and each write hits persistent state.
            Button(action: save) {
                Text(LocalizedString("Save", comment: "Save session length button"))
            }
            .disabled(!isDirty)
            .buttonStyle(G6PrimaryButtonStyle())
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.insetGrouped)
    }

    private func save() {
        cgmManager.setSensorLifeDays(days)
        savedDays = days
    }
}

// MARK: - Dexcom Share upload

struct G6ShareUploadSettingsView: View {

    let cgmManager: G6CGMManager

    @State private var isEnabled: Bool
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var statusMessage: String?

    init(cgmManager: G6CGMManager) {
        self.cgmManager = cgmManager
        _isEnabled = State(initialValue: cgmManager.state.shareUploadEnabled)
    }

    var body: some View {
        List {
            Section {
                Toggle(LocalizedString("Upload to Dexcom Share", comment: "Toggle label for Share upload"), isOn: $isEnabled)
            } footer: {
                Text(LocalizedString("Turning this on sends your readings to Dexcom Share so people who follow you can see them in the Dexcom Follow app. It is optional, and your readings still work in this app without it.", comment: "Footer explaining Share upload"))
            }

            if isEnabled {
                Section {
                    TextField(LocalizedString("Username", comment: "Share account username field"), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(LocalizedString("Password", comment: "Share account password field"), text: $password)

                    Button(LocalizedString("Save Credentials", comment: "Button to save Share credentials")) {
                        save()
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                } header: {
                    Text(LocalizedString("Dexcom Account", comment: "Section header for Share account"))
                } footer: {
                    Text(LocalizedString("Your username and password are stored in the iOS Keychain on this device only. They are never written into app settings, logs, or backups of this app's data.", comment: "Footer explaining Keychain credential storage"))
                }
            }

            if let statusMessage = statusMessage {
                Section {
                    Text(statusMessage).font(.subheadline)
                }
            }

        }
        .listStyle(.insetGrouped)
        .onChange(of: isEnabled) { newValue in
            cgmManager.setShareUploadEnabled(newValue)
            if !newValue {
                try? G6ShareCredentialStore(transmitterID: cgmManager.state.transmitterID).delete()
                username = ""
                password = ""
                statusMessage = LocalizedString("Upload turned off and saved credentials removed.", comment: "Status message after disabling Share upload")
            }
        }
    }

    private func save() {
        let store = G6ShareCredentialStore(transmitterID: cgmManager.state.transmitterID)
        do {
            try store.save(G6ShareCredentials(username: username, password: password))
            password = ""
            statusMessage = LocalizedString("Credentials saved to the Keychain.", comment: "Status message after saving Share credentials")
        } catch {
            statusMessage = LocalizedString("Could not save your credentials. Try again.", comment: "Status message when saving Share credentials fails")
        }
    }
}
