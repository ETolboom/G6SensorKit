//
//  G6ReadingDetailView.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Detail for the most recent reading, mirroring LibreLoop's sample detail
//  screen: the value up top, then the facts behind it — when it was taken,
//  how it is trending, what the transmitter's own algorithm state says, and
//  the identifier used to de-duplicate it against backfill.
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore

struct G6ReadingDetailView: View {

    let reading: G6StoredReading
    let deviceModel: String
    let transmitterID: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(reading.glucoseMgDL))")
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                        if let symbol = trendSymbol {
                            Image(systemName: symbol)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(LocalizedString("mg/dL", comment: "Glucose unit label"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(reading.date.formatted(date: .abbreviated, time: .standard))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                row(LocalizedString("Trend", comment: "Reading detail label for trend"), trendText)
                row(LocalizedString("Sensor status", comment: "Reading detail label for algorithm state"), stateText)
                row(
                    LocalizedString("Display only", comment: "Reading detail label for display-only flag"),
                    reading.isDisplayOnly
                        ? LocalizedString("Yes", comment: "Affirmative")
                        : LocalizedString("No", comment: "Negative")
                )
            } header: {
                Text(LocalizedString("Reading", comment: "Reading detail section header"))
            } footer: {
                if reading.isDisplayOnly {
                    Text(LocalizedString("A display-only value has been shifted by a recent calibration. It is shown for continuity and is not used for dosing.", comment: "Footer explaining display-only readings"))
                }
            }

            Section {
                row(LocalizedString("Device", comment: "Reading detail label for device"), deviceModel)
                row(LocalizedString("Transmitter", comment: "Reading detail label for transmitter"), transmitterID)
                row(LocalizedString("Identifier", comment: "Reading detail label for sync identifier"), reading.syncIdentifier)
            } header: {
                Text(LocalizedString("Source", comment: "Reading detail section header for source"))
            } footer: {
                Text(LocalizedString("The identifier is derived from the transmitter's own clock, so the same reading keeps one identity whether it arrives live or is filled in later.", comment: "Footer explaining the sync identifier"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LocalizedString("Latest Reading", comment: "Reading detail screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trendSymbol: String? {
        guard let rate = reading.trendRateMgDLPerMinute else { return nil }
        switch rate {
        case ..<(-3): return "arrow.down"
        case ..<(-1): return "arrow.down.right"
        case ..<1: return "arrow.right"
        case ..<3: return "arrow.up.right"
        default: return "arrow.up"
        }
    }

    private var trendText: String {
        guard let rate = reading.trendRateMgDLPerMinute else {
            return LocalizedString("Not available", comment: "Value when the transmitter reports no trend")
        }
        return String(
            format: LocalizedString("%@%.1f mg/dL per minute", comment: "Trend rate (1: sign, 2: rate)"),
            rate > 0 ? "+" : "", rate
        )
    }

    private var stateText: String {
        let state = reading.calibrationState
        if state.isSensorFailed {
            return LocalizedString("Sensor failed", comment: "Algorithm state: failed")
        }
        if state.isInWarmup {
            return LocalizedString("Warming up", comment: "Algorithm state: warm-up")
        }
        if state.isStopped {
            return LocalizedString("Session stopped", comment: "Algorithm state: stopped")
        }
        if state.needsCalibration {
            return LocalizedString("Calibration requested", comment: "Algorithm state: needs calibration")
        }
        if state.hasReliableGlucose {
            return LocalizedString("OK", comment: "Algorithm state: ok")
        }
        return String(
            format: LocalizedString("Unusable (code %d)", comment: "Algorithm state: unusable with raw code"),
            Int(reading.calibrationStateRawValue)
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
