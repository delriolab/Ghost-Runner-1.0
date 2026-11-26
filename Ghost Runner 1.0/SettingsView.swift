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

                Text("Log Out, Safe and errors after each rep, keep a roster and see rep history. Turn off to use the app exactly as before.")
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

                    Text("After the bat strike, call the play: \u{201C}Jake, out\u{201D}, \u{201C}Shortstop, got em\u{201D}, \u{201C}Safe\u{201D}, \u{201C}Glove error\u{201D}, \u{201C}Throwing error, number 7\u{201D}. Say \u{201C}Undo\u{201D} to take one back. Say it back repeats each call out loud.")
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
