import SwiftUI

/// Screen 1: pick Baseball or Softball.
struct SportSelectionView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("GhostLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            Text("Ghost Runner")
                .font(.largeTitle.bold())

            Spacer()

            VStack(spacing: 16) {
                ForEach(Sport.allCases) { sport in
                    NavigationLink(value: sport) {
                        Text(sport.title)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding()
    }
}
