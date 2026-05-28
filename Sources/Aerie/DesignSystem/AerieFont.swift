import SwiftUI

enum AerieFont {
    static let sans = "Inter"            // installed via the .app bundle (see Task 1.6)
    static let mono = "JetBrains Mono"

    // Common sizes
    static func display() -> Font  { .custom(sans, size: 30).weight(.light) }
    static func sectionTitle() -> Font  { .custom(sans, size: 22).weight(.medium) }
    static func body() -> Font      { .custom(sans, size: 13.5) }
    static func small() -> Font     { .custom(sans, size: 12) }
    static func eyebrow() -> Font   { .custom(mono, size: 10).weight(.medium) }
    static func code(_ size: CGFloat = 12) -> Font { .custom(mono, size: size) }
}
