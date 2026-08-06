//
//  G6Logger.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Modeled on EversenseKit's logger: everything goes to OSLog *and* to a
//  daily-rotated file the user can export from settings. OSLog alone is not
//  much use once someone is out in the field with a transmitter that
//  misbehaved an hour ago — the file is what ends up attached to a report.
//
//  Lives in the core so the transport and session layers can log without
//  depending on LoopKit, and so every layer writes to one file.
//

import Foundation
import os.log

public final class G6Logger {

    public static let shared = G6Logger()

    private let fileManager = FileManager.default

    /// Serialises appends; BLE callbacks arrive on their own queues.
    private let queue = DispatchQueue(label: "org.nightscout.G6SensorKit.logger", qos: .utility)

    private init() {}

    // MARK: - Writing

    public func write(category: String, level: String, message: String) {
        let stamp = Self.dateFormatter.string(from: Date())
        let line = "[\(stamp) \(level)] [\(category)] \(message)\n"

        queue.async { [weak self] in
            self?.append(line)
        }
    }

    private func append(_ line: String) {
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }

        // Roll over at the start of each day, keeping one previous file.
        if !fileManager.fileExists(atPath: logFile.path) {
            createLogFile()
        } else if let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
                  let created = attributes[.creationDate] as? Date,
                  created < Calendar.current.startOfDay(for: Date()) {
            try? fileManager.removeItem(at: previousLogFile)
            try? fileManager.moveItem(at: logFile, to: previousLogFile)
            createLogFile()
        }

        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFile, options: .atomic)
        }
    }

    private func createLogFile() {
        fileManager.createFile(
            atPath: logFile.path,
            contents: nil,
            attributes: [.creationDate: Calendar.current.startOfDay(for: Date())]
        )
    }

    // MARK: - Export

    /// Current and previous log files, for sharing from settings.
    public func debugLogURLs() -> [URL] {
        // Flush anything still queued so the export is not missing the tail.
        queue.sync {}

        return [logFile, previousLogFile].filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func deleteLogs() {
        queue.sync {
            try? fileManager.removeItem(at: logFile)
            try? fileManager.removeItem(at: previousLogFile)
        }
    }

    // MARK: - Locations

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var logDirectory: URL {
        documentsDirectory.appendingPathComponent("g6sensorkit", isDirectory: true)
    }

    private var logFile: URL {
        logDirectory.appendingPathComponent("g6sensorkit_log.txt")
    }

    private var previousLogFile: URL {
        logDirectory.appendingPathComponent("g6sensorkit_log_prev.txt")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
}
