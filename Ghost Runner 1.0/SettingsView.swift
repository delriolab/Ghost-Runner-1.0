import SwiftUI

/// Settings screen, reached from the gear on the setup and Game Break screens.
struct SettingsView: View {
    let onTestBuzzer: () -> Void
    @AppStorage("gameBreakSimulateTaps") private var simulateTaps = false
    @AppStorage(ProAccess.enabledKey) private var proEnabled = false
    @AppStorage("proVoice") private var voiceEnabled = true
    @AppStorage("proSayItBack") private var sayItBack = true

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

                Text("Logs every rep for whoever is fielding: an out unless you call safe. See it all in Rep History on the home screen. Turn off to use the app exactly as before.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)

                if proEnabled {
                    VStack(spacing: 0) {
                        Toggle(isOn: $voiceEnabled) {
                            Text("Voice logging")
                                .foregroundStyle(Theme.text)
                        }
                        .frame(minHeight: 52)
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 0.5)
                        Toggle(isOn: $sayItBack) {
                            Text("Say it back")
                                .foregroundStyle(Theme.text)
                        }
                        .frame(minHeight: 52)
                        .disabled(!voiceEnabled)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .card()

                    Text("Say who\u{2019}s fielding: 1 pitcher, 2 catcher, 3 first, 4 second, 5 third, 6 short, 7 left, 8 center, 9 right. It stays until you say another. Say \u{201C}safe\u{201D} when the runner beats the play; every other rep is an out. \u{201C}Turn two\u{201D} or \u{201C}roll it\u{201D} with where it\u{2019}s fielded calls a double play: 5 is 5-4-3, 6 is 6-4-3, 4 is 4-6-3, 3 is 3-6-3. \u{201C}Undo\u{201D} takes back the last rep. \u{201C}Ghost Runner pause\u{201D} and \u{201C}Ghost Runner resume\u{201D} work like the Pause button. Say it back repeats what it heard.")
                        .font(.footnote)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 16)
                }

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
