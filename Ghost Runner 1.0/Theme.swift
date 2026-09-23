import SwiftUI

/// Ghost Runner visual style. The app is always shown in dark appearance.
enum Theme {
    static let background = Color.black                                            // #000000
    static let card = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255)   // #141416

    // Sport selection cards
    static let sportCard = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x23 / 255)        // #1F1F23
    static let sportCardPressed = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x30 / 255) // #2A2A30
    static let sportCardBorder = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x40 / 255)  // #3A3A40
    static let accentBright = Color(red: 0x4F / 255, green: 0x7C / 255, blue: 0xFF / 255)     // #4F7CFF, sport card chevrons

    static let divider = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255) // #2A2A2E, thin rules and card borders
    static let accent = Color(red: 0x28 / 255, green: 0x50 / 255, blue: 0xD2 / 255)  // #2850D2, Start button and selected states only
    static let label = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)   // #8E8E93, small labels
    static let text = Color.white

    // Sensor status dots
    static let ready = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)      // green
    static let connecting = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255) // amber
    static let disconnected = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255) // red

    static let cornerRadius: CGFloat = 16
}

extension View {
    /// Places the view on a dark rounded card.
    func card() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Small gray header above a group. Write titles in sentence case.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Dims a custom-drawn button while it is pressed.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
