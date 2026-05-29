import SwiftUI

/// Settings → Appearance: interface zoom (display size).
///
/// Recreated pixel-for-pixel from the v2 design
/// (`docs/superpowers/design/v2/appearance.jsx`):
///   ┌──────────────────────────────────────────────────────┐
///   │ APPEARANCE                                            │  ← eyebrow
///   │ Display size   zoom the whole interface  [Reset 100%] │  ← title + sub
///   │ INTERFACE ZOOM                                        │  ← section eyebrow
///   │  ┌ card: "Interface zoom" + big {pct}% reading ┐      │
///   │  │  small A ──●────●────◉────●────● large A     │      │  ← stepper
///   │  │  85% Smaller … 100% Default … 125% Larger    │      │
///   │  │  ────────────────────────────────────────── │      │
///   │  │  ⌘+ Zoom in   ⌘− Zoom out   ⌘0 Reset to 100% │      │
///   │ PREVIEW                                               │
///   │  ┌ card: a sample PR row scaled by the chosen zoom ┐  │
///   └──────────────────────────────────────────────────────┘
///
/// The stepper is interactive (tap a stop to select) and ⌘+/⌘−/⌘0 drive the
/// same selection; both persist through `AppearanceViewModel`. Applying the
/// scale app-wide is out of scope — the screen drives the stored preference.
struct AppearanceScreen: View {
    @Bindable var viewModel: AppearanceViewModel

    // Amber gradient stops (design uses oklch(0.78 0.14 75) → oklch(0.88 0.14 78)).
    private let amberDeep = Color(red: 0.88, green: 0.62, blue: 0.18)
    private let amberBright = Color(red: 1.0, green: 0.80, blue: 0.40)
    // Preview avatar radial (oklch(0.88 0.14 78) → oklch(0.50 0.13 60)).
    private let avatarBrown = Color(red: 0.52, green: 0.34, blue: 0.12)

    private var stops: [AppearanceViewModel.ZoomStop] { AppearanceViewModel.stops }
    private var active: Int { viewModel.activeIndex }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                sectionEyebrow("INTERFACE ZOOM").padding(.top, 28)
                zoomCard.padding(.top, 10)

                sectionEyebrow("PREVIEW").padding(.top, 28)
                previewCard.padding(.top, 10)
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // ⌘+ / ⌘= zoom in · ⌘− zoom out · ⌘0 reset — invisible accelerators
        // that drive the same persisted selection as the stepper.
        .background(shortcutAccelerators)
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("APPEARANCE")
            HStack(alignment: .firstTextBaseline) {
                Text("Display size")
                    .font(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("zoom the whole interface")
                    .font(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                resetButton
            }
        }
    }

    private var resetButton: some View {
        Button("Reset to 100%") {
            Task { await viewModel.reset() }
        }
        .buttonStyle(.plain)
        .font(AerieFont.small())
        .foregroundStyle(AerieColor.text3)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(AerieColor.glass1))
        .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    // MARK: - Interface zoom card

    private var zoomCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interface zoom")
                        .font(.custom(AerieFont.sans, size: 14.5).weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    Text("Text, spacing and icons all scale together — the same way ⌘+ zooms a browser.")
                        .font(.custom(AerieFont.sans, size: 12.5))
                        .foregroundStyle(AerieColor.text3)
                        .lineSpacing(3)
                        .frame(maxWidth: 360, alignment: .leading)
                }
                Spacer(minLength: 16)
                Text("\(viewModel.zoomPct)%")
                    .font(.custom(AerieFont.mono, size: 30).weight(.medium))
                    .tracking(-0.3)
                    .foregroundStyle(AerieColor.text1)
            }

            zoomStepper

            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1)

            HStack(spacing: 22) {
                shortcutHint(keys: ["⌘", "+"], label: "Zoom in")
                shortcutHint(keys: ["⌘", "−"], label: "Zoom out")
                shortcutHint(keys: ["⌘", "0"], label: "Reset to 100%")
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    // MARK: - Stepper

    private var zoomStepper: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Text("A")
                    .font(.custom(AerieFont.sans, size: 13).weight(.semibold))
                    .foregroundStyle(AerieColor.text3)

                stepperTrack
                    .frame(height: 18)

                Text("A")
                    .font(.custom(AerieFont.sans, size: 22).weight(.semibold))
                    .foregroundStyle(AerieColor.text1)
            }

            // Stop labels
            HStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    let isActive = idx == active
                    VStack(spacing: 2) {
                        Text("\(stop.pct)%")
                            .font(AerieFont.code(11).weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? AerieColor.amber : AerieColor.text4)
                        Text(stop.label)
                            .font(.custom(AerieFont.sans, size: 10))
                            .tracking(0.2)
                            .foregroundStyle(isActive ? AerieColor.text2 : AerieColor.text4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var stepperTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = stops.count
            let fillFraction = CGFloat(active) / CGFloat(n - 1)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
                    .frame(height: 6)

                // Fill
                Capsule()
                    .fill(LinearGradient(
                        colors: [amberDeep, amberBright],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(0, w * fillFraction), height: 6)
                    .shadow(color: AerieColor.amber.opacity(0.4), radius: 5)

                // Ticks + tap bands
                ForEach(0..<n, id: \.self) { i in
                    let x = w * CGFloat(i) / CGFloat(n - 1)
                    tick(i)
                        .position(x: x, y: h / 2)
                    // Invisible band so each stop is easy to click.
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: w / CGFloat(n - 1), height: 18)
                        .position(x: x, y: h / 2)
                        .onTapGesture { Task { await viewModel.select(i) } }
                }
            }
            .frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private func tick(_ i: Int) -> some View {
        let isActive = i == active
        let passed = i <= active
        let size: CGFloat = isActive ? 16 : 9
        Circle()
            .fill(isActive ? Color.white : (passed ? AerieColor.amber : Color.white.opacity(0.18)))
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(
                    isActive ? Color.black.opacity(0.10) : AerieColor.glassLine,
                    lineWidth: 1
                )
            )
            .shadow(color: isActive ? Color.black.opacity(0.6) : .clear,
                    radius: isActive ? 2 : 0, x: 0, y: 1)
    }

    // MARK: - Shortcut hint

    private func shortcutHint(keys: [String], label: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                    Text(k)
                        .font(.custom(AerieFont.mono, size: 12))
                        .foregroundStyle(AerieColor.text2)
                        .frame(minWidth: 20)
                        .frame(height: 20)
                        .padding(.horizontal, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.30))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                        )
                }
            }
            Text(label)
                .font(.custom(AerieFont.sans, size: 12.5))
                .foregroundStyle(AerieColor.text3)
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        zoomPreview
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.card)
    }

    private var zoomPreview: some View {
        let k = CGFloat(viewModel.zoomPct) / 100.0
        return HStack(spacing: 16 * k) {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [amberBright, avatarBrown]),
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 0, endRadius: 30 * k
                ))
                .frame(width: 30 * k, height: 30 * k)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .blendMode(.overlay)
                )

            VStack(alignment: .leading, spacing: 5 * k) {
                Text("PollingScheduler: virtual clock for tests")
                    .font(.custom(AerieFont.sans, size: 16 * k).weight(.medium))
                    .tracking(-0.08 * k)
                    .foregroundStyle(AerieColor.text1)
                    .lineLimit(1)
                Text("aerie · #142 · feat/virtual-clock")
                    .font(.custom(AerieFont.mono, size: 12 * k))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ciPill(k: k)
        }
        .padding(.vertical, 16 * k)
        .padding(.horizontal, 18 * k)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private func ciPill(k: CGFloat) -> some View {
        HStack(spacing: 6 * k) {
            Circle()
                .fill(AerieColor.ok)
                .frame(width: 7 * k, height: 7 * k)
                .shadow(color: AerieColor.ok.opacity(0.6), radius: 4 * k)
            Text("CI passing")
                .font(.custom(AerieFont.sans, size: 11 * k).weight(.medium))
                .foregroundStyle(AerieColor.ok)
        }
        .padding(.vertical, 3 * k)
        .padding(.horizontal, 9 * k)
        .background(Capsule().fill(AerieColor.ok.opacity(0.10)))
        .overlay(Capsule().strokeBorder(AerieColor.ok.opacity(0.32), lineWidth: 1))
        .fixedSize()
    }

    // MARK: - Keyboard accelerators

    private var shortcutAccelerators: some View {
        // Zero-size, hidden buttons whose only job is to carry the ⌘ shortcuts.
        ZStack {
            Button("") { Task { await viewModel.zoomIn() } }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { Task { await viewModel.zoomIn() } }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { Task { await viewModel.zoomOut() } }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { Task { await viewModel.reset() } }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Building blocks

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }
}
