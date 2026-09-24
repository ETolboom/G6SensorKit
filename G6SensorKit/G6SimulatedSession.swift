//
//  G6SimulatedSession.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Simulator-only stand-in for a real transmitter, so the setup flow and the
//  settings screens can be exercised without hardware. CoreBluetooth cannot
//  connect to anything in the simulator, so without this the pairing screen
//  would wait forever and nothing past it could be reached.
//
//  The whole file is compiled out on device — there is no runtime flag that
//  could switch this on for a real user.
//

#if targetEnvironment(simulator)

import Foundation
import HealthKit
import LoopKit
import G6SensorCore

extension G6CGMManager {

    /// How long the simulated transmitter "searches" before connecting.
    static let simulatedConnectDelay: TimeInterval = 5

    /// Warm-up is left with this much time remaining so the warm-up screen
    /// shows a real countdown instead of being skipped or taking two hours.
    static let simulatedWarmupRemaining: TimeInterval = 60

    func startSimulatedSession() {
        connectionPhase = .searching

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.simulatedConnectDelay) { [weak self] in
            guard let self = self else { return }

            self.connectionPhase = .connected

            let now = Date()
            self.mutateStateForSimulation { state in
                // Transmitter part-way through its life, sensor almost done
                // warming up.
                state.transmitterStartDate = now.addingTimeInterval(-.hours(24 * 12))
                state.sensorStartDate = now.addingTimeInterval(-(state.warmupPeriod - Self.simulatedWarmupRemaining))
                // 180 days so the simulator presents as an Anubis, making the
                // longer session length and expiry visible in the UI.
                state.transmitterExpiryInDays = 180
                state.firmwareVersion = "1.0.0.0 (simulated)"
                state.peripheralIdentifier = UUID()
            }

            self.scheduleSimulatedReadings()
        }
    }

    private func scheduleSimulatedReadings() {
        // Tick faster than the real 5-minute cadence so warm-up ending and the
        // first readings are visible without a long wait.
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.emitSimulatedReading()
        }
        RunLoop.main.add(timer, forMode: .common)
        simulationTimer = timer
        emitSimulatedReading()
    }

    private func emitSimulatedReading() {
        // No active session (ended, or not yet started): stay quiet.
        guard state.sensorStartDate != nil else { return }

        guard !state.isInWarmup else {
            // Still warming up: the state change alone refreshes the UI.
            notifySimulationObservers()
            return
        }

        let date = Date()
        // Gentle wander around 120 mg/dL so trend arrows and the chart move.
        let phase = date.timeIntervalSince1970 / 600
        let value = (120 + 35 * sin(phase)).rounded()
        let rate = (35 * cos(phase) / 10).rounded(toPlaces: 1)

        let reading = G6StoredReading(
            date: date,
            glucoseMgDL: value,
            trendRateMgDLPerMinute: rate,
            isDisplayOnly: false,
            syncIdentifier: "g6sk-sim-\(Int(date.timeIntervalSince1970 / 300))",
            calibrationStateRawValue: 6      // .ok
        )

        mutateStateForSimulation { state in
            state.latestReading = reading
            state.recentReadings.append(reading)
            if state.recentReadings.count > 100 {
                state.recentReadings.removeFirst(state.recentReadings.count - 100)
            }
        }

        let sample = NewGlucoseSample(
            date: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
            condition: nil,
            trend: nil,
            trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: rate),
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: reading.syncIdentifier,
            syncVersion: 1,
            device: device
        )

        deliverSimulated([sample])
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#endif
