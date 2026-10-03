//
//  G6CGMManager.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  LoopKit CGMManager conformance over G6SensorCore's transmitter sessions.
//  Two modes: direct (the manager owns the transmitter — it authenticates,
//  starts and stops sessions, sends calibrations, requests backfill) and
//  passive (the manager observes the session another client, such as the
//  Dexcom app, drives — like CGMBLEKit).
//

import Foundation
import HealthKit
import LoopKit
import G6SensorCore
import os.log

public protocol G6CGMManagerObserver: AnyObject {
    func g6CGMManagerDidUpdateState(_ manager: G6CGMManager)
}

/// Live connection progress. Deliberately transient — it describes what the
/// radio is doing right now and must not be persisted in `rawState`.
public enum G6ConnectionPhase: Equatable {
    /// Waiting for the transmitter to advertise; it only does so every ~5 min.
    case searching
    /// A bond was requested; the user has ~60 s to accept the iOS prompt.
    case awaitingPairing
    /// Authenticated and exchanging messages.
    case connected
}

public final class G6CGMManager: CGMManager {

    /// Readings this stale stop counting as a live signal.
    private static let signalLossInterval: TimeInterval = .minutes(20)

    /// Ask for backfill once the gap since the last reading exceeds this.
    private static let backfillGapThreshold: TimeInterval = .minutes(5.3)

    /// How far back backfill may reach.
    private static let backfillWindow: TimeInterval = .hours(6)

    /// Battery is re-read at most this often.
    private static let batteryReadInterval: TimeInterval = .hours(2)

    public static let pluginIdentifier = "G6SensorKit"

    public var pluginIdentifier: String {
        return Self.pluginIdentifier
    }

    public let localizedTitle = LocalizedString("Dexcom G6 / ONE", comment: "Title for the G6SensorKit CGM manager")

    public var managedDataInterval: TimeInterval? {
        return .hours(3)
    }

    public static var onboardingMaximumSensorLifeDays: Int {
        return TransmitterManagerState.sensorLifeDaysRange.upperBound
    }

    private let logger = OSLog(category: "G6CGMManager")

    private let lockedState: Locked<G6CGMManagerState>

    public private(set) var session: (any TransmitterSessioning)?

    /// Commands queued for the next connection cycle.
    private let lockedCommandQueue: Locked<CommandQueue> = Locked(CommandQueue())

    /// The command handed to the session and not yet answered. Held so a
    /// flagged command whose send fails can be reported to the user.
    private let lockedInFlightCommand: Locked<QueuedCommand?> = Locked(nil)

    /// Response code from a session start awaiting confirmation. The reply
    /// alone does not say whether a session began, so it is held until the
    /// transmitter's state settles the question.
    private var unverifiedSessionStart: SessionStartResponse?

    /// Alerts currently raised, so an ongoing condition is not re-issued on
    /// every connection. In memory only: on relaunch the first evaluation
    /// re-raises whatever still applies.
    var raisedAlerts: Set<G6Alert> = []

    var delegateForAlerts: WeakSynchronizedDelegate<CGMManagerDelegate> { delegate }

    var log: OSLog { logger }

    #if targetEnvironment(simulator)
    var simulationTimer: Timer?

    func mutateStateForSimulation(_ changes: (inout G6CGMManagerState) -> Void) {
        mutateState(changes)
    }

    func notifySimulationObservers() {
        notifyObservers()
    }

    func deliverSimulated(_ samples: [NewGlucoseSample]) {
        deliver(samples)
    }
    #endif

    /// Weak boxes so an observing view model going away cannot keep the
    /// manager alive, and so several screens can observe at once (the single
    /// slot this replaced meant settings silently displaced onboarding).
    private final class WeakObserver {
        weak var value: G6CGMManagerObserver?
        init(_ value: G6CGMManagerObserver) { self.value = value }
    }
    private let lockedObservers: Locked<[WeakObserver]> = Locked([])

    public internal(set) var connectionPhase: G6ConnectionPhase = .searching {
        didSet {
            if connectionPhase != oldValue {
                notifyObservers()
            }
        }
    }

    /// True once the transmitter has been authenticated and its clock read —
    /// the real proof that pairing succeeded.
    public var isPaired: Bool {
        return state.transmitterStartDate != nil
    }

    public var state: G6CGMManagerState {
        return lockedState.value
    }

    // MARK: - Lifecycle

    public init(state: G6CGMManagerState) {
        self.lockedState = Locked(state)
        lockedCommandQueue.mutate { $0 = CommandQueue(rawValues: state.pendingCommands) }
        startSession()
    }

    public init?(rawState: RawStateValue) {
        guard var state = G6CGMManagerState(rawValue: rawState) else {
            return nil
        }

        // A recorded start failure describes a moment, not a condition. If a
        // session is running it is already contradicted, so it is not carried
        // across a relaunch.
        if state.hasActiveSession {
            state.lastSessionStartFailure = nil
        }

        self.lockedState = Locked(state)
        lockedCommandQueue.mutate { $0 = CommandQueue(rawValues: state.pendingCommands) }
        startSession()
    }

    public var rawState: RawStateValue {
        return state.rawValue
    }

    public var isOnboarded: Bool {
        return state.isOnboarded
    }

    public weak var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public var debugDescription: String {
        return [
            "## G6CGMManager",
            "transmitterID: \(state.transmitterID)",
            "model: \(state.deviceModel)",
            "mode: \(state.passiveModeEnabled ? "passive" : "direct")",
            "firmware: \(state.firmwareVersion ?? "unknown")",
            "isAnubis: \(state.isAnubis)",
            "sensorStartDate: \(String(describing: state.sensorStartDate))",
            "sensorExpirationDate: \(String(describing: state.sensorExpirationDate))",
            "transmitterStartDate: \(String(describing: state.transmitterStartDate))",
            "isInWarmup: \(state.isInWarmup)",
            "latestReadingDate: \(String(describing: state.latestReading?.date))",
            "shareUploadEnabled: \(state.shareUploadEnabled)",
            session.map(String.init(reflecting:)) ?? "No session",
        ].joined(separator: "\n")
    }

    // MARK: - State mutation

    @discardableResult
    private func mutateState(_ changes: (inout G6CGMManagerState) -> Void) -> G6CGMManagerState {
        let oldValue = lockedState.value
        let newValue = lockedState.mutate { state in
            changes(&state)
        }

        if newValue != oldValue {
            notifyDelegateOfStateChange()
            notifyObservers()
            evaluateAlerts()
        }

        return newValue
    }

    private func notifyDelegateOfStateChange() {
        delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
        }
    }

    /// Wording for a start the transmitter declined and that produced no
    /// session. End of life is only claimed when the transmitter's own dates
    /// agree — the response code alone has been seen to say that about a
    /// transmitter activated minutes earlier.
    private func describeStartRefusal(_ code: SessionStartResponse) -> String {
        if state.isTransmitterExpired, let expiration = state.transmitterExpirationDate {
            return String(
                format: LocalizedString("This transmitter reached the end of its %d-day life on %@ and can no longer start a sensor session. A new transmitter is needed.", comment: "Explanation when an expired transmitter refuses a session start (1: lifetime days, 2: expiry date)"),
                Int(state.transmitterLifetime / 86400),
                DateFormatter.localizedString(from: expiration, dateStyle: .medium, timeStyle: .none)
            )
        }

        switch code {
        case .staleStartCommand:
            return LocalizedString("The transmitter did not accept the start time. Try starting the sensor again.", comment: "Session start refused as stale")
        default:
            return LocalizedString("The transmitter did not start a sensor session. Try again, and check that the transmitter is clicked firmly into the sensor holder.", comment: "Session start refused for an unclear reason")
        }
    }

    /// Records a setup-flow event, so an exported log explains what the user
    /// did as well as what the radio did.
    public func logSetupEvent(_ message: String) {
        log.default("Setup: %{public}@", message)
    }

    /// Writes the current configuration into the log, so an exported file
    /// explains the state the traffic came from.
    public func logStateSnapshot() {
        log.default("State snapshot: %{public}@", debugDescription)
    }

    public func addStateObserver(_ observer: G6CGMManagerObserver) {
        lockedObservers.mutate { observers in
            observers.removeAll { $0.value == nil || $0.value === observer }
            observers.append(WeakObserver(observer))
        }
    }

    public func removeStateObserver(_ observer: G6CGMManagerObserver) {
        lockedObservers.mutate { observers in
            observers.removeAll { $0.value == nil || $0.value === observer }
        }
    }

    private func notifyObservers() {
        let observers = lockedObservers.value.compactMap { $0.value }
        DispatchQueue.main.async {
            for observer in observers {
                observer.g6CGMManagerDidUpdateState(self)
            }
        }
    }

    // MARK: - Session management

    private func startSession() {
        #if targetEnvironment(simulator)
        // CoreBluetooth cannot reach a transmitter in the simulator, so run
        // the stand-in instead of waiting on a connection that cannot happen.
        startSimulatedSession()
        return
        #else
        connectionPhase = .searching
        let session: any TransmitterSessioning
        if state.passiveModeEnabled {
            session = PassiveTransmitterSession(
                id: state.transmitterID,
                peripheralIdentifier: state.peripheralIdentifier,
                activationDate: state.transmitterStartDate
            )
        } else {
            let active = TransmitterSession(id: state.transmitterID, peripheralIdentifier: state.peripheralIdentifier)
            active.commandSource = self
            session = active
        }
        session.delegate = self
        self.session = session
        session.start()
        #endif
    }

    /// Queues a device command for the next connection cycle.
    ///
    /// - Parameter notifyIfUndelivered: for commands the user is relying on
    ///   — a stop they believe has ended the session, a calibration they
    ///   believe was applied. The user is alerted if one has not gone out
    ///   within a few connection cycles, or fails to send, or expires unsent.
    ///   A failed or expired command is never retried: the user decides.
    public func enqueue(_ command: Command, notifyIfUndelivered: Bool = false) {
        // A passive session never writes, so a command could never be
        // delivered. The UI hides the command rows in passive mode; this is
        // the backstop.
        guard !state.passiveModeEnabled else {
            log.error("Dropping command %{public}@: passive mode cannot write to the transmitter", String(describing: command))
            return
        }

        // Newest wins. Repeated trips through setup used to stack session
        // starts — seven went out in one connection — and because the queue
        // is persisted, a stale code-less start could reach the transmitter
        // ahead of the one carrying the sensor code the user actually typed.
        var superseded = 0
        lockedCommandQueue.mutate { queue in
            superseded = queue.enqueue(command, notifyIfUndelivered: notifyIfUndelivered)
        }

        if superseded > 0 {
            log.default("Replaced %d queued command(s) with %{public}@", superseded, String(describing: command))
        } else {
            log.default("Queued %{public}@", String(describing: command))
        }

        mutateState { state in
            state.pendingCommands = self.lockedCommandQueue.value.rawValues

            // Asking again is the user's answer to an earlier one that did
            // not get through.
            if let undelivered = state.undeliveredCommand, undelivered.entry.command.supersededBy(command) {
                state.undeliveredCommand = nil
            }

            // Reflect the entered code straight away. Waiting until the
            // transmitter answered meant the screen said "Not used" for as
            // long as the command sat in the queue — and permanently if the
            // reply was misread, which is exactly what happened.
            if case .startSensor(_, let sensorCode) = command {
                state.sensorCode = sensorCode.carriesParameters ? sensorCode.code : nil
            }
        }

        // Nudge the connection in case it is idle.
        session?.start()

        #if targetEnvironment(simulator)
        // No link will ever drain the queue in the simulator; apply the
        // command to state directly, mirroring didComplete on hardware,
        // so End Sensor / Start New Sensor work end-to-end there.
        lockedCommandQueue.mutate { _ = $0.dequeue() }
        if case .stopSensor = command, state.sensorStartDate != nil {
            let sensorEnded = PersistedCgmEvent(
                date: Date(),
                type: .sensorEnd,
                deviceIdentifier: state.transmitterID,
                failureMessage: LocalizedString("Stopped by user", comment: "Reason recorded when a session ends because the user stopped it")
            )
            delegate.notify { delegate in
                delegate?.cgmManager(self, hasNew: [sensorEnded])
            }
        }
        mutateState { state in
            state.pendingCommands = self.lockedCommandQueue.value.rawValues
            switch command {
            case .stopSensor:
                state.sensorStartDate = nil
                state.sensorCode = nil
            case .startSensor(let date, let sensorCode):
                state.sensorCode = sensorCode.carriesParameters ? sensorCode.code : nil
                state.sensorStartDate = date
                    .addingTimeInterval(-(state.warmupPeriod - G6CGMManager.simulatedWarmupRemaining))
            case .calibrateSensor, .resetTransmitter:
                break
            }
        }
        #endif
    }

    public func setSensorLifeDays(_ days: Int) {
        mutateState { state in
            state.sensorLifeDays = TransmitterManagerState.clampedSensorLifeDays(days)
        }
    }

    public func setShareUploadEnabled(_ enabled: Bool) {
        mutateState { state in
            state.shareUploadEnabled = enabled
        }
    }

    public func setShouldSyncToRemoteService(_ enabled: Bool) {
        mutateState { state in
            state.shouldSyncToRemoteService = enabled
        }
    }

    /// Switches between passive (observe the Dexcom app's session) and direct
    /// (own the transmitter) mode. The live session can't change nature, so
    /// it is torn down and rebuilt as the other kind.
    public func setPassiveModeEnabled(_ enabled: Bool) {
        guard enabled != state.passiveModeEnabled else {
            return
        }

        log.default("Switching to %{public}@ mode", enabled ? "passive" : "direct")

        session?.stop()
        session = nil

        // Queued commands belong to the mode they were queued in. Passive
        // mode can't deliver them, and carrying them back into direct mode
        // would replay a stale stop or start — possibly days later, against
        // a session the Dexcom app has since started.
        lockedCommandQueue.mutate { $0.removeAll() }
        lockedInFlightCommand.mutate { $0 = nil }

        mutateState { state in
            state.passiveModeEnabled = enabled
            state.pendingCommands = []
            state.undeliveredCommand = nil
        }

        startSession()
    }

    /// Switches to a different transmitter without tearing down the CGM.
    ///
    /// Everything scoped to the old transmitter is cleared — its clock,
    /// reported lifetime, firmware, peripheral handle, session and queued
    /// commands — while the settings that belong to the user, such as remote
    /// sync and the Anubis session length, are kept.
    public func replaceTransmitter(id: String) {
        let previousID = state.transmitterID
        log.default("Replacing transmitter %{public}@ with %{public}@", previousID, id)

        // A sensor session lives on the transmitter, so it cannot follow the
        // user across. End it explicitly rather than letting it disappear
        // with the state: the host would otherwise still believe a session is
        // running on a transmitter that is no longer here.
        if state.sensorStartDate != nil {
            let sensorEnded = PersistedCgmEvent(
                date: Date(),
                type: .sensorEnd,
                deviceIdentifier: previousID,
                failureMessage: LocalizedString("Ended because the transmitter was replaced", comment: "Reason recorded when a session ends due to a transmitter swap")
            )
            delegate.notify { delegate in
                delegate?.cgmManager(self, hasNew: [sensorEnded])
            }

            // Best effort: if the old transmitter happens to be connected
            // right now, tell it to stop. Once it is off the sensor there is
            // nothing to send to, so this is not worth waiting on. A passive
            // session cannot send anything at all.
            if !state.passiveModeEnabled, connectionPhase == .connected, let active = session as? TransmitterSession {
                log.default("Old transmitter still connected; sending session stop before switching")
                active.commandSource = self
                lockedCommandQueue.mutate { $0 = CommandQueue([.stopSensor(at: Date())]) }
            } else {
                log.default("Old transmitter not connected; its session is left as-is")
            }
        }

        // Record the end of the old transmitter before its dates are cleared,
        // so the host's event log shows the handover.
        if let start = state.transmitterStartDate {
            let ended = PersistedCgmEvent(
                date: max(start, Date()),
                type: .transmitterEnd,
                deviceIdentifier: previousID,
                expectedLifetime: state.transmitterLifetime
            )
            delegate.notify { delegate in
                delegate?.cgmManager(self, hasNew: [ended])
            }
        }

        // Stop first: callbacks from the old session must not land in the
        // middle of the state reset. The session itself is kept and pointed at
        // the new transmitter — the radio does not need rebuilding for a swap.
        session?.stop()
        lockedCommandQueue.mutate { $0.removeAll() }
        lockedInFlightCommand.mutate { $0 = nil }
        raisedAlerts = []

        mutateState { state in
            state.transmitterID = id
            state.peripheralIdentifier = nil
            state.transmitterStartDate = nil
            state.transmitterExpiryInDays = nil
            state.firmwareVersion = nil
            state.sensorStartDate = nil
            state.sensorCode = nil
            state.latestReading = nil
            state.recentReadings = []
            state.pendingCommands = []
            state.undeliveredCommand = nil
            state.lastSessionStartFailure = nil
        }

        connectionPhase = .searching

        if let session = session {
            session.retarget(id: id)
        } else {
            startSession()
        }
    }

    public func completeOnboarding() {
        mutateState { state in
            state.isOnboarded = true
            state.setupStep = nil
        }
    }

    /// Records setup progress so an interrupted flow resumes in place.
    public func recordSetupStep(_ step: G6SetupStep) {
        mutateState { state in
            state.setupStep = step
        }
    }

    public func delete(completion: @escaping () -> Void) {
        #if targetEnvironment(simulator)
        simulationTimer?.invalidate()
        simulationTimer = nil
        #endif
        session?.stop()
        session = nil

        // Best-effort credential cleanup; failure to delete must not block.
        try? G6ShareCredentialStore(transmitterID: state.transmitterID).delete()

        notifyDelegateOfDeletion(completion: completion)
    }

    // MARK: - CGMManager

    public var providesBLEHeartbeat: Bool {
        // Direct mode: the owned connection wakes the app roughly every
        // 5 minutes. Passive mode: the Dexcom app drives the cadence, so the
        // host's own timer must keep ticking.
        // Loop uses this to suppress the pump's timer tick; Trio dev reads it
        // through FetchGlucoseManager.
        return !state.passiveModeEnabled
    }

    public var shouldSyncToRemoteService: Bool {
        return state.shouldSyncToRemoteService
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        guard let reading = state.latestReading else {
            return nil
        }
        return G6GlucoseDisplay(reading: reading, isStale: isSignalStale)
    }

    public var cgmManagerStatus: CGMManagerStatus {
        return CGMManagerStatus(
            hasValidSensorSession: hasValidSensorSession,
            lastCommunicationDate: state.latestReading?.date,
            device: device
        )
    }

    public var device: HKDevice? {
        return HKDevice(
            name: "G6SensorKit",
            manufacturer: "Dexcom",
            model: state.deviceModel,
            hardwareVersion: nil,
            firmwareVersion: state.firmwareVersion,
            softwareVersion: nil,
            localIdentifier: state.transmitterID,
            udiDeviceIdentifier: "00386270000385"
        )
    }

    private var hasValidSensorSession: Bool {
        // A session is valid when a sensor is running; warm-up counts, since
        // data is expected without further user action.
        return state.sensorStartDate != nil
    }

    private var isSignalStale: Bool {
        guard let date = state.latestReading?.date else {
            return true
        }
        return Date().timeIntervalSince(date) > Self.signalLossInterval
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        // Runtime hook, not a data path: re-arm the pending connect and queue
        // backfill when a gap is detected. Readings arrive through the
        // session delegate on BLE events.
        session?.start()

        // Time-based alerts — signal loss, a command that has not got
        // through — must not wait for a connection that may never come.
        evaluateAlerts()

        // Backfill requests and battery reads are writes; passive mode
        // cannot perform them and picks up whatever the driving client asks
        // for instead.
        if let session = session as? TransmitterSession {
            if let lastDate = state.latestReading?.date {
                let gap = Date().timeIntervalSince(lastDate)
                if gap > Self.backfillGapThreshold {
                    let end = Date()
                    let start = max(lastDate, end.addingTimeInterval(-Self.backfillWindow))
                    session.requestedBackfillWindow = DateInterval(start: start, end: end)
                }
            }

            let batteryReadRecently = state.lastBatteryReadDate
                .map { Date().timeIntervalSince($0) < Self.batteryReadInterval } ?? false
            if !batteryReadRecently {
                session.shouldReadBattery = true
            }
        }

        completion(.noData)
    }

    // MARK: - AlertResponder / AlertSoundVendor

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        let alert = G6Alert(rawValue: alertIdentifier)
        alert.map { alert in
            log.default("Acknowledged alert: %{public}@", alert.rawValue)
        }
        if alert == .commandFailed {
            mutateState { state in
                state.undeliveredCommand?.acknowledged = true
            }
        }
        completion(nil)
    }

    public func getSoundBaseURL() -> URL? {
        return nil
    }

    public func getSounds() -> [Alert.Sound] {
        return []
    }
}


// MARK: - TransmitterSessionDelegate

extension G6CGMManager: TransmitterSessionDelegate {

    public func transmitterSessionDidConnect(_ session: any TransmitterSessioning) {
        log.default("Connected to transmitter")
        connectionPhase = .connected
        // Expiry and signal loss are time-based: without this they would only
        // be noticed when some other part of the state happened to change.
        evaluateAlerts()
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didError error: Error) {
        log.error("Session error: %{public}@", String(describing: error))
        connectionPhase = .searching
        delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: .error(error))
        }
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didRead glucose: Glucose) {
        reconcileSession(with: glucose)

        guard let sample = newGlucoseSample(from: glucose) else {
            // Unreliable value: tell the host explicitly so it can surface
            // staleness rather than silently showing nothing.
            log.default("Reading not usable, state: %{public}@", String(describing: glucose.state))
            delegate.notify { delegate in
                delegate?.cgmManager(self, hasNew: .unreliableData)
            }
            return
        }

        store(glucose)
        deliver([sample])
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didReadBackfill glucose: [Glucose]) {
        let samples = glucose.compactMap { newGlucoseSample(from: $0) }

        guard !samples.isEmpty else {
            return
        }

        log.default("Delivering %d backfill samples", samples.count)
        deliver(samples)
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didReadTransmitterVersion message: TransmitterVersionRxMessage) {
        let firmware = message.firmwareVersion.map(String.init).joined(separator: ".")
        let wasAnubis = state.isAnubis

        mutateState { state in
            state.firmwareVersion = firmware
            state.transmitterExpiryInDays = message.transmitterExpiryInDays
        }

        if state.isAnubis && !wasAnubis {
            log.default("Anubis-modified transmitter detected (expiry %d days)", Int(message.transmitterExpiryInDays))
        }
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didReadTransmitterTime activationDate: Date) {
        // In direct mode this is the proof authentication succeeded; in
        // passive mode it is the first observed time frame. Record it now
        // rather than waiting for a glucose reading: a stopped or failed
        // sensor never produces one, and pairing would appear to hang even
        // though the transmitter is talking.
        log.default("Transmitter clock read; activation %{public}@", String(describing: activationDate))

        mutateState { state in
            state.transmitterStartDate = activationDate
        }
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didReadBattery message: BatteryStatusRxMessage) {
        log.default("Battery: A %d, B %d, resist %d", Int(message.voltageA), Int(message.voltageB), Int(message.resist))

        mutateState { state in
            state.batteryVoltageA = message.voltageA
            state.batteryVoltageB = message.voltageB
            state.batteryResistance = message.resist
            state.batteryRuntimeDays = message.runtime
            state.batteryTemperature = message.temperature
            state.lastBatteryReadDate = Date()
        }

        evaluateAlerts()
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didReadUnknownData data: Data) {
        log.error("Unknown data received (%d bytes)", data.count)
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didUpdatePeripheralIdentifier identifier: UUID?) {
        mutateState { state in
            state.peripheralIdentifier = identifier
        }
    }

    public func transmitterSessionDidRequestBond(_ session: any TransmitterSessioning) {
        log.default("Bond requested; user must accept the pairing prompt")
        connectionPhase = .awaitingPairing
    }

    // MARK: - Session reconciliation

    /// Tracks transmitter/sensor start dates and emits lifecycle events when
    /// they change. A start date differing by more than 15 seconds means a
    /// different session (fact borrowed from xDrip's reconciliation window).
    private func reconcileSession(with glucose: Glucose) {
        let tolerance: TimeInterval = 15

        var events: [PersistedCgmEvent] = []

        let previousTransmitterStart = state.transmitterStartDate
        let previousSensorStart = state.sensorStartDate

        if previousTransmitterStart == nil ||
            abs(previousTransmitterStart!.timeIntervalSince(glucose.activationDate)) > tolerance {
            events.append(PersistedCgmEvent(
                date: glucose.activationDate,
                type: .transmitterStart,
                deviceIdentifier: state.transmitterID,
                expectedLifetime: state.transmitterLifetime
            ))
        }

        if let sessionStart = glucose.sessionStartDate {
            if previousSensorStart == nil ||
                abs(previousSensorStart!.timeIntervalSince(sessionStart)) > tolerance {
                events.append(PersistedCgmEvent(
                    date: sessionStart,
                    type: .sensorStart,
                    deviceIdentifier: state.transmitterID,
                    expectedLifetime: state.sensorLife,
                    warmupPeriod: state.warmupPeriod
                ))
            }
        } else if previousSensorStart != nil {
            // Transmitter reports no session: the sensor was stopped or expired.
            events.append(PersistedCgmEvent(
                date: Date(),
                type: .sensorEnd,
                deviceIdentifier: state.transmitterID,
                failureMessage: String(describing: glucose.state)
            ))
        }

        mutateState { state in
            state.transmitterStartDate = glucose.activationDate
            state.sensorStartDate = glucose.sessionStartDate
            state.algorithmStateRawValue = glucose.calibrationStateRawValue

            // The transmitter's state is the verdict on a start attempt.
            let algorithmState = CalibrationState(rawValue: glucose.calibrationStateRawValue)
            if !algorithmState.isStopped {
                state.lastSessionStartFailure = nil
            } else if let code = self.unverifiedSessionStart, !code.isAccepted {
                state.lastSessionStartFailure = self.describeStartRefusal(code)
            }
            if glucose.sessionStartDate == nil {
                state.sensorCode = nil
            }
        }

        guard !events.isEmpty else {
            return
        }

        // Drop future-dated events; the host's event store rejects them.
        let now = Date()
        let valid = events.filter { $0.date <= now }

        guard !valid.isEmpty else {
            return
        }

        delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: valid)
        }
    }

    private func store(_ glucose: Glucose) {
        guard let value = glucose.glucoseMgDL else {
            return
        }

        let reading = G6StoredReading(
            date: glucose.readDate,
            glucoseMgDL: value,
            trendRateMgDLPerMinute: glucose.trendRateMgDLPerMinute,
            isDisplayOnly: glucose.isDisplayOnly,
            syncIdentifier: syncIdentifier(for: glucose),
            calibrationStateRawValue: glucose.calibrationStateRawValue
        )

        mutateState { state in
            state.latestReading = reading
            state.recentReadings.append(reading)
            if state.recentReadings.count > 100 {
                state.recentReadings.removeFirst(state.recentReadings.count - 100)
            }
        }
    }

    private func deliver(_ samples: [NewGlucoseSample]) {
        delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: .newData(samples))
        }
    }

    /// Stable across live and backfill delivery of the same reading: the
    /// transmitter-relative timestamp is the same in both paths.
    private func syncIdentifier(for glucose: Glucose) -> String {
        return "g6sk-\(state.transmitterID)-\(glucose.transmitterTimestamp)"
    }

    private func newGlucoseSample(from glucose: Glucose) -> NewGlucoseSample? {
        guard let value = glucose.glucoseMgDL else {
            return nil
        }

        // Warm-up readings are not delivered: the transmitter's own algorithm
        // state governs, and dosing on warm-up data is unsafe.
        guard glucose.state.hasReliableGlucose else {
            return nil
        }

        return NewGlucoseSample(
            date: glucose.readDate,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
            condition: glucoseCondition(for: value),
            trend: glucoseTrend(for: glucose),
            trendRate: glucose.trendRateMgDLPerMinute.map {
                HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: $0)
            },
            isDisplayOnly: glucose.isDisplayOnly,
            wasUserEntered: false,
            syncIdentifier: syncIdentifier(for: glucose),
            syncVersion: 1,
            device: device
        )
    }

    private func glucoseCondition(for value: Double) -> GlucoseCondition? {
        // The transmitter clamps to 40…400; report the boundaries as
        // below/above range so the host renders LOW/HIGH rather than a number.
        if value <= 40 {
            return .belowRange
        } else if value >= 400 {
            return .aboveRange
        }
        return nil
    }

    private func glucoseTrend(for glucose: Glucose) -> GlucoseTrend? {
        guard let arrow = G6TrendArrow(dexcomRateMgDLPerMinute: glucose.trendRateMgDLPerMinute) else {
            return nil
        }
        return GlucoseTrend(rawValue: arrow.rawValue)
    }
}


// MARK: - TransmitterCommandSource

extension G6CGMManager: TransmitterCommandSource {

    public func dequeuePendingCommand(for session: any TransmitterSessioning) -> Command? {
        var next: QueuedCommand?
        var dropped: [QueuedCommand] = []
        lockedCommandQueue.mutate { queue in
            (next, dropped) = queue.dequeueEntry()
        }
        lockedInFlightCommand.mutate { $0 = next }

        for entry in dropped {
            log.default("Dropping stale command: %{public}@", String(describing: entry.command))
        }
        if let expired = dropped.last(where: \.notifyIfUndelivered) {
            recordUndelivered(expired, reason: .expired)
        }

        if next != nil || !dropped.isEmpty {
            mutateState { state in
                state.pendingCommands = self.lockedCommandQueue.value.rawValues
            }
        }

        return next?.command
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didFail command: Command, with error: Error) {
        log.error("Command failed: %{public}@ — %{public}@", String(describing: command), String(describing: error))

        // Not retried, whatever the command: by the next connection a stop
        // or start may no longer be what the user wants, and a calibration
        // would no longer match the blood it was measured from.
        var inFlight: QueuedCommand?
        lockedInFlightCommand.mutate { value in
            inFlight = value
            value = nil
        }

        if let entry = inFlight, entry.command == command, entry.notifyIfUndelivered {
            recordUndelivered(entry, reason: .sendFailed)
        }

        if case .startSensor = command {
            // Genuine delivery failures only; a refusal that still produced a
            // session is handled when the transmitter's state arrives.
            let reason = (error as? TransmitterError)?.description ?? String(describing: error)
            mutateState { state in
                state.lastSessionStartFailure = reason
            }
        }
    }

    /// Notes a flagged command that will not reach the transmitter, so the
    /// user is alerted and can decide whether to ask again.
    private func recordUndelivered(_ entry: QueuedCommand, reason: UndeliveredCommand.Reason) {
        log.error("Not delivered (%{public}@): %{public}@", reason.rawValue, String(describing: entry.command))

        // A fresh failure deserves its own alert even if an earlier one is
        // still showing; the host replaces it under the same identifier.
        raisedAlerts.remove(.commandFailed)

        mutateState { state in
            state.undeliveredCommand = UndeliveredCommand(entry: entry, reason: reason)
        }
    }

    public func transmitterSession(_ session: any TransmitterSessioning, didComplete command: Command, response: TransmitterRxMessage?) {
        log.default("Command completed: %{public}@", String(describing: command))
        lockedInFlightCommand.mutate { $0 = nil }

        switch command {
        case .startSensor(_, let sensorCode):
            unverifiedSessionStart = (response as? SessionStartRxMessage)
                .flatMap { SessionStartResponse(rawValue: $0.received) }

            mutateState { state in
                // Recorded on delivery, not on a claimed success: the code was
                // treating a started session as a failure and dropping the
                // sensor code the user had entered.
                state.sensorCode = sensorCode.carriesParameters ? sensorCode.code : nil
                state.lastSessionStartFailure = nil
            }
        case .stopSensor:
            if state.sensorStartDate != nil {
                let sensorEnded = PersistedCgmEvent(
                    date: Date(),
                    type: .sensorEnd,
                    deviceIdentifier: state.transmitterID,
                    failureMessage: LocalizedString("Stopped by user", comment: "Reason recorded when a session ends because the user stopped it")
                )
                delegate.notify { delegate in
                    delegate?.cgmManager(self, hasNew: [sensorEnded])
                }
            }
            mutateState { state in
                state.sensorStartDate = nil
                state.sensorCode = nil
            }
        case .calibrateSensor, .resetTransmitter:
            break
        }
    }
}


// MARK: - GlucoseDisplayable

struct G6GlucoseDisplay: GlucoseDisplayable {
    let reading: G6StoredReading
    let isStale: Bool

    var isStateValid: Bool {
        return !isStale && reading.calibrationState.hasReliableGlucose
    }

    var trendType: GlucoseTrend? {
        guard let arrow = G6TrendArrow(dexcomRateMgDLPerMinute: reading.trendRateMgDLPerMinute) else {
            return nil
        }
        return GlucoseTrend(rawValue: arrow.rawValue)
    }

    var trendRate: HKQuantity? {
        return reading.trendRateMgDLPerMinute.map {
            HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: $0)
        }
    }

    var isLocal: Bool {
        return true
    }

    var glucoseRangeCategory: GlucoseRangeCategory? {
        return nil
    }
}
