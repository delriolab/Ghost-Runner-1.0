import SwiftUI

/// Screen 2: shows the selected time and lets the coach set up the drill.
struct SetupView: View {
    let sport: Sport
    @Binding var category: String
    @Binding var drill: String
    @Binding var intensity: Intensity

    let selectedTime: Double?
    let remainingTime: Double
    let timerRunning: Bool
    let connectionStatus: String
    let monitoring: Bool

    let onStart: () -> Void
    let onStop: () -> Void
    let onTestBuzzer: () -> Void

    private var times: SportTimes { StandardTimes.table(for: sport) }

    private var bigNumber: String {
        if timerRunning {
            return String(format: "%.1f", remainingTime)
        }
        guard let selectedTime else { return "—" }
        return String(format: "%.1f", selectedTime)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    Text(bigNumber)
                        .font(.system(size: 110, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(timerRunning ? "seconds left" : "seconds")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                Picker(times.categoryLabel, selection: $category) {
                    ForEach(times.categories, id: \.self) { Text($0).tag($0) }
                }
                Picker("Drill", selection: $drill) {
                    ForEach(times.drills, id: \.self) { Text($0).tag($0) }
                }
            }

            Section {
                Picker("Intensity", selection: $intensity) {
                    ForEach(Intensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                LabeledContent("Sensor", value: connectionStatus)
            }
        }
        .navigationTitle(sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Test buzzer", systemImage: "speaker.wave.2", action: onTestBuzzer)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                monitoring ? onStop() : onStart()
            } label: {
                Text(monitoring ? "Stop" : "Start")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(monitoring ? .red : .accentColor)
            .disabled(selectedTime == nil && !monitoring)
            .padding()
        }
    }
}
