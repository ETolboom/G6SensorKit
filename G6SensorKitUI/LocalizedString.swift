//
//  LocalizedString.swift
//  G6SensorKitUI
//
//  Adapted for G6SensorKit from CGMBLEKit/Common (LoopUI),
//  created by Kathryn DiSimone on 8/15/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved. (MIT License)
//
//  Each framework resolves strings against its own bundle; mirrors
//  G7SensorKitUI.LocalizedString.
//

import Foundation

private class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value = value {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, comment: comment)
    }
}
