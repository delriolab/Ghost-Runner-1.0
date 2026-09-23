import SwiftUI

/// Screen 1: pick Baseball or Softball.
struct SportSelectionView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Upper half: logo centered
            Image("GhostLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 240)
                .accessibilityLabel("Ghost Runner")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Lower half: cards start near the middle, close to the logo
            VStack(spacing: 14) {
                ForEach(Sport.allCases) { sport in
                    NavigationLink(value: sport) {
                        HStack(alignment: .center) {
                            Text(sport.title)
                                .font(.title2.weight(.heavy))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Theme.accentBright)
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 20)
                        .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    .buttonStyle(SportCardButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Bordered card with a blue left edge that brightens and shrinks slightly while pressed.
private struct SportCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        configuration.label
            .background(configuration.isPressed ? Theme.sportCardPressed : Theme.sportCard)
            .overlay(shape.strokeBorder(Theme.sportCardBorder, lineWidth: 1.5))
            .overlay(alignment: .leading) {
                Theme.accent.frame(width: 4)
            }
            // Clipping rounds the accent bar's corners to match the card
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
