//
//  G6UICoordinator.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Hosts both the setup wizard and the settings screen, following the
//  coordinator pattern used by G7SensorKit and LibreLoop: a
//  UINavigationController conforming to CGMManagerOnboarding and
//  CompletionNotifying, with each SwiftUI screen wrapped in
//  DismissibleHostingController.
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit
import G6SensorCore

enum G6UIScreen {
    // Onboarding
    case introduction
    case transmitterIDEntry
    case sensorCodeEntry
    case placementGuide
    case pairing
    case warmup

    // Settings
    case settings
    case calibration
    case transmitterDetails
    case sensorLifeSettings
    case shareUpload
    case readingDetail

    /// Persisted resume marker for onboarding screens.
    var setupStep: G6SetupStep? {
        switch self {
        case .transmitterIDEntry: return .transmitterID
        case .placementGuide: return .placement
        case .sensorCodeEntry: return .sensorCode
        case .pairing: return .pairing
        case .warmup: return .warmup
        default: return nil
        }
    }

    init?(setupStep: G6SetupStep) {
        switch setupStep {
        case .transmitterID: self = .transmitterIDEntry
        case .placement: self = .placementGuide
        case .sensorCode: self = .sensorCodeEntry
        case .pairing: self = .pairing
        case .warmup: self = .warmup
        }
    }

    var next: G6UIScreen? {
        switch self {
        case .introduction: return .transmitterIDEntry
        case .transmitterIDEntry: return .placementGuide
        case .placementGuide: return .sensorCodeEntry
        case .sensorCodeEntry: return .pairing
        case .pairing: return .warmup
        case .warmup: return nil
        default: return nil
        }
    }
}

/// Which sequence the pushed screens belong to. Replacing a transmitter
/// walks most of the same screens, but skips the introduction and the
/// placement guide — the sensor is already on — and returns to settings
/// rather than completing onboarding.
private enum G6FlowMode {
    case onboarding
    case replacingTransmitter
}

public class G6UICoordinator: UINavigationController, CGMManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {

    public weak var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?

    public weak var completionDelegate: CompletionDelegate?

    private var cgmManager: G6CGMManager?

    private let bluetoothProvider: BluetoothProvider

    private let displayGlucosePreference: DisplayGlucosePreference

    private let colorPalette: LoopUIColorPalette

    private let allowDebugFeatures: Bool

    /// Transmitter ID collected during onboarding, before a manager exists.
    private var pendingTransmitterID: String?

    private var screenStack: [G6UIScreen] = []

    private var flowMode: G6FlowMode = .onboarding

    init(
        cgmManager: G6CGMManager? = nil,
        bluetoothProvider: BluetoothProvider,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool
    ) {
        self.cgmManager = cgmManager
        self.bluetoothProvider = bluetoothProvider
        self.displayGlucosePreference = displayGlucosePreference
        self.colorPalette = colorPalette
        self.allowDebugFeatures = allowDebugFeatures

        super.init(navigationBarClass: nil, toolbarClass: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        let screen = initialScreen()
        screenStack = [screen]
        recordProgress(for: screen)

        let viewController = viewControllerForScreen(screen)

        // Whatever screen the stack starts on carries Cancel. Resuming an
        // interrupted setup can begin on any of them, and the root has no
        // back button — restricting Cancel to the introduction left a
        // resumed pairing screen with no way out at all. Settings has its
        // own Done and is excluded.
        if screen != .settings, viewController.navigationItem.leftBarButtonItem == nil {
            viewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelSetup)
            )
        }

        setViewControllers([viewController], animated: false)
    }

    private func initialScreen() -> G6UIScreen {
        guard let cgmManager = cgmManager else {
            return .introduction
        }

        if cgmManager.isOnboarded {
            return .settings
        }

        // Setup was interrupted — the host tears this coordinator down when
        // the user navigates elsewhere, so resume from persisted progress
        // rather than sending them back through the introduction with a
        // transmitter ID they already entered.
        if let step = cgmManager.state.setupStep, let screen = G6UIScreen(setupStep: step) {
            return screen
        }

        return .introduction
    }

    // MARK: - UINavigationControllerDelegate

    public func navigationController(_ navigationController: UINavigationController,
                                     didShow viewController: UIViewController,
                                     animated: Bool) {
        // A back-button pop happens without going through navigateTo, so trim
        // the stack to match what is actually on screen.
        if screenStack.count > navigationController.viewControllers.count {
            screenStack = Array(screenStack.prefix(navigationController.viewControllers.count))
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ screen: G6UIScreen) {
        screenStack.append(screen)
        recordProgress(for: screen)
        pushViewController(viewControllerForScreen(screen), animated: true)
    }

    private func recordProgress(for screen: G6UIScreen) {
        guard let cgmManager = cgmManager, !cgmManager.isOnboarded, let step = screen.setupStep else {
            return
        }
        cgmManager.recordSetupStep(step)
    }

    private func stepFinished() {
        guard let current = screenStack.last else {
            return
        }

        if let next = nextScreen(after: current) {
            navigateTo(next)
        } else {
            finishFlow()
        }
    }

    private func nextScreen(after screen: G6UIScreen) -> G6UIScreen? {
        switch flowMode {
        case .onboarding:
            if screen == .pairing, !shouldShowWarmup {
                return nil
            }
            return screen.next
        case .replacingTransmitter:
            // No introduction, and no placement guide: the sensor is already
            // worn, only the transmitter changed.
            switch screen {
            case .transmitterIDEntry: return .sensorCodeEntry
            case .sensorCodeEntry: return .pairing
            case .pairing: return shouldShowWarmup ? .warmup : nil
            default: return nil
            }
        }
    }

    /// Warm-up only deserves a screen when the sensor is actually in it.
    /// Adopting a session that has been running for hours — what happens when
    /// someone moves a live sensor across from another app — must not
    /// announce a warm-up that finished long ago.
    private var shouldShowWarmup: Bool {
        guard let state = cgmManager?.state else {
            return false
        }
        return state.isInWarmup || state.hasPendingSessionStart
    }

    private func finishFlow() {
        switch flowMode {
        case .onboarding:
            finishOnboarding()
        case .replacingTransmitter:
            // The CGM was never torn down, so there is nothing to onboard —
            // just go back to settings.
            flowMode = .onboarding
            screenStack = [.settings]
            popToRootViewController(animated: true)
        }
    }

    /// Starts the replace-transmitter sequence from settings.
    private func beginTransmitterReplacement() {
        flowMode = .replacingTransmitter
        navigateTo(.transmitterIDEntry)
    }

    private func finishOnboarding() {
        guard let cgmManager = cgmManager else {
            completionDelegate?.completionNotifyingDidComplete(self)
            return
        }

        cgmManager.completeOnboarding()
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didOnboardCGMManager: cgmManager)
        completionDelegate?.completionNotifyingDidComplete(self)
    }

    private func hostingController<Content: View>(
        rootView: Content,
        title: String? = nil,
        showsCancel: Bool = false
    ) -> DismissibleHostingController<some View> {
        let view = rootView
            .environmentObject(displayGlucosePreference)
            .environment(\.appName, Self.hostAppName)
        let controller = DismissibleHostingController(content: view, colorPalette: colorPalette)
        controller.navigationItem.title = title
        if showsCancel {
            // Only ever set on the root screen: a left bar button item
            // replaces the system back button on a pushed controller.
            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelSetup)
            )
        }
        return controller
    }

    /// The host's display name. LoopKit's `bundleDisplayName` helper is a
    /// Loop-side extension that some forks do not carry, so read the plist.
    static let hostAppName: String = {
        let bundle = Bundle.main
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? LocalizedString("This app", comment: "Fallback when the host app name cannot be read")
    }()

    /// Backs out of setup. Without this the first screen had no exit at all,
    /// so choosing this CGM by mistake left the user stranded with no way to
    /// reach settings and remove it.
    @objc private func cancelSetup() {
        // A manager is created as soon as the transmitter ID is entered so the
        // later screens can drive a live session. Backing out after that point
        // must tear it down, or the host is left holding a CGM that was never
        // finished being set up.
        if let cgmManager = cgmManager, !cgmManager.isOnboarded {
            cgmManager.delete { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            }
            self.cgmManager = nil
            return
        }

        completionDelegate?.completionNotifyingDidComplete(self)
    }

    /// Creates the manager once the transmitter ID is known, so the remaining
    /// onboarding screens can drive a live session (create-then-onboard order;
    /// note EversenseKit inverts this — don't copy that).
    private func createManagerIfNeeded(transmitterID: String) {
        guard cgmManager == nil else {
            return
        }

        let state = G6CGMManagerState(transmitterID: transmitterID)
        let manager = G6CGMManager(state: state)
        cgmManager = manager
        manager.recordSetupStep(.transmitterID)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didCreateCGMManager: manager)
    }

    private func viewControllerForScreen(_ screen: G6UIScreen) -> UIViewController {
        switch screen {
        case .introduction:
            return hostingController(
                rootView: G6IntroductionView(didContinue: { [weak self] in self?.stepFinished() })
            )

        case .transmitterIDEntry:
            return hostingController(
                rootView: G6TransmitterIDEntryView(
                    initialValue: cgmManager?.state.transmitterID ?? "",
                    didSubmit: { [weak self] id in
                        guard let self = self else { return }
                        self.pendingTransmitterID = id

                        switch self.flowMode {
                        case .onboarding:
                            self.createManagerIfNeeded(transmitterID: id)
                        case .replacingTransmitter:
                            self.cgmManager?.replaceTransmitter(id: id)
                        }

                        self.stepFinished()
                    }
                ),
                title: LocalizedString("Transmitter ID", comment: "Navigation title for transmitter ID entry")
            )

        case .sensorCodeEntry:
            return hostingController(
                rootView: G6SensorCodeEntryView(
                    didSubmit: { [weak self] code in
                        self?.startSensor(code: code)
                        self?.stepFinished()
                    }
                ),
                title: LocalizedString("Sensor Code", comment: "Navigation title for sensor code entry")
            )

        case .placementGuide:
            return hostingController(
                rootView: G6ApplySensorView(onNext: { [weak self] in self?.stepFinished() }),
                title: LocalizedString("Applying Your Sensor", comment: "Navigation title for placement guide")
            )

        case .pairing:
            return hostingController(
                rootView: G6PairingView(
                    manager: cgmManager,
                    didContinue: { [weak self] in self?.stepFinished() }
                ),
                title: LocalizedString("Pairing", comment: "Navigation title for pairing screen")
            )

        case .warmup:
            return hostingController(
                rootView: G6WarmupView(
                    manager: cgmManager,
                    didFinish: { [weak self] in self?.stepFinished() }
                ),
                title: LocalizedString("Warm-Up", comment: "Navigation title for warm-up screen")
            )

        case .settings:
            guard let cgmManager = cgmManager else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6SettingsView(
                    viewModel: G6SettingsViewModel(
                        cgmManager: cgmManager,
                        toCalibration: { [weak self] in self?.navigateTo(.calibration) },
                        toTransmitterDetails: { [weak self] in self?.navigateTo(.transmitterDetails) },
                        toSensorLifeSettings: { [weak self] in self?.navigateTo(.sensorLifeSettings) },
                        toShareUpload: { [weak self] in self?.navigateTo(.shareUpload) },
                        toReadingDetail: { [weak self] in self?.navigateTo(.readingDetail) },
                        toPlacementGuide: { [weak self] in self?.navigateTo(.placementGuide) },
                        didRequestDeletion: { [weak self] in self?.deleteCGM() },
                        didFinish: { [weak self] in
                            guard let self = self else { return }
                            self.completionDelegate?.completionNotifyingDidComplete(self)
                        }
                    )
                ),
                title: LocalizedString("Dexcom G6 / ONE", comment: "Navigation title for settings")
            )

        case .calibration:
            guard let cgmManager = cgmManager else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6CalibrationView(
                    cgmManager: cgmManager,
                    didSubmit: { [weak self] in self?.popViewController(animated: true) }
                ),
                title: LocalizedString("Calibration", comment: "Navigation title for calibration")
            )

        case .readingDetail:
            guard let cgmManager = cgmManager, let reading = cgmManager.state.latestReading else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6ReadingDetailView(
                    reading: reading,
                    deviceModel: cgmManager.state.deviceModel,
                    transmitterID: cgmManager.state.transmitterID
                )
            )

        case .transmitterDetails:
            guard let cgmManager = cgmManager else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6TransmitterDetailsView(
                    cgmManager: cgmManager,
                    onPairNewTransmitter: { [weak self] in self?.beginTransmitterReplacement() }
                ),
                title: LocalizedString("Transmitter", comment: "Navigation title for transmitter details")
            )

        case .sensorLifeSettings:
            guard let cgmManager = cgmManager else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6SensorLifeSettingsView(cgmManager: cgmManager),
                title: LocalizedString("Session Length", comment: "Navigation title for sensor life settings")
            )

        case .shareUpload:
            guard let cgmManager = cgmManager else {
                return UIViewController()
            }
            return hostingController(
                rootView: G6ShareUploadSettingsView(cgmManager: cgmManager),
                title: LocalizedString("Dexcom Share", comment: "Navigation title for Share upload settings")
            )
        }
    }

    private func startSensor(code: String?) {
        guard let cgmManager = cgmManager else {
            return
        }

        guard let sensorCode = SensorCode(code) else {
            // Should not be reachable — the entry screen validates before
            // submitting — but silently doing nothing here would strand the
            // flow with no session queued and no explanation.
            cgmManager.logSetupEvent("Sensor code \(code ?? "nil") not recognised; no session queued")
            return
        }

        cgmManager.logSetupEvent("Queued session start with sensor code \(sensorCode.carriesParameters ? sensorCode.code : "none")")
        cgmManager.enqueue(.startSensor(at: Date(), sensorCode: sensorCode))
    }

    private func deleteCGM() {
        cgmManager?.delete { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }
        }
    }
}
