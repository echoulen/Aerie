import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `DialogShell` across the three tones (neutral,
/// warning, danger) plus the optional error banner. Each test renders the
/// dialog on a `Backdrop` so the modal sits in its main-window context
/// (1240x880).
final class DialogShellTests: XCTestCase {
    private func snapshot<V: View>(_ view: V) -> NSHostingView<some View> {
        let host = ZStack {
            Backdrop()
            view
        }
        .frame(width: 1240, height: 880)
        return NSHostingView(rootView: host)
    }

    func test_dialogShell_neutralTone() {
        let view = DialogShell(
            tone: .neutral,
            title: "Remove Aerie from Aerie?",
            subtitle: "This only removes it from the tracked list. Nothing on disk will change.",
            primaryTitle: "Remove",
            onPrimary: { },
            secondaryTitle: "Cancel",
            onSecondary: { }
        ) {
            KVList(pairs: [
                ("Local path", "/Users/dev/work/aerie"),
                ("GitHub", "carlos-li/aerie"),
                ("Will delete", "nothing on disk"),
            ])
        }
        assertSnapshot(of: snapshot(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    func test_dialogShell_dangerToneWithError() {
        let view = DialogShell(
            tone: .danger,
            title: "Hard reset Aerie to origin/main?",
            subtitle: "This is destructive and cannot be undone.",
            primaryTitle: "Reset to origin/main",
            onPrimary: { },
            secondaryTitle: "Cancel",
            onSecondary: { },
            primaryDisabled: false,
            errorMessage: "fatal: unable to access 'origin': could not resolve host"
        ) {
            KVList(pairs: [
                ("Repository", "carlos-li/aerie"),
                ("Current branch", "feat/phase17-dialogs"),
                ("Working tree", "3 modified"),
                ("Ahead of origin", "2"),
                ("Behind of origin", "1"),
                ("Unpushed commits", "2"),
            ])
        }
        assertSnapshot(of: snapshot(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    func test_dialogShell_warningTone() {
        let view = DialogShell(
            tone: .warning,
            title: "Merge PR #142?",
            subtitle: "Wire the PR card to PRLocalState and add ready-to-ship eyebrow",
            primaryTitle: "Squash and merge",
            onPrimary: { },
            secondaryTitle: "Cancel",
            onSecondary: { }
        ) {
            Text("Squash merge will be performed via the configured GitHub account.")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        assertSnapshot(of: snapshot(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
