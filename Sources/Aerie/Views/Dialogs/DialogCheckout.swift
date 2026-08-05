import SwiftUI

/// The decision a force-checkout faces, derived purely from a PR's local state.
/// Mirrors the design's `aerieCheckoutPlan` (`v2/checkout.jsx`):
///   - `losses`      — the local work a force-checkout would discard.
///   - `destructive` — true when there's anything to lose (dirty / ahead /
///                     unpushed). Drives the dialog's red danger tone.
///   - `current`     — the repo is already on this branch, clean and level
///                     (checked out · not destructive · not behind).
///
/// Pure + `Equatable` so it's unit-testable without rendering the dialog, and so
/// the PR card's Checkout button can reuse it to tint its label.
struct CheckoutPlan: Equatable {
    let destructive: Bool
    let current: Bool
    let losses: [String]

    static func make(for local: PRLocalState?) -> CheckoutPlan {
        let dirty = local?.dirty ?? false
        let ahead = local?.ahead ?? 0
        let unpushed = local?.unpushed ?? 0
        let behind = local?.behind ?? 0
        let checkedOut = local?.isCurrentBranch ?? false

        var losses: [String] = []
        if dirty { losses.append("uncommitted working-tree changes") }
        if ahead > 0 {
            losses.append("\(ahead) local commit\(ahead > 1 ? "s" : "") ahead of origin")
        }
        if unpushed > 0 {
            losses.append("\(unpushed) unpushed commit\(unpushed > 1 ? "s" : "")")
        }
        let destructive = !losses.isEmpty
        let current = checkedOut && !destructive && behind == 0
        return CheckoutPlan(destructive: destructive, current: current, losses: losses)
    }
}

/// Confirmation dialog for force-checking-out the repo onto a PR's origin
/// branch. Tone switches on the local state: a destructive checkout (dirty /
/// ahead / unpushed) reads red and spells out what's discarded; a safe one reads
/// amber and reassures nothing local is at risk.
///
/// Carries no busy/error state of its own — `onConfirm` fires once,
/// synchronously; the caller closes the popover immediately and hands off to
/// `PRActionStore` for the actual (backgrounded) checkout + failure reporting.
///
/// Visual contract: `v2/checkout.jsx` `CheckoutOverlay`.
struct DialogCheckout: View {
    let repo: Repository
    let pr: PullRequest
    let local: PRLocalState?
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var branch: String { pr.sourceBranch }
    private var plan: CheckoutPlan { CheckoutPlan.make(for: local) }

    var body: some View {
        let plan = self.plan
        return ActionPopoverShell(
            tone: plan.destructive ? .danger : .warning,
            title: plan.destructive
                ? "Force checkout \(repo.name) to origin/\(branch)?"
                : "Check out origin/\(branch)?",
            subtitle: plan.destructive
                ? "This runs git checkout -f and resets the local branch to origin. The changes below are permanently discarded."
                : "Fetches origin and moves the local repo onto this PR’s branch. Nothing local is at risk.",
            primaryTitle: plan.destructive ? "Force checkout" : "Check out",
            onPrimary: onConfirm,
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            iconView: AnyView(checkoutIcon(destructive: plan.destructive)),
            primaryProminent: !plan.destructive
        ) {
            KVList(rows: rows(plan: plan))
        }
    }

    // MARK: - KV rows

    private func rows(plan: CheckoutPlan) -> [KVList.Row] {
        var rows: [KVList.Row] = [
            KVList.Row("repository", AnyView(mono("\(repo.githubOwner)/\(repo.githubRepo)"))),
            KVList.Row("target", AnyView(mono("origin/\(branch)"))),
            KVList.Row("command", AnyView(commandValue)),
        ]
        if plan.destructive {
            rows.append(KVList.Row("will discard", AnyView(
                Text(plan.losses.joined(separator: " · "))
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.err)
            )))
        } else {
            rows.append(KVList.Row("working tree", AnyView(
                Text(plan.current ? "already on this branch · clean" : "clean — nothing to discard")
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.ok)
            )))
        }
        return rows
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
    }

    private var commandValue: some View {
        Text("git checkout -f -B \(branch) origin/\(branch)")
            .aerieFont(AerieFont.code(11.5))
            .foregroundStyle(AerieColor.text1)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // The design's CheckoutGlyph, stroked to match the tone (red / amber) so it
    // reads correctly inside DialogShell's icon tile (which paints the bg/ring
    // but leaves a custom `iconView` to colour itself).
    private func checkoutIcon(destructive: Bool) -> some View {
        CheckoutGlyphShape()
            .stroke(
                destructive ? AerieColor.dangerText : AerieColor.amber,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 16, height: 16)
    }

}

/// The design's `CheckoutGlyph` (`v2/checkout.jsx`): a down-arrow dropping into
/// an open-topped tray — "check out into the working directory". Redrawn as a
/// Shape (16-unit viewBox) so it strokes crisply at any size, matching the
/// other hand-drawn SVG glyphs (e.g. `ChevronDownShape`).
struct CheckoutGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        // Vertical shaft — `M8 1.8v8.2`.
        path.move(to: p(8, 1.8))
        path.addLine(to: p(8, 10))
        // Down chevron — `M5 7.2 8 10.2l3-3`.
        path.move(to: p(5, 7.2))
        path.addLine(to: p(8, 10.2))
        path.addLine(to: p(11, 7.2))
        // Open-topped tray — `M2.6 11.4v1.2 a1.4 1.4 0 0 0 1.4 1.4 h8 a1.4 1.4 0 0 0 1.4-1.4 v-1.2`.
        path.move(to: p(2.6, 11.4))
        path.addLine(to: p(2.6, 12.6))
        path.addQuadCurve(to: p(4, 14), control: p(2.6, 14))
        path.addLine(to: p(12, 14))
        path.addQuadCurve(to: p(13.4, 12.6), control: p(13.4, 14))
        path.addLine(to: p(13.4, 11.4))
        return path
    }
}
