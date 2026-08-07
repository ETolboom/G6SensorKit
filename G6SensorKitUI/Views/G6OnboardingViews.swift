//
//  G6OnboardingViews.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Onboarding flow. All copy is written specifically for this project in
//  plain language; no text, screenshots, or artwork is taken from Dexcom's
//  apps or printed materials. Illustrations are SF Symbols or original
//  assets shipped with this framework.
//
//  Safety-relevant statements (warm-up, do-not-dose, alerting, fingerstick
//  fallback) must be preserved in any translation or redesign.
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore

// MARK: - Shared building blocks

/// A numbered instruction row used by the placement guide.
struct G6InstructionStep: View {
    let number: Int
    let symbolName: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbolName)
                    .foregroundColor(.accentColor)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

struct G6ContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    init(title: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title ?? LocalizedString("Continue", comment: "Default continue button label")
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(G6PrimaryButtonStyle())
        .disabled(!isEnabled)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

// MARK: - 1. Introduction

/// Product hero, in the shape G7SensorKit uses: name, device, a short
/// statement of what this driver does, then Continue. The wording is the
/// inverse of G7's — that one piggybacks the manufacturer's app, this one
/// replaces it, and getting that distinction wrong would be dangerous.
struct G6IntroductionView: View {
    let didContinue: () -> Void

    @Environment(\.appName) private var appName

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 28) {
                Text(LocalizedString("Dexcom G6", comment: "Introduction screen product title"))
                    .font(.largeTitle.bold())

                G6TransmitterImage(size: 200)

                VStack(spacing: 14) {
                    Text(String(
                        format: LocalizedString("%1$@ talks to your G6 or Dexcom ONE transmitter directly. It starts and stops sensor sessions, sends your calibrations, and fills in readings it missed.", comment: "Introduction: what the native driver does (1: app name)"),
                        appName
                    ))

                    Text(LocalizedString("You do not need the Dexcom app — and you must not let it use the same transmitter at the same time.", comment: "Introduction: single-app requirement"))
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            }

            Spacer(minLength: 0)

            G6ContinueButton(action: didContinue)
        }
    }
}

struct G6BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .padding(.top, 7)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct G6CalloutBox: View {
    let symbolName: String
    let tint: Color
    let title: String
    let message: String

    init(symbolName: String, tint: Color, title: String, body: String) {
        self.symbolName = symbolName
        self.tint = tint
        self.title = title
        self.message = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(tint.opacity(0.10))
        .cornerRadius(10)
    }
}

// MARK: - 2. Transmitter ID

struct G6TransmitterIDEntryView: View {
    let initialValue: String
    let didSubmit: (String) -> Void

    @State private var transmitterID: String = ""
    @State private var validationMessage: String?

    init(initialValue: String, didSubmit: @escaping (String) -> Void) {
        self.initialValue = initialValue
        self.didSubmit = didSubmit
        _transmitterID = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedString("Enter your transmitter ID", comment: "Transmitter ID screen heading"))
                        .font(.title2.bold())

                    // The manual points at two places, so show both rather
                    // than making the user guess which one they have to hand.
                    G6FindCodeCard(
                        assetName: "G6TransmitterIDLocationBox",
                        caption: LocalizedString("On the transmitter box, next to the barcode.", comment: "Transmitter ID: location on the box")
                    ) {
                        G6TransmitterBackGlyph(size: 150)
                    }

                    G6FindCodeCard(
                        assetName: "G6TransmitterIDLocation",
                        caption: LocalizedString("Or on the back of the transmitter itself.", comment: "Transmitter ID: location on the transmitter")
                    ) {
                        G6TransmitterBackGlyph(size: 150)
                    }

                    TextField(LocalizedString("6-character ID", comment: "Transmitter ID text field placeholder"), text: $transmitterID)
                        .textCase(.uppercase)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .font(.title3.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .onChange(of: transmitterID) { newValue in
                            transmitterID = String(newValue.uppercased().prefix(6))
                            validationMessage = nil
                        }

                    if let validationMessage = validationMessage {
                        Text(validationMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(LocalizedString("This app works with Dexcom G6 and Dexcom ONE transmitters. Older G5 transmitters, whose IDs begin with 4, are not supported.", comment: "Transmitter ID: supported hardware note"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }

            G6ContinueButton(isEnabled: transmitterID.count == 6) {
                submit()
            }
        }
    }

    private func submit() {
        guard transmitterID.count == 6 else {
            return
        }

        if transmitterID.hasPrefix("4") {
            validationMessage = LocalizedString("IDs that begin with 4 belong to Dexcom G5 transmitters, which this app does not support.", comment: "Validation message for G5 transmitter ID")
            return
        }

        didSubmit(transmitterID)
    }
}

// MARK: - 3. Sensor code

struct G6SensorCodeEntryView: View {
    /// Passes nil when the user chooses to start without a code.
    let didSubmit: (String?) -> Void

    @State private var sensorCode: String = ""
    @State private var validationMessage: String?
    @State private var confirmingNoCode = false
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedString("Enter your sensor code", comment: "Sensor code screen heading"))
                        .font(.title2.bold())

                    G6FindCodeCard(
                        assetName: "G6SensorCodeLocation",
                        caption: LocalizedString("The 4-digit code is on the applicator’s adhesive label, and is unique to that sensor. Use the code from the applicator you are about to insert — a code from a different one will make readings inaccurate.", comment: "Sensor code: where to find it")
                    ) {
                        G6SensorCodeLabelGlyph(size: 150)
                    }

                    TextField(LocalizedString("4-digit code", comment: "Sensor code text field placeholder"), text: $sensorCode)
                        .keyboardType(.numberPad)
                        .focused($codeFieldFocused)
                        .font(.title3.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .onChange(of: sensorCode) { newValue in
                            sensorCode = String(newValue.filter(\.isNumber).prefix(4))
                            validationMessage = nil
                        }

                    if let validationMessage = validationMessage {
                        Text(validationMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    G6CalloutBox(
                        symbolName: "drop.fill",
                        tint: .blue,
                        title: LocalizedString("No code on your sensor?", comment: "Sensor code callout title"),
                        body: LocalizedString("You can start without one. The transmitter will then ask you for two fingerstick glucose values after warm-up, and for one more each day. \"Calibration\" means telling the sensor what your meter reads, so it can correct itself.", comment: "Sensor code callout body explaining calibration")
                    )

                }
                .padding()
            }
            .onAppear { codeFieldFocused = true }

            VStack(spacing: 10) {
                G6ContinueButton(
                    title: LocalizedString("Use This Code", comment: "Sensor code submit button"),
                    isEnabled: sensorCode.count == 4
                ) {
                    submit()
                }

                Button(LocalizedString("Start Without a Code", comment: "Button to start a session with no sensor code")) {
                    confirmingNoCode = true
                }
                .padding(.bottom)
                .confirmationDialog(
                    LocalizedString("Start without a sensor code?", comment: "Confirmation title for a code-less session"),
                    isPresented: $confirmingNoCode,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedString("Start Without a Code", comment: "Confirm a code-less session"), role: .destructive) {
                        didSubmit(nil)
                    }
                    Button(LocalizedString("Enter the Code", comment: "Return to entering the sensor code"), role: .cancel) {
                        codeFieldFocused = true
                    }
                } message: {
                    Text(LocalizedString("Without the code the sensor cannot use its factory calibration, and the transmitter will ask you for two fingerstick values after warm-up and one every day after that. The code is on the applicator label.", comment: "Confirmation message explaining a code-less session"))
                }
            }
        }
    }

    private func submit() {
        guard SensorCode(sensorCode) != nil else {
            validationMessage = LocalizedString("That code isn't one this app recognizes. Check the digits on the applicator label, or start without a code.", comment: "Validation message for unrecognized sensor code")
            return
        }

        didSubmit(sensorCode)
    }
}

// MARK: - 5. Pairing

/// Observes the manager so the screen reflects the radio live. Without this
/// the view read `manager.state` once and never updated, so a successful
/// connection was invisible.
final class G6PairingViewModel: ObservableObject, G6CGMManagerObserver {
    private let cgmManager: G6CGMManager?

    @Published private(set) var phase: G6ConnectionPhase = .searching
    @Published private(set) var isPaired = false
    @Published private(set) var hasSession = false
    @Published private(set) var searchingLongerThanExpected = false

    private let startedAt = Date()
    private var tick: Timer?

    init(cgmManager: G6CGMManager?) {
        self.cgmManager = cgmManager
        refresh()
        cgmManager?.addStateObserver(self)

        // Two missed advertisement cycles is the point where this stops
        // being "be patient" and starts being "something is wrong".
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let overdue = Date().timeIntervalSince(self.startedAt) > 11 * 60
            if overdue != self.searchingLongerThanExpected {
                DispatchQueue.main.async { self.searchingLongerThanExpected = overdue }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    deinit {
        tick?.invalidate()
        cgmManager?.removeStateObserver(self)
    }

    func g6CGMManagerDidUpdateState(_ manager: G6CGMManager) {
        refresh()
    }

    private func refresh() {
        guard let cgmManager = cgmManager else { return }
        let phase = cgmManager.connectionPhase
        let paired = cgmManager.isPaired
        let session = cgmManager.state.sensorStartDate != nil
        if Thread.isMainThread {
            self.phase = phase; isPaired = paired; hasSession = session
        } else {
            DispatchQueue.main.async {
                self.phase = phase; self.isPaired = paired; self.hasSession = session
            }
        }
    }
}

/// Holds off auto-lock while a screen waits on the transmitter, which
/// advertises only about every five minutes. Counted, and restores the
/// previous value, so it does not clobber the host's own setting.
enum G6ScreenWakeLock {
    private static var holders = 0
    private static var previousValue = false

    static func hold() {
        dispatchPrecondition(condition: .onQueue(.main))
        if holders == 0 {
            previousValue = UIApplication.shared.isIdleTimerDisabled
        }
        holders += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard holders > 0 else {
            return
        }
        holders -= 1
        if holders == 0 {
            UIApplication.shared.isIdleTimerDisabled = previousValue
        }
    }
}

struct G6PairingView: View {
    @StateObject private var viewModel: G6PairingViewModel
    let didContinue: () -> Void

    @State private var showingLogShare = false

    init(manager: G6CGMManager?, didContinue: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: G6PairingViewModel(cgmManager: manager))
        self.didContinue = didContinue
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedString("Connecting to your transmitter", comment: "Pairing screen heading"))
                        .font(.title2.bold())

                    statusRow

                    if !viewModel.isPaired {
                        Text(LocalizedString("Your transmitter only talks to your phone about once every 5 minutes, so this can take a few minutes. Keep your phone nearby.", comment: "Pairing: explanation of the 5-minute cycle"))
                    }

                    if viewModel.phase == .awaitingPairing {
                        G6CalloutBox(
                            symbolName: "lock.shield.fill",
                            tint: .orange,
                            title: LocalizedString("Tap Pair on the iOS prompt", comment: "Pairing callout title while awaiting the prompt"),
                            body: LocalizedString("Accept the Bluetooth pairing request within about a minute. If it disappears, the app tries again on the next connection.", comment: "Pairing callout body while awaiting the prompt")
                        )
                    } else if !viewModel.isPaired {
                        G6CalloutBox(
                            symbolName: "lock.shield.fill",
                            tint: .blue,
                            title: LocalizedString("A pairing request will appear", comment: "Pairing callout title"),
                            body: LocalizedString("The first time they connect, iOS shows a Bluetooth pairing request. Tap Pair within about a minute — if it disappears, the app will try again on the next connection.", comment: "Pairing callout body about the iOS prompt")
                        )
                    }

                    if viewModel.hasSession {
                        Label(LocalizedString("Sensor session found", comment: "Pairing success label for an existing session"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    // A transmitter advertises about every 5 minutes, so a
                    // couple of missed cycles means something is actually
                    // wrong rather than slow.
                    if !viewModel.isPaired && viewModel.searchingLongerThanExpected {
                        G6CalloutBox(
                            symbolName: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: LocalizedString("Still looking", comment: "Pairing troubleshooting title"),
                            body: LocalizedString("Check that the Dexcom app is not connected to this transmitter, that the transmitter ID is exactly right, and that your phone is next to it. Bluetooth must be on.", comment: "Pairing troubleshooting body")
                        )

                        Button {
                            showingLogShare = true
                        } label: {
                            Label(LocalizedString("Share Logs", comment: "Row to export the log files"), systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .sheet(isPresented: $showingLogShare) {
                            G6ActivityViewController(activityItems: G6Logger.shared.debugLogURLs())
                        }
                    }
                }
                .padding()
            }

            // Continue stays disabled until the transmitter has actually been
            // authenticated — advancing earlier would show a warm-up screen
            // for a connection that may never have happened.
            G6ContinueButton(isEnabled: viewModel.isPaired, action: didContinue)
        }
        .onAppear { G6ScreenWakeLock.hold() }
        .onDisappear { G6ScreenWakeLock.release() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch (viewModel.isPaired, viewModel.phase) {
        case (true, _):
            Label(LocalizedString("Connected to your transmitter", comment: "Pairing status: connected"), systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        case (false, .awaitingPairing):
            HStack(spacing: 12) {
                ProgressView()
                Text(LocalizedString("Waiting for you to accept pairing…", comment: "Pairing status: awaiting prompt"))
                    .font(.subheadline)
            }
        default:
            HStack(spacing: 12) {
                ProgressView()
                Text(LocalizedString("Looking for your transmitter…", comment: "Pairing status: searching"))
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - 6. Warm-up

struct G6WarmupView: View {
    let manager: G6CGMManager?
    let didFinish: () -> Void

    /// Warm-up can finish while this screen is open, so the copy is
    /// recomputed rather than frozen at first render.
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var warmupMinutes: Int {
        guard let state = manager?.state else {
            return Int(G6CGMManagerState.stockWarmupPeriod / 60)
        }
        return Int(state.warmupPeriod / 60)
    }

    /// Nil when the transmitter has not reported a start time yet, which is
    /// the normal case for a session that was only just requested.
    private var endDate: Date? {
        return manager?.state.warmupEndDate
    }

    private var isFinished: Bool {
        guard let endDate = endDate else {
            return false
        }
        return endDate <= now
    }

    private var minutesRemaining: Int? {
        guard let endDate = endDate, endDate > now else {
            return nil
        }
        return max(1, Int((endDate.timeIntervalSince(now) / 60).rounded(.up)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(isFinished
                         ? LocalizedString("Warm-up is finished", comment: "Warm-up screen heading once warm-up has completed")
                         : LocalizedString("Your sensor is warming up", comment: "Warm-up screen heading"))
                        .font(.title2.bold())

                    if isFinished {
                        Text(LocalizedString("Readings will appear as they arrive from the transmitter, about every 5 minutes.", comment: "Explanation shown once warm-up has completed"))
                    } else {
                        Text(String(
                            format: LocalizedString("Warm-up takes about %d minutes. You will not get any glucose readings until it finishes.", comment: "Warm-up duration explanation (1: minutes)"),
                            warmupMinutes
                        ))
                    }

                    G6CalloutBox(
                        symbolName: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: LocalizedString("Do not dose on early readings", comment: "Warm-up callout title"),
                        body: LocalizedString("Do not make insulin decisions from the first readings after warm-up, or from readings that look wrong for how you feel. Use a fingerstick meter instead, and follow your care team's guidance.", comment: "Warm-up callout body about dosing safety")
                    )

                    if let endDate = endDate, let minutesRemaining = minutesRemaining {
                        Label(
                            String(
                                format: LocalizedString("Expected to finish at %1$@, about %2$d minutes from now", comment: "Warm-up completion time (1: time, 2: minutes remaining)"),
                                endDate.formatted(date: .omitted, time: .shortened),
                                minutesRemaining
                            ),
                            systemImage: "clock"
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }

                }
                .padding()
            }

            G6ContinueButton(title: LocalizedString("Done", comment: "Warm-up screen finish button"), action: didFinish)
        }
        .onReceive(tick) { now = $0 }
    }
}
