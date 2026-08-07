//
//  SensorCode.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  The 4-digit factory sensor code printed on the G6/ONE applicator maps to a
//  pair of calibration parameters that are sent with the session-start
//  command. The parameter values are protocol facts observable on the wire,
//  cross-checked against the xDrip4iOS and xDrip+ (Android) projects, which
//  document rather than originate them. No code from either is included.
//

import Foundation

public struct SensorCode: Equatable {
    public let code: String
    let parameter1: Int16
    let parameter2: Int16

    /// The "no code" sentinel: the transmitter runs the session without
    /// factory calibration and will request fingerstick calibrations.
    public static let none = SensorCode(code: "0000", parameter1: 0, parameter2: 0)

    /// Each parameter pair is reachable from exactly two printed codes.
    private static let parametersByCode: [String: (Int16, Int16)] = {
        let pairs: [(codes: [String], parameters: (Int16, Int16))] = [
            (["5915", "9759"], (3100, 3600)),
            (["5917", "9357"], (3000, 3500)),
            (["5931", "9137"], (2900, 3400)),
            (["5937", "7197"], (2800, 3300)),
            (["5951", "9517"], (3100, 3500)),
            (["5955", "9179"], (3000, 3400)),
            (["7171", "7539"], (2700, 3300)),
            (["9117", "7135"], (2700, 3200)),
            (["9159", "5397"], (2600, 3200)),
            (["9311", "5391"], (2600, 3100)),
            (["9371", "5375"], (2500, 3100)),
            (["9515", "5795"], (2500, 3000)),
            (["9551", "5317"], (2400, 3000)),
            (["9577", "5177"], (2400, 2900)),
            (["9713", "5171"], (2300, 2900)),
        ]

        var map: [String: (Int16, Int16)] = [:]
        for entry in pairs {
            for code in entry.codes {
                map[code] = entry.parameters
            }
        }
        return map
    }()

    /// Returns nil for a code that is not a known factory sensor code.
    /// Pass nil or "0000" for a code-less session start.
    public init?(_ code: String?) {
        guard let code = code, code != Self.none.code else {
            self = .none
            return
        }

        guard let parameters = Self.parametersByCode[code] else {
            return nil
        }

        self.init(code: code, parameter1: parameters.0, parameter2: parameters.1)
    }

    private init(code: String, parameter1: Int16, parameter2: Int16) {
        self.code = code
        self.parameter1 = parameter1
        self.parameter2 = parameter2
    }

    /// Whether this code carries factory calibration parameters.
    public var carriesParameters: Bool {
        return parameter1 != 0
    }
}
