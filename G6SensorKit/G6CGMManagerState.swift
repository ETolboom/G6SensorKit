//
//  G6CGMManagerState.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Persistence conventions follow LibreLoop's state layer: schema-migration
//  key fallbacks, numeric-width bridging (UserDefaults cannot hold UInt16),
//  bounded collections, and sparse writes. No secrets are stored here —
//  optional Dexcom Share credentials live in the Keychain.
//

import Foundation
import G6SensorCore

/// How far setup got. Persisted so an interrupted setup resumes where the
/// user left off instead of restarting from the introduction — the
/// coordinator is rebuilt whenever the host re-presents the UI, so this
/// cannot live in memory.
public enum G6SetupStep: String {
    case transmitterID
    case placement
    case sensorCode
    case pairing
    case warmup
}

public struct G6CGMManagerState: RawRepresentable {
    public typealias RawValue = [String: Any]

    public static let version = 1

    /// Stock G6 warm-up; Anubis-modded transmitters warm up faster.
    public static let stockWarmupPeriod: TimeInterval = .hours(2)
    public static let anubisWarmupPeriod: TimeInterval = .minutes(50)

    /// Stock G6 transmitter lifetime; Anubis reports 180 days.
    public static let stockTransmitterLifetime: TimeInterval = .hours(24 * 100)
    public static let anubisTransmitterLifetime: TimeInterval = .hours(24 * 180)

    /// Cap on readings persisted in rawState (in-memory list may be longer).
    static let recentReadingsPersistenceCap = 12

    public var transmitterID: String

    /// Persisted so the peripheral can be re-acquired without a fresh scan
    /// after each app launch.
    public var peripheralIdentifier: UUID?

    public var transmitterStartDate: Date?

    public var sensorStartDate: Date?

    /// The factory sensor code entered for the current session, if any.
    public var sensorCode: String?

    public var shouldSyncToRemoteService: Bool

    /// Transmitter-reported lifetime in days (90 stock, 180 Anubis); nil until
    /// the first version-rx frame arrives.
    public var transmitterExpiryInDays: UInt16?

    /// User-configured session length; honored only for Anubis.
    public var sensorLifeDays: Int

    public var latestReading: G6StoredReading?

    public var recentReadings: [G6StoredReading]

    /// Firmware version string from the transmitter version response.
    public var firmwareVersion: String?

    /// Whether optional Dexcom Share upload is enabled. The credentials
    /// themselves are never stored here — see G6ShareCredentialStore.
    public var shareUploadEnabled: Bool

    public var isOnboarded: Bool

    /// Resume point for an interrupted setup; nil once onboarding finishes.
    public var setupStep: G6SetupStep?

    /// The transmitter's own algorithm state from the most recent reading.
    /// A session can be running while the time message still reports no
    /// session start — during warm-up, notably — so session presence is
    /// taken from here rather than from the start date alone.
    public var algorithmStateRawValue: UInt8?

    /// Why the last attempt to start a sensor failed, if it did. Kept so the
    /// UI can explain a refusal instead of showing "No Sensor" as though
    /// nothing had been tried.
    public var lastSessionStartFailure: String?

    /// Commands waiting for the next connection. Persisted because the
    /// transmitter may be minutes away and the user's entered sensor code or
    /// calibration must not vanish if the app is relaunched meanwhile.
    public var pendingCommands: [Command.RawValue]

    // MARK: - Battery

    /// Hundredths of a volt (310 is 3.10 V).
    public var batteryVoltageA: UInt16?
    public var batteryVoltageB: UInt16?
    public var batteryResistance: UInt16?
    public var batteryRuntimeDays: Int?
    public var batteryTemperature: Int?
    public var lastBatteryReadDate: Date?

    public var batteryVoltageAMillivolts: Int? {
        return batteryVoltageA.map { Int($0) * 10 }
    }

    public var batteryVoltageBMillivolts: Int? {
        return batteryVoltageB.map { Int($0) * 10 }
    }

    /// Battery B gives out first.
    public static let batteryLowMillivolts = 2750
    public static let batteryVeryLowMillivolts = 2700

    public var isBatteryLow: Bool {
        guard let millivolts = batteryVoltageBMillivolts else {
            return false
        }
        return millivolts <= Self.batteryLowMillivolts
    }

    public var isBatteryVeryLow: Bool {
        guard let millivolts = batteryVoltageBMillivolts else {
            return false
        }
        return millivolts <= Self.batteryVeryLowMillivolts
    }

    /// Headline battery level for the settings row.
    public enum BatteryLevel {
        case unknown, high, low, veryLow
    }

    public var batteryLevel: BatteryLevel {
        guard let millivolts = batteryVoltageBMillivolts else {
            return .unknown
        }
        if millivolts <= Self.batteryVeryLowMillivolts {
            return .veryLow
        }
        if millivolts <= Self.batteryLowMillivolts {
            return .low
        }
        return .high
    }

    public init(
        transmitterID: String,
        peripheralIdentifier: UUID? = nil,
        transmitterStartDate: Date? = nil,
        sensorStartDate: Date? = nil,
        sensorCode: String? = nil,
        shouldSyncToRemoteService: Bool = true,
        transmitterExpiryInDays: UInt16? = nil,
        sensorLifeDays: Int = TransmitterManagerState.defaultSensorLifeDays,
        latestReading: G6StoredReading? = nil,
        recentReadings: [G6StoredReading] = [],
        firmwareVersion: String? = nil,
        shareUploadEnabled: Bool = false,
        isOnboarded: Bool = false,
        setupStep: G6SetupStep? = nil,
        pendingCommands: [Command.RawValue] = [],
        lastSessionStartFailure: String? = nil,
        algorithmStateRawValue: UInt8? = nil
    ) {
        self.transmitterID = transmitterID
        self.peripheralIdentifier = peripheralIdentifier
        self.transmitterStartDate = transmitterStartDate
        self.sensorStartDate = sensorStartDate
        self.sensorCode = sensorCode
        self.shouldSyncToRemoteService = shouldSyncToRemoteService
        self.transmitterExpiryInDays = transmitterExpiryInDays
        self.sensorLifeDays = TransmitterManagerState.clampedSensorLifeDays(sensorLifeDays)
        self.latestReading = latestReading
        self.recentReadings = recentReadings
        self.firmwareVersion = firmwareVersion
        self.shareUploadEnabled = shareUploadEnabled
        self.isOnboarded = isOnboarded
        self.setupStep = setupStep
        self.pendingCommands = pendingCommands
        self.lastSessionStartFailure = lastSessionStartFailure
        self.algorithmStateRawValue = algorithmStateRawValue
    }

    public init?(rawValue: RawValue) {
        guard let transmitterID = rawValue["transmitterID"] as? String else {
            return nil
        }

        // UInt16 cannot round-trip through a property list, so accept Int too.
        let expiry = (rawValue["transmitterExpiryInDays"] as? UInt16)
            ?? (rawValue["transmitterExpiryInDays"] as? Int).map { UInt16(clamping: $0) }

        self.init(
            transmitterID: transmitterID,
            peripheralIdentifier: (rawValue["peripheralIdentifier"] as? String).flatMap(UUID.init(uuidString:)),
            transmitterStartDate: rawValue["transmitterStartDate"] as? Date,
            sensorStartDate: rawValue["sensorStartDate"] as? Date,
            sensorCode: rawValue["sensorCode"] as? String,
            shouldSyncToRemoteService: rawValue["shouldSyncToRemoteService"] as? Bool ?? true,
            transmitterExpiryInDays: expiry,
            sensorLifeDays: rawValue["sensorLifeDays"] as? Int ?? TransmitterManagerState.defaultSensorLifeDays,
            latestReading: (rawValue["latestReading"] as? G6StoredReading.RawValue).flatMap(G6StoredReading.init(rawValue:)),
            recentReadings: (rawValue["recentReadings"] as? [G6StoredReading.RawValue])?.compactMap(G6StoredReading.init(rawValue:)) ?? [],
            firmwareVersion: rawValue["firmwareVersion"] as? String,
            shareUploadEnabled: rawValue["shareUploadEnabled"] as? Bool ?? false,
            isOnboarded: rawValue["isOnboarded"] as? Bool ?? false,
            setupStep: (rawValue["setupStep"] as? String).flatMap(G6SetupStep.init(rawValue:)),
            pendingCommands: rawValue["pendingCommands"] as? [Command.RawValue] ?? [],
            lastSessionStartFailure: rawValue["lastSessionStartFailure"] as? String,
            algorithmStateRawValue: (rawValue["algorithmState"] as? Int).map { UInt8(clamping: $0) }
        )

        batteryVoltageA = (rawValue["batteryVoltageA"] as? Int).map { UInt16(clamping: $0) }
        batteryVoltageB = (rawValue["batteryVoltageB"] as? Int).map { UInt16(clamping: $0) }
        batteryResistance = (rawValue["batteryResistance"] as? Int).map { UInt16(clamping: $0) }
        batteryRuntimeDays = rawValue["batteryRuntimeDays"] as? Int
        batteryTemperature = rawValue["batteryTemperature"] as? Int
        lastBatteryReadDate = rawValue["lastBatteryReadDate"] as? Date
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "transmitterID": transmitterID,
            "shouldSyncToRemoteService": shouldSyncToRemoteService,
            "sensorLifeDays": sensorLifeDays,
        ]

        raw["peripheralIdentifier"] = peripheralIdentifier?.uuidString
        raw["transmitterStartDate"] = transmitterStartDate
        raw["sensorStartDate"] = sensorStartDate
        raw["sensorCode"] = sensorCode
        raw["transmitterExpiryInDays"] = transmitterExpiryInDays.map { Int($0) }
        raw["latestReading"] = latestReading?.rawValue
        raw["firmwareVersion"] = firmwareVersion

        if !recentReadings.isEmpty {
            raw["recentReadings"] = recentReadings.suffix(Self.recentReadingsPersistenceCap).map { $0.rawValue }
        }

        // Sparse writes: only persist flags when set.
        if shareUploadEnabled {
            raw["shareUploadEnabled"] = true
        }
        if isOnboarded {
            raw["isOnboarded"] = true
        }
        raw["setupStep"] = setupStep?.rawValue
        if !pendingCommands.isEmpty {
            raw["pendingCommands"] = pendingCommands
        }
        raw["lastSessionStartFailure"] = lastSessionStartFailure
        raw["algorithmState"] = algorithmStateRawValue.map { Int($0) }

        raw["batteryVoltageA"] = batteryVoltageA.map { Int($0) }
        raw["batteryVoltageB"] = batteryVoltageB.map { Int($0) }
        raw["batteryResistance"] = batteryResistance.map { Int($0) }
        raw["batteryRuntimeDays"] = batteryRuntimeDays
        raw["batteryTemperature"] = batteryTemperature
        raw["lastBatteryReadDate"] = lastBatteryReadDate

        return raw
    }

    // MARK: - Derived lifecycle values

    /// `true` once the transmitter reports the Anubis 180-day lifetime.
    public var isAnubis: Bool {
        return transmitterExpiryInDays == 180
    }

    public var warmupPeriod: TimeInterval {
        return isAnubis ? Self.anubisWarmupPeriod : Self.stockWarmupPeriod
    }

    /// The transmitter reports its own lifetime in the version response, and
    /// that is authoritative — a field unit reported 110 days, which matches
    /// neither the stock assumption of 100 nor the Anubis 180. The constants
    /// are only a fallback for before the first version read.
    public var transmitterLifetime: TimeInterval {
        if let days = transmitterExpiryInDays, days > 0 {
            return .hours(24 * Double(days))
        }
        return isAnubis ? Self.anubisTransmitterLifetime : Self.stockTransmitterLifetime
    }

    /// The transmitter is running a session, whether or not it has told us
    /// when it started. Anything other than stopped counts.
    public var hasActiveSession: Bool {
        if sensorStartDate != nil {
            return true
        }
        guard let raw = algorithmStateRawValue else {
            return false
        }
        let state = CalibrationState(rawValue: raw)
        return !state.isStopped && raw != 0
    }

    /// A session is running but the transmitter has not reported a start
    /// time, so elapsed and remaining time cannot be shown.
    public var hasSessionWithUnknownStart: Bool {
        return hasActiveSession && sensorStartDate == nil
    }

    /// Past its reported lifetime. An expired transmitter still authenticates
    /// and answers reads, but refuses to start a new sensor session.
    public var isTransmitterExpired: Bool {
        guard let expiration = transmitterExpirationDate else {
            return false
        }
        return expiration < Date()
    }

    /// Session length: user-configured for Anubis, otherwise the stock 10 days.
    public var sensorLife: TimeInterval {
        return .hours(24 * Double(isAnubis ? sensorLifeDays : TransmitterManagerState.defaultSensorLifeDays))
    }

    public var sensorExpirationDate: Date? {
        return sensorStartDate?.addingTimeInterval(sensorLife)
    }

    /// Unknown until the first version read: the fallback constants in
    /// `transmitterLifetime` are guesses (a 180-day Anubis would alert as
    /// "expired" against the stock 90 days), so no expiry is reported before
    /// the transmitter's own value is in.
    public var transmitterExpirationDate: Date? {
        guard transmitterExpiryInDays != nil else {
            return nil
        }
        return transmitterStartDate?.addingTimeInterval(transmitterLifetime)
    }

    public var isInWarmup: Bool {
        guard let sensorStartDate = sensorStartDate else {
            return false
        }
        return Date().timeIntervalSince(sensorStartDate) < warmupPeriod
    }

    public var warmupEndDate: Date? {
        return sensorStartDate?.addingTimeInterval(warmupPeriod)
    }

    /// A session start is queued but the transmitter has not acknowledged it
    /// yet, so there is no start date to judge warm-up by — it is about to
    /// begin rather than already running.
    public var hasPendingSessionStart: Bool {
        return pendingCommands.contains { raw in
            if case .startSensor? = Command(rawValue: raw) {
                return true
            }
            return false
        }
    }

    /// The device model implied by the transmitter ID prefix. G6 transmitters
    /// use `8…`; Dexcom ONE uses `5…` or `C…`.
    public var deviceModel: String {
        switch G6TransmitterModel(transmitterID: transmitterID) {
        case .g6: return "Dexcom G6"
        case .one: return "Dexcom ONE"
        }
    }
}


/// A glucose reading reduced to what needs persisting.
public struct G6StoredReading: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public let date: Date
    public let glucoseMgDL: Double
    public let trendRateMgDLPerMinute: Double?
    public let isDisplayOnly: Bool
    public let syncIdentifier: String
    public let calibrationStateRawValue: UInt8

    public init(date: Date, glucoseMgDL: Double, trendRateMgDLPerMinute: Double?, isDisplayOnly: Bool, syncIdentifier: String, calibrationStateRawValue: UInt8) {
        self.date = date
        self.glucoseMgDL = glucoseMgDL
        self.trendRateMgDLPerMinute = trendRateMgDLPerMinute
        self.isDisplayOnly = isDisplayOnly
        self.syncIdentifier = syncIdentifier
        self.calibrationStateRawValue = calibrationStateRawValue
    }

    public init?(rawValue: RawValue) {
        guard let date = rawValue["date"] as? Date,
              let glucoseMgDL = rawValue["glucoseMgDL"] as? Double,
              let syncIdentifier = rawValue["syncIdentifier"] as? String
        else {
            return nil
        }

        self.init(
            date: date,
            glucoseMgDL: glucoseMgDL,
            trendRateMgDLPerMinute: rawValue["trendRateMgDLPerMinute"] as? Double,
            isDisplayOnly: rawValue["isDisplayOnly"] as? Bool ?? false,
            syncIdentifier: syncIdentifier,
            calibrationStateRawValue: (rawValue["calibrationState"] as? Int).map { UInt8(clamping: $0) } ?? 0
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "date": date,
            "glucoseMgDL": glucoseMgDL,
            "syncIdentifier": syncIdentifier,
            "calibrationState": Int(calibrationStateRawValue),
        ]
        raw["trendRateMgDLPerMinute"] = trendRateMgDLPerMinute
        if isDisplayOnly {
            raw["isDisplayOnly"] = true
        }
        return raw
    }

    public var calibrationState: CalibrationState {
        return CalibrationState(rawValue: calibrationStateRawValue)
    }
}

// [String: Any] is not Equatable, so the conformance is written out. The
// change detection in the manager depends on it: without it every state
// write would notify observers and re-persist.
extension G6CGMManagerState: Equatable {
    public static func == (lhs: G6CGMManagerState, rhs: G6CGMManagerState) -> Bool {
        return lhs.transmitterID == rhs.transmitterID
            && lhs.peripheralIdentifier == rhs.peripheralIdentifier
            && lhs.transmitterStartDate == rhs.transmitterStartDate
            && lhs.sensorStartDate == rhs.sensorStartDate
            && lhs.sensorCode == rhs.sensorCode
            && lhs.shouldSyncToRemoteService == rhs.shouldSyncToRemoteService
            && lhs.transmitterExpiryInDays == rhs.transmitterExpiryInDays
            && lhs.sensorLifeDays == rhs.sensorLifeDays
            && lhs.latestReading == rhs.latestReading
            && lhs.recentReadings == rhs.recentReadings
            && lhs.firmwareVersion == rhs.firmwareVersion
            && lhs.shareUploadEnabled == rhs.shareUploadEnabled
            && lhs.isOnboarded == rhs.isOnboarded
            && lhs.setupStep == rhs.setupStep
            && lhs.lastSessionStartFailure == rhs.lastSessionStartFailure
            && lhs.algorithmStateRawValue == rhs.algorithmStateRawValue
            && lhs.batteryVoltageA == rhs.batteryVoltageA
            && lhs.batteryVoltageB == rhs.batteryVoltageB
            && lhs.batteryResistance == rhs.batteryResistance
            && lhs.batteryRuntimeDays == rhs.batteryRuntimeDays
            && lhs.batteryTemperature == rhs.batteryTemperature
            && lhs.lastBatteryReadDate == rhs.lastBatteryReadDate
            && NSArray(array: lhs.pendingCommands) == NSArray(array: rhs.pendingCommands)
    }
}
