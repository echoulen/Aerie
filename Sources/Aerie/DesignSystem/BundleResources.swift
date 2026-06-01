import Foundation

extension Bundle {
    /// The SwiftPM resource bundle (`Aerie_Aerie.bundle`), resolved for BOTH the
    /// `swift build` / test layout and the hand-assembled `.app`.
    ///
    /// SwiftPM's generated `Bundle.module` accessor only checks two paths:
    /// `Bundle.main.bundleURL/Aerie_Aerie.bundle` (the `.app` *root* — a loose
    /// bundle there fails code signing, so we don't ship it there) and a
    /// build-time *absolute* path that exists only on the machine that compiled
    /// the binary. In the shipped `.app` the bundle lives in `Contents/Resources/`
    /// (where `make app` copies it, which keeps the signature valid), so on any
    /// other machine `Bundle.module` finds neither path and fatal-errors on
    /// launch — which crashed the released build inside `Backdrop`.
    ///
    /// This resolver checks `Contents/Resources/Aerie_Aerie.bundle` first (the
    /// `.app` case) and only falls back to `.module` for `swift test` /
    /// `swift run`, where the build-dir path resolves. Use it instead of
    /// `.module` for every shipped resource lookup.
    static let aerieResources: Bundle = {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Aerie_Aerie.bundle")
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return .module
    }()
}
