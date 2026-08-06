//
//  LocalizedString.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  The core carries no resource bundle on purpose. A SwiftPM package that
//  ships resources produces a separate `.bundle` which is NOT automatically
//  embedded when the package is statically linked into a framework, so
//  `Bundle.module` traps at runtime inside a plugin (documented in
//  LibreLoop/Scripts/generate_project.rb).
//
//  Strings here are developer-facing diagnostics only. All user-facing text
//  is localized by the integration layer, which receives typed values
//  (enums, errors) rather than pre-rendered English.
//

import Foundation

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    return value ?? key
}
