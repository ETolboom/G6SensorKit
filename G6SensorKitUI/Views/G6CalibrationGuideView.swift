//
//  G6CalibrationGuideView.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  "How to calibrate" deck, built the same way as the apply-sensor guide.
//  Steps and tips follow the Dexcom G6 user guide, Chapter 7 (Calibrate):
//  wash hands properly, use a fingertip sample, and enter the exact meter
//  value promptly. Getting these wrong is the most common cause of a bad
//  calibration, so the guide leads with them.
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit

enum G6CalibrationSteps {

    static var all: [G6ApplyStep] {
        let section = LocalizedString("CALIBRATE", comment: "Section label for the calibration steps")
        func title(_ n: Int) -> String {
            String(format: LocalizedString("STEP %d of 3", comment: "Calibration step counter (1: step number)"), n)
        }
        return [
            G6ApplyStep(
                title: title(1), section: section, assetName: "G6CalibrateStep1",
                body: LocalizedString("Wash and dry your hands with soap and water — not a gel cleaner.", comment: "Calibration step 1 body"),
                note: LocalizedString("Poorly washed hands are behind most inaccurate meter readings, and an inaccurate reading teaches the sensor the wrong thing.", comment: "Calibration step 1 note")
            ),
            G6ApplyStep(
                title: title(2), section: section, assetName: "G6CalibrateStep2",
                body: LocalizedString("Take a blood sample from your fingertip and measure it with your meter.", comment: "Calibration step 2 body"),
                note: LocalizedString("Use a fingertip only — samples from other sites are less accurate. Use the same meter throughout a sensor session, and check that your strips are in date.", comment: "Calibration step 2 note")
            ),
            G6ApplyStep(
                title: title(3), section: section, assetName: "",
                body: LocalizedString("Enter the exact value your meter showed, within 5 minutes of the fingerstick.", comment: "Calibration step 3 body"),
                note: LocalizedString("Do not round the number or reuse an older reading. If more than 5 minutes have passed, measure again.", comment: "Calibration step 3 note")
            )
        ]
    }
}

struct G6CalibrationGuideView: View {
    let onDone: () -> Void

    private let steps = G6CalibrationSteps.all

    var body: some View {
        NavigationView {
            TabView {
                ForEach(steps) { step in
                    G6ApplyStepCard(step: step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(LocalizedString("How to calibrate", comment: "Calibration help screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedString("Done", comment: "Done button"), action: onDone)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
