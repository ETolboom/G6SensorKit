//
//  CommandQueue.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import Foundation

/// A persisted queue of transmitter commands awaiting the next connection.
///
/// Pure value logic, extracted from the G6 manager so the supersede and
/// stale-drop rules can be tested without LoopKit. The manager mirrors
/// `rawValues` into its persisted state so queued commands survive relaunch.
public struct CommandQueue: Equatable {

    public static let staleCalibrationInterval: TimeInterval = .minutes(5)

    public private(set) var commands: [Command]

    public init(_ commands: [Command] = []) {
        self.commands = commands
    }

    public init(rawValues: [Command.RawValue]) {
        self.init(rawValues.compactMap(Command.init(rawValue:)))
    }

    public var rawValues: [Command.RawValue] {
        commands.map(\.rawValue)
    }

    public var isEmpty: Bool {
        commands.isEmpty
    }

    /// Queues a command for the next connection cycle. Newest wins: any
    /// queued command the new one supersedes is dropped first, so repeated
    /// trips through setup cannot stack session starts.
    ///
    /// - Returns: the number of queued commands the new one replaced.
    @discardableResult public mutating func enqueue(_ command: Command) -> Int {
        let before = commands.count
        commands.removeAll { $0.supersededBy(command) }
        let superseded = before - commands.count
        commands.append(command)
        return superseded
    }

    /// Pops the next command to send, silently dropping stale calibrations.
    ///
    /// - Returns: the command to send, plus any commands dropped as stale
    ///   (for logging).
    public mutating func dequeue(now: Date = Date()) -> (next: Command?, dropped: [Command]) {
        var dropped: [Command] = []
        var next: Command?
        while let candidate = commands.first {
            commands.removeFirst()
            if case let .calibrateSensor(_, date) = candidate,
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

    public mutating func removeAll() {
        commands.removeAll()
    }
}
