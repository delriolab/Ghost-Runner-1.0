import SwiftUI

/// Settings screen, reached from the gear on the setup and Game Break screens.
struct SettingsView: View {
    let onTestBuzzer: () -> Void
    @AppStorage("gameBreakSimulateTaps") private var simulateTaps = false
    @AppStorage(ProAccess.enabledKey) private var proEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Sound")

                Button(action: onTestBuzzer) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Theme.label)
                        Text("Test buzzer")
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .card()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())

                Text("Plays the buzzer through the current audio output.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)

                SectionHeader("Ghost Runner Pro")
                    .padding(.top, 16)

                Toggle(isOn: $proEnabled) {
                    Text("Pro features (test)")
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .card()

                Text("Log Out, Safe and errors after each rep, keep a roster and see rep history. Turn off to use the app exactly as before.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)

                SectionHeader("Developer")
                    .padding(.top, 16)

                Toggle(isOn: $simulateTaps) {
                    Text("Simulate puck taps")
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .card()

                Text("Game Break shows a button that acts like tapping the puck, so it can be tried without one.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
