import SwiftUI

/// A round avatar for a GitHub identity. Renders the account's real GitHub
/// avatar (fetched once per session via `AvatarStore`) and falls back to the
/// original design — a palette-hashed radial-gradient circle with uppercase
/// mono initials — while loading, offline, or for logins GitHub doesn't know.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` AccountCard and
/// `advanced.jsx` ACTIVE GH ACCOUNT card both render the same shape — a
/// radial gradient circle with an inset white highlight and 1–2 mono
/// initials in a near-black warm tone (`oklch(0.15 0.02 70)`).
struct AccountAvatar: View {
    let login: String
    var size: CGFloat = 42

    @State private var remote: NSImage?

    var body: some View {
        // Prefer the freshly-loaded image, then the store's cache (so a
        // second view of the same login shows the avatar on its first frame,
        // before its own `.task` fires), then the initials fallback.
        let image = remote ?? AvatarStore.shared.cachedImage(for: login)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                fallbackCircle
            }
            // Inset highlight on the top edge — matches the spec's
            // `boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.35)'`. Kept over
            // the photo too so both states share the design's glass finish.
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .frame(width: size, height: size)
        .task(id: login) {
            // Reset before awaiting so a reused view never shows the previous
            // login's photo while the new one loads.
            remote = AvatarStore.shared.cachedImage(for: login)
            if remote == nil {
                remote = await AvatarStore.shared.image(for: login)
            }
        }
    }

    private var fallbackCircle: some View {
        let tone = Self.tone(for: login)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tone.highlight, tone.shade],
                        center: UnitPoint(x: 0.30, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.85
                    )
                )
            Text(Self.initials(for: login))
                .font(.system(size: size * 0.30, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.10))
        }
    }

    // MARK: - Static helpers (exposed for tests / re-use in Advanced)

    /// Tone palette — five distinct radial-gradient pairs so each tracked
    /// gh identity gets a visually-stable colour. Stop colours are
    /// approximations of the spec's `oklch(L C H)` values converted to sRGB
    /// hex; the highlight is the lighter / inner stop and the shade is the
    /// darker / outer stop.
    struct Tone {
        let highlight: Color
        let shade: Color
    }

    /// Five-tone palette covering the design's amber / blue / violet + two
    /// additions (green, coral) so dashboards with 4+ accounts still read
    /// distinctly.
    private static let palette: [Tone] = [
        Tone(highlight: Color(hex: 0xF1C98F), shade: Color(hex: 0xB58748)), // amber
        Tone(highlight: Color(hex: 0x8FBDEC), shade: Color(hex: 0x4C6FA7)), // blue
        Tone(highlight: Color(hex: 0xC18FE0), shade: Color(hex: 0x7B47A3)), // violet
        Tone(highlight: Color(hex: 0x8FE0B8), shade: Color(hex: 0x437D5B)), // green
        Tone(highlight: Color(hex: 0xE89998), shade: Color(hex: 0xA84F4D)), // coral
    ]

    static func tone(for login: String) -> Tone {
        palette[paletteIndex(for: login)]
    }

    /// 1–2 letter abbreviation. Splits on `-` first (the gh convention
    /// `<first>-<last>` produces `CL`-style initials matching the spec's
    /// mocks); falls back to the first two characters for camel-case logins
    /// like `NextDriveBot`.
    static func initials(for login: String) -> String {
        let parts = login.split(separator: "-")
        if parts.count >= 2 {
            let chars = parts.prefix(2).compactMap { $0.first }
            return String(chars).uppercased()
        }
        return String(login.prefix(2)).uppercased()
    }

    // Deterministic across runs (unlike `String.hashValue`) so the same login
    // always lands on the same colour, even after relaunches and across
    // different machines.
    private static func paletteIndex(for s: String) -> Int {
        let sum = s.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % palette.count
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
