//
//  HKUnit.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  LoopKit's HKUnit extensions are internal-scoped, so each plugin
//  redeclares the units it needs. Matches the pattern in
//  G7SensorKit/Common/HKUnit.swift and LibreLoop/Common/HKUnit.swift.
//

import HealthKit

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }()

    static let millimolesPerLiter: HKUnit = {
        return HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: HKUnit.liter())
    }()

    static let milligramsPerDeciliterPerMinute: HKUnit = {
        return HKUnit.milligramsPerDeciliter.unitDivided(by: .minute())
    }()

    static let millimolesPerLiterPerMinute: HKUnit = {
        return HKUnit.millimolesPerLiter.unitDivided(by: .minute())
    }()

    var localizedShortUnitString: String {
        if self == .millimolesPerLiter {
            return LocalizedString("mmol/L", comment: "The short unit display string for millimoles of glucose per liter")
        } else if self == .milligramsPerDeciliter {
            return LocalizedString("mg/dL", comment: "The short unit display string for milligrams of glucose per deciliter")
        } else {
            return String(describing: self)
        }
    }
}
