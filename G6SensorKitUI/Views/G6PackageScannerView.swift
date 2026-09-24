//
//  G6PackageScannerView.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//

import AVFoundation
import G6SensorCore
import SwiftUI
import VisionKit

/// Camera scanner for the GS1 Data Matrix barcodes on Dexcom packaging:
/// the applicator label and the transmitter box. The box carries two Data
/// Matrices — serial-only (21) and the full (241)(10)(21)(17) — and
/// either yields the transmitter ID. 
struct G6PackageScannerView: UIViewControllerRepresentable {
    let onScan: (G6PackageScan) -> Void
    let onStartFailure: (Error) -> Void

    static var isSupported: Bool {
        return DataScannerViewController.isSupported
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    static var cameraAuthorization: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.dataMatrix])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            DispatchQueue.main.async { onStartFailure(error) }
        }
        return scanner
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (G6PackageScan) -> Void
        private var didDeliver = false

        init(onScan: @escaping (G6PackageScan) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems _: [RecognizedItem]
        ) {
            guard !didDeliver else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue
                else { continue }
                didDeliver = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                onScan(G6PackageScan(payload: payload))
                dataScanner.stopScanning()
                return
            }
        }
    }
}
