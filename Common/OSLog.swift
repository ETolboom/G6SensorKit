//
//  OSLog.swift
//  G6SensorKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log
import G6SensorCore


extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "org.nightscout.G6SensorKit", category: category)
        Self.categoriesLock.lock()
        Self.categories[ObjectIdentifier(self)] = category
        Self.categoriesLock.unlock()
    }

    func debug(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .debug, args)
    }

    func info(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .info, args)
    }

    func `default`(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .default, args)
    }

    func error(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .error, args)
    }

    private func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        mirrorToFile(message, type: type, args)

        switch args.count {
        case 0:
            os_log(message, log: self, type: type)
        case 1:
            os_log(message, log: self, type: type, args[0])
        case 2:
            os_log(message, log: self, type: type, args[0], args[1])
        case 3:
            os_log(message, log: self, type: type, args[0], args[1], args[2])
        case 4:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3])
        case 5:
            os_log(message, log: self, type: type, args[0], args[1], args[2], args[3], args[4])
        default:
            os_log(message, log: self, type: type, args)
        }
    }

    /// Category this logger was created with, so file lines can be attributed.
    /// OSLog does not expose it, so it is captured on init.
    private static let categoriesLock = NSLock()
    private static var categories: [ObjectIdentifier: String] = [:]

    var loggerCategory: String {
        Self.categoriesLock.lock()
        defer { Self.categoriesLock.unlock() }
        return Self.categories[ObjectIdentifier(self)] ?? "G6SensorKit"
    }

    /// Mirrors every OSLog line into the exportable file log. Format
    /// specifiers are OSLog-flavoured (%{public}@), so the privacy qualifier
    /// is stripped before String(format:) sees them.
    private func mirrorToFile(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        let template = "\(message)"
            .replacingOccurrences(of: "%{public}", with: "%")
            .replacingOccurrences(of: "%{private}", with: "%")
        let rendered = args.isEmpty ? template : String(format: template, arguments: args)

        let level: String
        switch type {
        case .debug: level = "DEBUG"
        case .info: level = "INFO"
        case .error, .fault: level = "ERROR"
        default: level = "DEFAULT"
        }

        G6Logger.shared.write(category: loggerCategory, level: level, message: rendered)
    }
}
