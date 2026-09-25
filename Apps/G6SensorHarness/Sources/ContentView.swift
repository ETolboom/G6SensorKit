//
//  ContentView.swift
//  G6SensorHarness
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = HarnessViewModel()
    @State private var sensorCode: String = ""
    @State private var calibrationValue: String = ""

    var body: some View {
        NavigationView {
            List {
                Section("Transmitter") {
                    TextField("Transmitter ID (6 characters)", text: $model.transmitterID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .disabled(model.isRunning)

                    Toggle("Passive mode (listen to Dexcom app)", isOn: $model.passiveModeEnabled)
                        .disabled(model.isRunning)

                    if model.isRunning {
                        Button("Stop", role: .destructive) { model.stop() }
                    } else {
                        Button("Start") { model.start() }
                    }

                    row("Latest reading", model.latestReading)
                    row("Last connect", model.lastConnect.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                }

                if !model.passiveModeEnabled {
                    Section("Session commands (sent on next connection)") {
                        HStack {
                            TextField("Sensor code (blank = no code)", text: $sensorCode)
                                .keyboardType(.numberPad)
                            Button("Start sensor") {
                                model.enqueueStartSensor(code: sensorCode.isEmpty ? nil : sensorCode)
                            }
                        }
                        Button("Stop sensor") { model.enqueueStopSensor() }
                        HStack {
                            TextField("Calibration mg/dL", text: $calibrationValue)
                                .keyboardType(.numberPad)
                            Button("Calibrate") {
                                if let value = Double(calibrationValue) {
                                    model.enqueueCalibration(mgDL: value)
                                }
                            }
                        }
                        Button("Read battery") { model.requestBattery() }
                        Button("Backfill last 3h") { model.requestBackfill(hours: 3) }
                    }
                }

                Section("Log") {
                    ForEach(model.log) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("G6SensorHarness")
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
