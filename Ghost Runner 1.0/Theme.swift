import SwiftUI

/// Ghost Runner visual style, matching the ghostrunnerdefense.com redesign.
/// The app is always shown in dark appearance. Site variable names are in brackets.
enum Theme {
    static let background = Color(red: 0x0A / 255, green: 0x0F / 255, blue: 0x1C / 255) // #0A0F1C [night]
    static let card = Color(red: 0x11 / 255, green: 0x1A / 255, blue: 0x2B / 255)       // #111A2B [deck]
    static let cardPressed = Color(red: 0x16 / 255, green: 0x21 / 255, blue: 0x3A / 255) // #16213A [deck-2]
    static let divider = Color(red: 0x24 / 255, green: 0x33 / 255, blue: 0x52 / 255)    // #243352 [rule], thin rules and card borders

    static let text = Color(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xEA / 255)       // #EEF1EA [chalk]
    static let label = Color(red: 0x97 / 255, green: 0xA4 / 255, blue: 0xBC / 255)      // #97A4BC [mute], small labels

    static let accent = Color(red: 0x8B / 255, green: 0xE9 / 255, blue: 0xFF / 255)     // #8BE9FF [ghost], Start and selected states
    static let onAccent = Color(red: 0x0A / 255, green: 0x0F / 255, blue: 0x1C / 255)   // #0A0F1C [ink], text on the accent
    static let alert = Color(red: 0xFF / 255, green: 0x4B / 255, blue: 0x3E / 255)      // #FF4B3E [beep], Stop and Hair on fire
    static let onAlert = Color.white                                                    // text on the alert red, as on the site

    // Sensor status dots
    static let ready = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)      // green
    static let connecting = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255) // amber
    static let disconnected = alert                                                     // red

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
