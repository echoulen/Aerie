import AppKit

/// Pure mapping from an `UpdateOutcome` to the strings + buttons an `NSAlert`
/// needs. Pulled out of the presenter so the copy — including the Gatekeeper
/// first-open hint — is unit-testable without touching AppKit.
struct UpdateAlertContent: Equatable {
    let title: String
    let informative: String
    /// Button titles; the first is the default. For `.updateAvailable` the first
    /// button triggers the download and `downloadURL` is non-nil.
    let buttons: [String]
    let downloadURL: URL?

    /// Shared first-open guidance — also pasted into the release notes (see the
    /// Makefile `release` target) so the two touchpoints stay in sync.
    static let firstOpenHint =
        "First launch: right-click Aerie.app → Open (macOS blocks the first open of a self-signed build)."

    init(outcome: UpdateOutcome) {
        switch outcome {
        case .upToDate(let current):
            title = "You're up to date"
            informative = "Aerie \(current) is the latest version."
            buttons = ["OK"]
            downloadURL = nil
        case .updateAvailable(let current, let latest, let url):
            title = "Update Available"
            informative = """
            Aerie \(latest) is available (you have \(current)).

            \(Self.firstOpenHint)
            """
            buttons = ["Download", "Later"]
            downloadURL = url
        case .failed(let message):
            title = "Couldn't Check for Updates"
            informative = message
            buttons = ["OK"]
            downloadURL = nil
        }
    }
}

/// Thin `@MainActor` driver: run the check, then show the alert and, on the
/// download button, open the release page in the browser. AppKit boundary — no
/// unit test; the mapping it relies on (`UpdateAlertContent`) is tested instead.
@MainActor
enum UpdatePresenter {
    /// The menu's "Check for Updates…". Routes through the shared `UpdateStore`
    /// so an available release also lights the titlebar pill, then reports the
    /// same outcome in an alert. The alert's Download button still opens the
    /// release page — the escape hatch for a build that can't self-install.
    static func checkAndPresent(store: UpdateStore) {
        Task { @MainActor in
            let outcome = await store.checkNow()
            present(UpdateAlertContent(outcome: outcome))
        }
    }

    /// Confirms an in-app update. Worth a prompt because the installer's first
    /// act is to quit Aerie out from under whatever the user was doing.
    static func confirmInstall(latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Update to Aerie \(latest)?"
        alert.informativeText = "Aerie will quit, install the update, and relaunch itself."
        alert.addButton(withTitle: "Update & Relaunch")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func present(_ content: UpdateAlertContent) {
        let alert = NSAlert()
        alert.messageText = content.title
        alert.informativeText = content.informative
        for title in content.buttons { alert.addButton(withTitle: title) }
        let response = alert.runModal()
        if let url = content.downloadURL, response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }
}
