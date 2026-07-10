import SwiftUI

/// The main-window page header shared by the PRs and Repos views.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `Header(...)` +
/// `styles.css` (`.section-eyebrow`, `.section-title`). Layout:
///   ┌──────────────────────────────────────────────────────────┐
///   │ VIEW · ⌘N                              (eyebrow, mono 10)  │
///   │ <Title>  <count>                       [ PRs | Repos ]     │
///   └──────────────────────────────────────────────────────────┘
/// The eyebrow sits above; the title (26pt medium) and mono count share a
/// baseline-aligned row, with the `SegmentedToggle` pinned to the trailing
/// edge and bottom-aligned to the title.
struct PageHeader: View {
    let eyebrow: String
    let title: String
    let count: String
    /// When provided, renders the right-aligned PRs/Issues/Repos toggle.
    /// Snapshot tests omit it.
    var tabSelection: Binding<MainTab>? = nil
    /// The real refresh to run when the header's Refresh button is tapped.
    /// Defaults to a no-op (snapshot tests / previews render the button only).
    var onRefresh: () async -> Void = {}
    /// An optional trailing control rendered just after the Refresh button —
    /// used by the Repositories header for its Add button. The title cluster is
    /// shared, so each screen injects its own extra action here.
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .aerieFont(AerieFont.eyebrow())
                .tracking(2.2)                       // 0.22em @ 10pt
                .foregroundStyle(AerieColor.text4)

            // The one-line header needs ~800pt; when it doesn't fit the count
            // and the tab toggle drop onto their own rows instead of forcing
            // the window wider. All the labels here are short fixed strings,
            // so ViewThatFits measures them reliably.
            ViewThatFits(in: .horizontal) {
                wideRow
                narrowRows
            }
        }
        .padding(.top, 22)
    }

    private var wideRow: some View {
        HStack(alignment: .bottom) {
            // Title + count share a baseline; the action buttons centre on
            // the title cluster (per the v2 `Header` row).
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .aerieFont(AerieFont.pageTitle())
                        .tracking(-0.3)          // -0.012em @ 26pt
                        .foregroundStyle(AerieColor.text1)
                    Text(count)
                        .aerieFont(AerieFont.code(13))
                        .tracking(0.26)          // 0.02em @ 13pt
                        .foregroundStyle(AerieColor.text3)
                }
                RefreshButton(action: onRefresh)
                if let trailing {
                    trailing
                }
            }
            Spacer(minLength: 16)
            if let tabSelection {
                SegmentedToggle(selection: tabSelection)
            }
        }
    }

    private var narrowRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Text(title)
                    .aerieFont(AerieFont.pageTitle())
                    .tracking(-0.3)
                    .foregroundStyle(AerieColor.text1)
                    .lineLimit(1)
                RefreshButton(action: onRefresh)
                if let trailing {
                    trailing
                }
                Spacer(minLength: 0)
            }
            Text(count)
                .aerieFont(AerieFont.code(13))
                .tracking(0.26)
                .foregroundStyle(AerieColor.text3)
            if let tabSelection {
                SegmentedToggle(selection: tabSelection)
            }
        }
    }
}
