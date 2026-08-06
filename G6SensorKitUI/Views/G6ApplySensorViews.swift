//
//  G6ApplySensorViews.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Structure follows LibreLoop's apply-sensor flow: a hero screen with a
//  "how to" entry point, and a modal paged card deck of numbered steps.
//  The step sequence, wording, and figures follow the Dexcom G6 user guide
//  (Chapter 6, Start Your Sensor) so the procedure users are taught by the
//  manufacturer is the procedure this app walks them through.
//
//  Figures live in Assets.xcassets and are loaded through UIImage from the
//  framework bundle — SwiftUI's Image(_:bundle:) is unreliable for assets
//  inside a plugin framework.
//

import SwiftUI
import LoopKit
import LoopKitUI
import G6SensorKit

// MARK: - Step model

struct G6ApplyStep: Identifiable {
    let id = UUID()
    /// e.g. "STEP 3 of 10"
    let title: String
    let section: String
    let assetName: String
    let body: String
    let note: String?
    var fallbackSymbol: String = "sensor.tag.radiowaves.forward"
}

enum G6ApplySteps {

    static func insertSensor() -> [G6ApplyStep] {
        let section = LocalizedString("INSERT SENSOR", comment: "Section label for the insert-sensor steps")
        func title(_ n: Int) -> String {
            String(format: LocalizedString("STEP %d of 10", comment: "Insert-sensor step counter (1: step number)"), n)
        }
        return [
            G6ApplyStep(
                title: title(1), section: section, assetName: "G6InsertStep1",
                body: LocalizedString("Thoroughly wash and dry your hands.", comment: "Insert step 1 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(2), section: section, assetName: "G6InsertStep2",
                body: LocalizedString("Clean the insertion site with alcohol. Let it dry.", comment: "Insert step 2 body"),
                note: LocalizedString("The site must be completely dry or the adhesive will not stick.", comment: "Insert step 2 note")
            ),
            G6ApplyStep(
                title: title(3), section: section, assetName: "G6InsertStep3",
                body: LocalizedString("Optional: if you use a skin adhesive, draw an empty oval on the skin and let it dry.", comment: "Insert step 3 body"),
                note: LocalizedString("Insert the sensor on clean skin in the centre of the oval, not on the adhesive itself.", comment: "Insert step 3 note")
            ),
            G6ApplyStep(
                title: title(4), section: section, assetName: "G6InsertStep4",
                body: LocalizedString("Take out the applicator whose sensor code you entered, and peel off its cover.", comment: "Insert step 4 body"),
                note: LocalizedString("Do not use it if the packaging is damaged or was already opened. Keep the packaging until the session is finished.", comment: "Insert step 4 note")
            ),
            G6ApplyStep(
                title: title(5), section: section, assetName: "G6InsertStep5",
                body: LocalizedString("Pull off both adhesive labels.", comment: "Insert step 5 body"),
                note: LocalizedString("Keep the tab showing the sensor code. Do not touch the adhesive.", comment: "Insert step 5 note")
            ),
            G6ApplyStep(
                title: title(6), section: section, assetName: "G6InsertStep6",
                body: LocalizedString("Place the applicator flat against your skin — horizontally, not upright — and press down firmly.", comment: "Insert step 6 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(7), section: section, assetName: "G6InsertStep7",
                body: LocalizedString("Fold and break off the safety guard, then throw it away.", comment: "Insert step 7 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(8), section: section, assetName: "G6InsertStep8",
                body: LocalizedString("Push and release the button to insert the sensor.", comment: "Insert step 8 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(9), section: section, assetName: "G6InsertStep9",
                body: LocalizedString("Lift the applicator away.", comment: "Insert step 9 body"),
                note: LocalizedString("Dispose of the applicator following your local rules for items that have touched blood.", comment: "Insert step 9 note")
            ),
            G6ApplyStep(
                title: title(10), section: section, assetName: "G6InsertStep10",
                body: LocalizedString("Left on your skin: the sensor wire and the transmitter holder. The sensor is in.", comment: "Insert step 10 body"),
                note: nil
            )
        ]
    }

    static func attachTransmitter() -> [G6ApplyStep] {
        let section = LocalizedString("ATTACH TRANSMITTER", comment: "Section label for the attach-transmitter steps")
        func title(_ n: Int) -> String {
            String(format: LocalizedString("STEP %d of 4", comment: "Attach-transmitter step counter (1: step number)"), n)
        }
        return [
            // Taking it out of the box and wiping it are one continuous
            // action; splitting them gave a step with nothing to show.
            G6ApplyStep(
                title: title(1), section: section, assetName: "G6AttachStep2",
                body: LocalizedString("Take the transmitter out of its box and prepare it for use. Wipe the bottom with an alcohol wipe and let it dry.", comment: "Attach step 1 body"),
                note: LocalizedString("Do not touch the metal contacts and do not scratch the bottom — that can break the waterproof seal.", comment: "Attach step 1 note")
            ),
            G6ApplyStep(
                title: title(2), section: section, assetName: "G6AttachStep3",
                body: LocalizedString("Slide the transmitter tab into the slot at the narrow end of the holder.", comment: "Attach step 3 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(3), section: section, assetName: "G6AttachStep4",
                body: LocalizedString("Press the wide end of the transmitter until it clicks into the holder.", comment: "Attach step 4 body"),
                note: nil
            ),
            G6ApplyStep(
                title: title(4), section: section, assetName: "G6AttachStep5",
                body: LocalizedString("Rub your fingers around the patch three times to secure it.", comment: "Attach step 5 body"),
                note: LocalizedString("You are almost done — the sensor session starts next.", comment: "Attach step 5 note")
            )
        ]
    }

    static var all: [G6ApplyStep] { insertSensor() + attachTransmitter() }
}

// MARK: - Shared figure rendering

/// Figures are line art on a light background, so they sit on a fixed light
/// card to stay legible in dark mode.
struct G6StepFigure: View {
    let assetName: String
    var height: CGFloat = 230
    /// Shown when there is no manual figure for the step — used where the
    /// step happens in this app rather than on the hardware.
    var fallbackSymbol: String = "sensor.tag.radiowaves.forward"

    var body: some View {
        if let image = UIImage(named: assetName, in: Bundle(for: G6UICoordinator.self), compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.97))
                )
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .scaledToFit()
                .frame(height: height * 0.45)
                .foregroundStyle(.tint)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Hero screen

struct G6ApplySensorView: View {
    let onNext: () -> Void

    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    G6StepFigure(assetName: "G6SensorSite", height: 190)
                        .padding(.top, 24)

                    Text(LocalizedString("Apply a new sensor", comment: "Apply-sensor screen title"))
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(LocalizedString("Adults wear the sensor on the belly. Children aged 2 to 17 can use the belly or upper buttocks.", comment: "Apply-sensor site instruction"))
                        Text(LocalizedString("Keep at least 8 cm (3 inches) away from insulin pump sites and injection sites, and avoid scars, bony areas, and your waistband.", comment: "Apply-sensor spacing instruction"))
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .padding(.horizontal, 24)

                    Button {
                        showingHelp = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                            Text(LocalizedString("HOW TO APPLY A SENSOR", comment: "Apply-sensor help button"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }

            Button(action: onNext) {
                Text(LocalizedString("Next", comment: "Next button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(G6PrimaryButtonStyle())
            .padding()
        }
        .sheet(isPresented: $showingHelp) {
            G6ApplyHelpPagerView(onDone: { showingHelp = false })
        }
    }
}

// MARK: - Paged step deck

struct G6ApplyHelpPagerView: View {
    let onDone: () -> Void

    private let steps = G6ApplySteps.all

    var body: some View {
        NavigationView {
            TabView {
                ForEach(steps) { step in
                    G6ApplyStepCard(step: step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(LocalizedString("How to apply a sensor", comment: "Apply-sensor help screen title"))
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

struct G6ApplyStepCard: View {
    let step: G6ApplyStep

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // An empty asset name means the step has no figure: it happens
                // in this app, not on the hardware, so nothing is illustrated.
                if !step.assetName.isEmpty {
                    G6StepFigure(assetName: step.assetName, fallbackSymbol: step.fallbackSymbol)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(step.section)
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    Text(step.title)
                        .font(.title3.weight(.bold))
                        .tracking(2)

                    // Left-aligned: centred body copy is markedly harder to
                    // read once it wraps past one line.
                    Text(step.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = step.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
