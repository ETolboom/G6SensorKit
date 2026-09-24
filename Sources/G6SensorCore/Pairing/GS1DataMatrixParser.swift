//
//  GS1DataMatrixParser.swift
//  G6SensorKit
//
//  Ported from DexKit (Pairing/GS1DataMatrixParser.swift), trimmed to G6
//  and extended with applicator sensor-code extraction (AI 240) and
//  FNC1-stripped payload fallbacks.
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import Foundation

/// One GS1 element string: application identifier + value.
public struct GS1Element: Equatable {
    public let ai: String
    public let value: String
}

/// Pure GS1 Data Matrix parser for Dexcom packaging barcodes.
///
/// The Data Matrix on Dexcom packaging encodes (GS1 element structure,
/// verified against our own captures of G6/ONE packaging):
///   - AI (01) GTIN: 14 digits; Dexcom company prefix `0038627`
///   - AI (21) serial: G6: 6-char transmitter ID; G7: 12-char sensor serial
///   - AI (240) additional product ID: G6: the 4-digit sensor code on the
///     applicator label; G7: the 4-digit pairing code
///   - AI (10) lot, AI (11) production date, AI (17) expiry
/// Variable-length AIs are terminated by FNC1 (ASCII GS, 0x1D) when more
/// elements follow.
public enum GS1DataMatrixParser {
    /// GS1 FNC1 separator as delivered in scanned payload strings.
    public static let fnc1: Character = "\u{1D}"

    private struct AIInfo {
        let fixedLength: Int?
        let maxLength: Int
    }

    /// AI registry: fixed-length AIs never need a trailing FNC1; variable
    /// ones are read up to FNC1 or end of payload.
    private static let registry: [String: AIInfo] = [
        "01": AIInfo(fixedLength: 14, maxLength: 14), // GTIN
        "11": AIInfo(fixedLength: 6, maxLength: 6), // production date YYMMDD
        "17": AIInfo(fixedLength: 6, maxLength: 6), // expiry YYMMDD
        "10": AIInfo(fixedLength: nil, maxLength: 20), // lot/batch
        "21": AIInfo(fixedLength: nil, maxLength: 20), // serial
        "240": AIInfo(fixedLength: nil, maxLength: 30), // additional product ID (G6 sensor code / G7 pairing code)
        "241": AIInfo(fixedLength: nil, maxLength: 30), // customer part number
        "250": AIInfo(fixedLength: nil, maxLength: 30) // secondary serial
    ]

    /// Parses a scanned payload into GS1 elements. Tolerates the AIM
    /// symbology identifier ("]d1"/"]d2") and/or a leading FNC1 that some
    /// scanners prepend. Stops at the first unrecognized AI and keeps
    /// everything parsed up to that point.
    public static func parse(_ payload: String) -> [GS1Element] {
        var remaining = Substring(normalize(payload))
        var elements: [GS1Element] = []

        while !remaining.isEmpty {
            // Skip stray FNC1 separators (robustness).
            if remaining.first == fnc1 {
                remaining = remaining.dropFirst()
                continue
            }

            guard let (ai, info) = readAI(remaining) else {
                break
            }
            remaining = remaining.dropFirst(ai.count)

            let value: Substring
            if let fixed = info.fixedLength {
                guard remaining.count >= fixed else { break }
                value = remaining.prefix(fixed)
                remaining = remaining.dropFirst(fixed)
            } else {
                let end = remaining.firstIndex(of: fnc1) ?? remaining.endIndex
                value = remaining[..<end]
                remaining = remaining[end...]
                if value.count > info.maxLength {
                    break
                }
            }
            elements.append(GS1Element(ai: ai, value: String(value)))
        }

        return elements
    }

    /// Strips the AIM symbology identifier and any leading FNC1.
    static func normalize(_ payload: String) -> String {
        var s = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("]d") {
            // AIM identifier for Data Matrix: ]d1 = plain, ]d2 = GS1.
            s = String(s.dropFirst(3))
        }
        while s.first == fnc1 {
            s = String(s.dropFirst())
        }
        return s
    }

    /// Longest-match AI read: 4 digits, then 3, then 2.
    private static func readAI(_ s: Substring) -> (String, AIInfo)? {
        for length in [4, 3, 2] {
            guard s.count >= length else { continue }
            let candidate = String(s.prefix(length))
            guard candidate.allSatisfy(\.isNumber) else { continue }
            if let info = registry[candidate] {
                return (candidate, info)
            }
        }
        return nil
    }
}

/// A scanned Dexcom package, mapped to what G6 onboarding needs.
public struct G6PackageScan: Equatable {
    public let elements: [GS1Element]

    /// The normalized payload, kept for the fallback candidate extraction:
    /// some scanners strip the FNC1 separators, leaving one long string the
    /// strict element parse cannot segment.
    private let normalizedPayload: String

    public init(payload: String) {
        normalizedPayload = GS1DataMatrixParser.normalize(payload)
        elements = GS1DataMatrixParser.parse(payload)
    }

    public func value(forAI ai: String) -> String? {
        elements.first(where: { $0.ai == ai })?.value
    }

    /// AI (01); identifies the product model.
    public var gtin: String? { value(forAI: "01") }
    /// AI (10) lot/batch.
    public var lot: String? { value(forAI: "10") }
    /// AI (21); G6: 6-char transmitter ID; G7: 12-char sensor serial.
    public var serial: String? { value(forAI: "21") }

    /// Dexcom's GS1 company prefix (0038627…) inside the GTIN.
    public var isDexcomPackage: Bool {
        gtin?.hasPrefix("0038627") == true
    }

    /// The AI (21) serial as a transmitter ID. Three shapes occur: the
    /// serial is the ID exactly; the ID is followed by a non-alphanumeric
    /// delimiter and trailing packaging data (seen on G6 transmitter boxes:
    /// "<ID>-<batch>"); or the payload lost its FNC1 separators, in which
    /// case the raw payload is scanned for the pattern. A 12-char
    /// alphanumeric G7 serial never matches: the character after the
    /// would-be ID is alphanumeric too. G5 rejection ("4…" prefix) is left
    /// to the entry view, matching how a typed ID is handled.
    public var transmitterIDCandidate: String? {
        if let serial = serial, let id = Self.transmitterIDPrefix(of: serial) {
            return id
        }
        guard isDexcomPackage else { return nil }
        var rest = normalizedPayload[...]
        while let range = rest.range(of: "21") {
            if let id = Self.transmitterIDPrefix(of: String(rest[range.upperBound...])) {
                return id
            }
            rest = rest[range.upperBound...]
        }
        return nil
    }

    /// The AI (240) field as a sensor code. On G6 the applicator's Data
    /// Matrix carries the 4-digit session code there (the field G7 uses
    /// for its pairing code). It is the last element on applicator labels,
    /// so an FNC1-stripped payload is recovered by reading the tail.
    /// Applicator labels carry no GTIN, so unlike the transmitter ID this
    /// is not gated on `isDexcomPackage`. Validity against the known-code
    /// table is left to the entry view, matching a typed code.
    public var sensorCodeCandidate: String? {
        if let pin = value(forAI: "240"), pin.count == 4, pin.allSatisfy(\.isNumber) {
            return pin
        }
        let tail = normalizedPayload.suffix(7)
        guard tail.count == 7,
              tail.hasPrefix("240"),
              tail.dropFirst(3).allSatisfy(\.isNumber)
        else { return nil }
        return String(tail.dropFirst(3))
    }

    /// The leading 6 characters when they are alphanumeric and the string
    /// either ends there or continues with a non-alphanumeric delimiter.
    /// FNC1 does not count as a delimiter: a 6-char run followed by FNC1 is
    /// a complete (21) field the strict parse handles, and in the fallback
    /// scan it is the middle of a longer serial (a G7's 12-char serial
    /// contains "21" six digits in), never a truncated transmitter ID.
    private static func transmitterIDPrefix(of serial: String) -> String? {
        guard serial.count >= 6 else { return nil }
        let prefix = serial.prefix(6)
        guard prefix.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        if serial.count == 6 {
            return prefix.uppercased()
        }
        let next = serial.dropFirst(6).first!
        guard !next.isLetter, !next.isNumber, next != GS1DataMatrixParser.fnc1 else { return nil }
        return prefix.uppercased()
    }
}
