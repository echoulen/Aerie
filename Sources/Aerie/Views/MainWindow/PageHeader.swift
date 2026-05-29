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
    /// When provided, renders the right-aligned PRs/Repos toggle. Snapshot
    /// tests omit it.
    var tabSelection: Binding<MainTab>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .aerieFont(AerieFont.eyebrow())
                .tracking(2.2)                       // 0.22em @ 10pt
                .foregroundStyle(AerieColor.text4)

            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .aerieFont(AerieFont.pageTitle())
                        .tracking(-0.3)              // -0.012em @ 26pt
                        .foregroundStyle(AerieColor.text1)
                    Text(count)
                        .aerieFont(AerieFont.code(13))
                        .tracking(0.26)              // 0.02em @ 13pt
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer(minLength: 16)
                if let tabSelection {
                    SegmentedToggle(selection: tabSelection)
                }
            }
        }
        .padding(.top, 22)
    }
}
