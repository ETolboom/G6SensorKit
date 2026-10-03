//
//  CommandQueue.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import Foundation

/// A command waiting in the queue, with what the queue needs to know about
/// its delivery.
public struct QueuedCommand: Equatable {
    public let command: Command

    /// When the user asked for it.
    public let queuedAt: Date

    /// Whether the user must hear about it if it does not get through. Set
    /// for commands whose silent loss leaves the user believing something
    /// happened that did not — a session they think they stopped carries on.
    ///
    /// It never causes a retry. A failed or expired command is gone, and the
    /// user decides whether to send it again: a calibration in particular
    /// must not reach the transmitter later than the fingerstick it came from.
    public let notifyIfUndelivered: Bool

    public init(_ command: Command, queuedAt: Date = Date(), notifyIfUndelivered: Bool = false) {
        self.command = command
        self.queuedAt = queuedAt
        self.notifyIfUndelivered = notifyIfUndelivered
    }

    /// The command's own keys plus the delivery bookkeeping. Command ignores
    /// keys it does not know, and entries persisted before these existed
    /// read back as unflagged.
    public init?(rawValue: Command.RawValue) {
        guard let command = Command(rawValue: rawValue) else {
            return nil
        }
        self.init(
            command,
            queuedAt: rawValue["queuedAt"] as? Date ?? Date(),
            notifyIfUndelivered: rawValue["notifyIfUndelivered"] as? Bool ?? false
        )
    }

    public var rawValue: Command.RawValue {
        var raw = command.rawValue
        raw["queuedAt"] = queuedAt
        if notifyIfUndelivered {
            raw["notifyIfUndelivered"] = true
        }
        return raw
    }

    /// A flagged command still waiting long enough that it is not just the
    /// usual gap between connections. It is still queued and goes out the
    /// first time the transmitter connects; this only says the user should
    /// know it has not yet.
    public func isDelayed(now: Date = Date()) -> Bool {
        guard notifyIfUndelivered else {
            return false
        }
        return now.timeIntervalSince(queuedAt) > CommandQueue.delayedInterval
    }
}

/// A flagged command that left the queue without reaching the transmitter.
/// Kept so the user can be told and can act on it; the command itself is
/// never sent again.
public struct UndeliveredCommand: Equatable {
    public enum Reason: String {
        /// The send was attempted and broke down in transit.
        case sendFailed
        /// It outlived its usefulness while waiting — a calibration older
        /// than the stale window — and was dropped unsent.
        case expired
    }

    public let entry: QueuedCommand
    public let reason: Reason
    public let date: Date

    /// The user has seen the alert. The alert is not raised again, though a
    /// stop or start that is still wrong stays visible in settings.
    public var acknowledged: Bool

    public init(entry: QueuedCommand, reason: Reason, date: Date = Date(), acknowledged: Bool = false) {
        self.entry = entry
        self.reason = reason
        self.date = date
        self.acknowledged = acknowledged
    }

    public init?(rawValue: [String: Any]) {
        guard
            let entryRaw = rawValue["entry"] as? Command.RawValue,
            let entry = QueuedCommand(rawValue: entryRaw),
            let reason = (rawValue["reason"] as? String).flatMap(Reason.init(rawValue:)),
            let date = rawValue["date"] as? Date
        else {
            return nil
        }
        self.init(entry: entry, reason: reason, date: date, acknowledged: rawValue["acknowledged"] as? Bool ?? false)
    }

    public var rawValue: [String: Any] {
        [
            "entry": entry.rawValue,
            "reason": reason.rawValue,
            "date": date,
            "acknowledged": acknowledged
        ]
    }
}

/// A persisted queue of transmitter commands awaiting the next connection.
///
/// Pure value logic, extracted from the G6 manager so the supersede and
/// stale-drop rules can be tested without LoopKit. The manager mirrors
/// `rawValues` into its persisted state so queued commands survive relaunch.
public struct CommandQueue: Equatable {

    public static let staleCalibrationInterval: TimeInterval = .minutes(5)

    /// Three missed connection cycles. One missed cycle is ordinary; three
    /// in a row means something is wrong with the link.
    public static let delayedInterval: TimeInterval = .minutes(15)

    public private(set) var entries: [QueuedCommand]

    public var commands: [Command] {
        entries.map(\.command)
    }

    public init(_ entries: [QueuedCommand] = []) {
        self.entries = entries
    }

    public init(_ commands: [Command]) {
        self.init(commands.map { QueuedCommand($0) })
    }

    public init(rawValues: [Command.RawValue]) {
        self.init(rawValues.compactMap(QueuedCommand.init(rawValue:)))
    }

    public var rawValues: [Command.RawValue] {
        entries.map(\.rawValue)
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Queues a command for the next connection cycle. Newest wins: any
    /// queued command the new one supersedes is dropped first, so repeated
    /// trips through setup cannot stack session starts.
    ///
    /// - Parameter notifyIfUndelivered: tell the user if the command is
    ///   delayed, fails to send or expires unsent. Never causes a retry.
    /// - Returns: the number of queued commands the new one replaced.
    @discardableResult public mutating func enqueue(_ command: Command, notifyIfUndelivered: Bool = false, now: Date = Date()) -> Int {
        let before = entries.count
        entries.removeAll { $0.command.supersededBy(command) }
        let superseded = before - entries.count
        entries.append(QueuedCommand(command, queuedAt: now, notifyIfUndelivered: notifyIfUndelivered))
        return superseded
    }

    /// Pops the next command to send, silently dropping stale calibrations.
    ///
    /// - Returns: the command to send, plus any commands dropped as stale
    ///   (for logging).
    public mutating func dequeue(now: Date = Date()) -> (next: Command?, dropped: [Command]) {
        let (next, dropped) = dequeueEntry(now: now)
        return (next?.command, dropped.map(\.command))
    }

    /// As `dequeue`, keeping the delivery bookkeeping so the caller can tell
    /// the user about a flagged command that is dropped or fails.
    public mutating func dequeueEntry(now: Date = Date()) -> (next: QueuedCommand?, dropped: [QueuedCommand]) {
        var dropped: [QueuedCommand] = []
        var next: QueuedCommand?
        while let candidate = entries.first {
            entries.removeFirst()
            if case let .calibrateSensor(_, date) = candidate.command,
               now.timeIntervalSince(date) > Self.staleCalibrationInterval
            {
                dropped.append(candidate)
                continue
            }
            next = candidate
            break
        }
        return (next, dropped)
    }

    /// The first flagged command that has waited long enough to tell the
    /// user about.
    public func firstDelayed(now: Date = Date()) -> QueuedCommand? {
        entries.first { $0.isDelayed(now: now) }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
