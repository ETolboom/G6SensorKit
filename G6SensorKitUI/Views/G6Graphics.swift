//
//  G6Graphics.swift
//  G6SensorKitUI
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Original vector illustrations and status components, drawn with SwiftUI
//  primitives. The step sequence and composition mirror the device's official
//  instructions so the flow matches what users are taught, but no artwork,
//  screenshots, or copy are taken from the manufacturer.
//

import SwiftUI

// MARK: - Palette

enum G6Palette {
    static let sensorBody = Color(.systemGray5)
    static let sensorEdge = Color(.systemGray3)
    static let skin = Color(red: 0.96, green: 0.86, blue: 0.78)
    static let skinEdge = Color(red: 0.84, green: 0.72, blue: 0.63)
    static let accent = Color.accentColor
}

// MARK: - Sensor + transmitter

/// The worn sensor: adhesive patch with the transmitter clipped into it.
struct G6SensorGlyph: View {
    var isActive: Bool = true
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            // Adhesive patch
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: max(1, size * 0.012))
                )
                .frame(width: size, height: size * 0.72)
                .shadow(color: .black.opacity(0.10), radius: size * 0.05, y: size * 0.02)

            // Transmitter body
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [G6Palette.sensorBody, G6Palette.sensorEdge],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.68, height: size * 0.38)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: max(1, size * 0.01))
                )

            // Transmitting indicator
            if isActive {
                Circle()
                    .fill(G6Palette.accent)
                    .frame(width: size * 0.10, height: size * 0.10)
                    .offset(x: size * 0.20)
                    .shadow(color: G6Palette.accent.opacity(0.6), radius: size * 0.06)
            }
        }
        .frame(width: size, height: size * 0.72)
        .accessibilityHidden(true)
    }
}

/// The applicator barrel used to place the sensor.
struct G6ApplicatorGlyph: View {
    var size: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            // Plunger
            Capsule()
                .fill(G6Palette.accent.opacity(0.85))
                .frame(width: size * 0.34, height: size * 0.20)
            // Barrel
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white, G6Palette.sensorBody],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: max(1, size * 0.012))
                )
                .frame(width: size * 0.56, height: size * 0.52)
            // Base on skin
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(G6Palette.sensorEdge)
                .frame(width: size * 0.66, height: size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Torso outline with the approved wear areas highlighted.
struct G6BodySiteGlyph: View {
    var size: CGFloat = 110

    var body: some View {
        ZStack {
            // Torso
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(G6Palette.skin)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(G6Palette.skinEdge, lineWidth: max(1, size * 0.012))
                )
                .frame(width: size * 0.62, height: size * 0.80)

            // Navel reference point
            Circle()
                .fill(G6Palette.skinEdge.opacity(0.6))
                .frame(width: size * 0.05, height: size * 0.05)

            // Candidate sites either side of the midline
            HStack(spacing: size * 0.22) {
                siteDot(size: size)
                siteDot(size: size)
            }
            .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func siteDot(size: CGFloat) -> some View {
        Circle()
            .strokeBorder(G6Palette.accent, style: StrokeStyle(lineWidth: max(1.5, size * 0.018), dash: [size * 0.045, size * 0.03]))
            .background(Circle().fill(G6Palette.accent.opacity(0.14)))
            .frame(width: size * 0.17, height: size * 0.17)
    }
}

/// Phone showing a pairing request.
struct G6PairingGlyph: View {
    var size: CGFloat = 90

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: max(1, size * 0.016))
                )
                .frame(width: size * 0.56, height: size * 0.86)

            VStack(spacing: size * 0.06) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: size * 0.20, weight: .semibold))
                    .foregroundStyle(G6Palette.accent)
                RoundedRectangle(cornerRadius: size * 0.02)
                    .fill(G6Palette.sensorBody)
                    .frame(width: size * 0.34, height: size * 0.045)
                Capsule()
                    .fill(G6Palette.accent)
                    .frame(width: size * 0.30, height: size * 0.11)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Generic "clean the site" mark.
struct G6WipeGlyph: View {
    var size: CGFloat = 90

    var body: some View {
        ZStack {
            Circle()
                .fill(G6Palette.skin)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .strokeBorder(G6Palette.accent.opacity(0.5),
                              style: StrokeStyle(lineWidth: max(1.5, size * 0.02), dash: [size * 0.05, size * 0.04]))
                .frame(width: size * 0.72, height: size * 0.72)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(G6Palette.accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Status presentation

enum G6SessionPhase {
    case noSession
    case warmup
    case active
    case expiringSoon
    case expired
    case failed
    case signalLoss
    case transmitterExpired

    var title: String {
        switch self {
        case .noSession: return LocalizedString("No Sensor", comment: "Session phase: no sensor running")
        case .warmup: return LocalizedString("Warming Up", comment: "Session phase: warm-up")
        case .active: return LocalizedString("Active", comment: "Session phase: active")
        case .expiringSoon: return LocalizedString("Ending Soon", comment: "Session phase: expiring soon")
        case .expired: return LocalizedString("Session Ended", comment: "Session phase: expired")
        case .failed: return LocalizedString("Sensor Failed", comment: "Session phase: failed")
        case .signalLoss: return LocalizedString("No Signal", comment: "Session phase: signal loss")
        case .transmitterExpired: return LocalizedString("Transmitter Expired", comment: "Session phase: transmitter past end of life")
        }
    }

    var symbol: String {
        switch self {
        case .noSession: return "sensor.tag.radiowaves.forward"
        case .warmup: return "clock.fill"
        case .active: return "checkmark.circle.fill"
        case .expiringSoon: return "exclamationmark.circle.fill"
        case .expired: return "clock.badge.exclamationmark.fill"
        case .failed: return "xmark.octagon.fill"
        case .signalLoss: return "antenna.radiowaves.left.and.right.slash"
        case .transmitterExpired: return "hourglass.bottomhalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .active: return .green
        case .warmup: return .blue
        case .expiringSoon: return .orange
        case .expired, .failed, .signalLoss, .transmitterExpired: return .red
        case .noSession: return .secondary
        }
    }
}

/// Compact status pill used in the settings header.
struct G6StatusPill: View {
    let phase: G6SessionPhase

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: phase.symbol)
                .font(.caption2.weight(.semibold))
            Text(phase.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(phase.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(phase.tint.opacity(0.14)))
    }
}

/// Session progress, laid out the way LibreLoop does it: the phase name in
/// its state colour on the left, the remaining time on the right, and the
/// track beneath — rather than a bare bar with a caption under it.
struct G6LifecycleBar: View {
    let phase: G6SessionPhase
    let fraction: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(phase.tint)
                Spacer()
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(phase.tint)
                        .frame(width: proxy.size.width * max(0, min(1, fraction)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phase.title). \(detail)")
    }
}

// MARK: - Asset slots

/// Renders a named image from the framework bundle when present, and falls
/// back to a drawn placeholder when it is not. This keeps the flow working
/// for anyone building without the optional illustration assets, and lets
/// artwork be dropped into Assets.xcassets without touching code.
struct G6AssetImage<Fallback: View>: View {
    let name: String
    let height: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        if let image = UIImage(named: name, in: Bundle(for: G6UICoordinator.self), compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: height)
                .accessibilityHidden(true)
        } else {
            fallback()
        }
    }
}

/// Callout that points at where a code is printed on the hardware.
/// The figure sits on a fixed light card because it is dark line art on
/// white; the caption stays outside the card so it keeps normal text
/// colours and stays readable in dark mode.
struct G6FindCodeCard<Fallback: View>: View {
    let assetName: String
    let caption: String
    var imageHeight: CGFloat = 170
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            G6AssetImage(name: assetName, height: imageHeight, fallback: fallback)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.97))
                )

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Transmitter shown from the back, where the serial number is printed.
struct G6TransmitterBackGlyph: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(G6Palette.sensorBody)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: 1.5)
                )
                .frame(width: size * 0.86, height: size * 0.46)
            VStack(spacing: size * 0.04) {
                Text(verbatim: "SN")
                    .font(.system(size: size * 0.09, weight: .bold))
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(G6Palette.accent, lineWidth: 2)
                    .frame(width: size * 0.46, height: size * 0.15)
            }
        }
        .frame(width: size, height: size * 0.6)
        .accessibilityHidden(true)
    }
}

/// Applicator label carrying the four-digit sensor code.
struct G6SensorCodeLabelGlyph: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .strokeBorder(G6Palette.sensorEdge, lineWidth: 1.5)
                )
                .frame(width: size * 0.9, height: size * 0.56)
            VStack(spacing: size * 0.05) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(G6Palette.sensorBody)
                    .frame(width: size * 0.5, height: size * 0.05)
                Text(verbatim: "0000")
                    .font(.system(size: size * 0.16, weight: .bold, design: .monospaced))
                    .padding(.horizontal, size * 0.06)
                    .padding(.vertical, size * 0.02)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(G6Palette.accent, lineWidth: 2))
            }
        }
        .frame(width: size, height: size * 0.6)
        .accessibilityHidden(true)
    }
}


/// The G6 transmitter artwork, shared with CGMBLEKitUI so the device reads
/// the same across drivers. Falls back to the drawn glyph if absent.
struct G6TransmitterImage: View {
    var size: CGFloat = 88
    var isActive: Bool = true
    var assetName: String = "G6Transmitter"

    var body: some View {
        if let image = UIImage(named: assetName, in: Bundle(for: G6UICoordinator.self), compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .opacity(isActive ? 1 : 0.55)
                .accessibilityHidden(true)
        } else {
            G6SensorGlyph(isActive: isActive, size: size)
        }
    }
}

// MARK: - Buttons

/// Primary action button.
///
/// `.borderedProminent` dims so little when disabled that it reads as
/// tappable, and any explicit `foregroundStyle` on a label defeats the
/// system dimming altogether. Reading `\.isEnabled` inside the style means
/// the disabled appearance is stated rather than inherited, and every
/// primary button gets the same treatment.
struct G6PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color(.systemGray5))
            )
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

/// Row-style action inside a List, dimmed when disabled.
struct G6RowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .opacity(isEnabled ? 1 : 0.55)
    }
}
