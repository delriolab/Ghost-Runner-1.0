import SwiftUI

/// Settings screen, reached from the gear on the setup screen.
struct SettingsView: View {
    let onTestBuzzer: () -> Void

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
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
