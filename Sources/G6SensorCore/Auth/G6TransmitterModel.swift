//
//  G6TransmitterModel.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import Foundation

/// The G6-family model, classified from the transmitter ID the user entered.
public enum G6TransmitterModel: CaseIterable {
    case g6
    case one

    /// Dexcom ONE transmitters use `5…` or `C…`; G6 uses `8…`. An unrecognized
    /// prefix falls back to G6, the stock case.
    public init(transmitterID: String) {
        switch transmitterID.first {
        case "5",
             "c",
             "C":
            self = .one
        default:
            self = .g6
        }
    }
}
